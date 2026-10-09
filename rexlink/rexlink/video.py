"""Видео с телефона: экран (показ в Настройках шелла) и камера (v4l2loopback + превью).

Пакеты потока: u32 длина | u8 тип | данные. Тип 0 — JSON {w, h}, тип 1 — H.264 Annex-B.
Перед каждым ключевым кадром телефон повторяет SPS/PPS, поэтому декодер можно
перезапустить в любой момент, запросив ключевой кадр.
"""
import glob
import json
import os
import shutil
import struct
import subprocess
import threading
import time

from PySide6.QtCore import QObject, Qt, Signal, Slot
from PySide6.QtGui import QImage

from .net import read_exact
from .proc import popen

FFMPEG_IN = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
             # без -fflags nobuffer: в ffmpeg 9 с ним декодер не отдаёт кадры из канала
             "-flags", "low_delay", "-probesize", "32", "-analyzeduration", "0",
             "-threads", "1", "-f", "h264", "-i", "pipe:0"]


DUMP = os.environ.get("REXLINK_DUMP")  # отладка: сохранять входящий H.264


COLOR_FIX = "setparams=colorspace=bt709:color_primaries=bt709:color_trc=bt709"


def find_loopback(preferred="auto"):
    if preferred and preferred != "auto":
        return preferred if os.path.exists(preferred) else None
    found = []
    for d in sorted(glob.glob("/sys/class/video4linux/video*")):
        try:
            name = open(os.path.join(d, "name")).read().strip()
        except OSError:
            continue
        dev = "/dev/" + os.path.basename(d)
        low = name.lower()
        if "rexlink" in low:
            return dev
        if "dummy video device" in low or "loopback" in low or "v4l2loopback" in low:
            found.append(dev)
    return found[0] if found else None


class FrameStore(QObject):
    """Последние кадры по каналам ("screen:<id>", "camera"); живёт в главном потоке.

    Окна у службы нет — картинку показывает шелл. Пока он смотрит канал (команда API
    `frames`), кадры пишутся JPEG-файлами в $XDG_RUNTIME_DIR/rexlink/frames/ (tmpfs)
    по кругу из трёх файлов, о каждом — сигнал exported (→ событие API "frame").
    """
    frame = Signal(str, QImage)
    status = Signal(str, str)   # канал, текст ошибки/состояния
    exported = Signal(str, str, int, int, int)   # канал, путь, ширина, высота, номер

    INTERVAL = 1 / 30          # не чаще 30 кадров в секунду

    def __init__(self, out_dir=None):
        super().__init__()
        self.images = {}
        self.watch = {}        # канал -> число смотрящих
        self.out_dir = out_dir
        self._seq = {}
        self._last = {}
        if out_dir:            # кадры прошлого запуска
            for f in glob.glob(os.path.join(out_dir, "*.jpg")):
                try:
                    os.remove(f)
                except OSError:
                    pass
        # кадры приходят из потоков ffmpeg — обрабатываем только в главном потоке
        self.frame.connect(self._store, Qt.ConnectionType.QueuedConnection)

    def set_watch(self, ch, on):
        n = self.watch.get(ch, 0) + (1 if on else -1)
        if n > 0:
            self.watch[ch] = n
            img = self.images.get(ch)
            if img is not None:          # сразу отдать последний кадр
                self._last[ch] = 0
                self._export(ch, img)
        else:
            self.watch.pop(ch, None)

    @Slot(str, QImage)
    def _store(self, ch, img):
        self.images[ch] = img
        if ch in self.watch and time.monotonic() - self._last.get(ch, 0) >= self.INTERVAL:
            self._export(ch, img)

    def _export(self, ch, img):
        if not self.out_dir:
            return
        self._last[ch] = time.monotonic()
        seq = self._seq.get(ch, 0) + 1
        self._seq[ch] = seq
        safe = "".join(c if c.isalnum() else "_" for c in ch)
        path = os.path.join(self.out_dir, f"{safe}.{seq % 3}.jpg")
        try:
            os.makedirs(self.out_dir, exist_ok=True)
            if img.save(path, "JPG", 85):
                self.exported.emit(ch, path, img.width(), img.height(), seq)
        except OSError:
            pass


STORE = None


class Decoder:
    """ffmpeg: H.264 на вход, кадры BGR0 на выход (и, для камеры, вывод в v4l2)."""

    def __init__(self, channel, w, h, sink=None, filters="", preview_w=None):
        self.channel = channel
        self.w, self.h = w, h
        self.sink = sink
        self.alive = True
        self.frames = 0
        self.errors = []
        # некоторые кодировщики (Qualcomm на Xiaomi) помечают поток как YCgCo — ffmpeg его не конвертирует;
        # экран и камера Android — это bt709, задаём явно
        vf = ",".join(x for x in (COLOR_FIX, filters) if x)
        if sink:
            # кадр для v4l2 + уменьшенное превью
            ow, oh = (h, w) if "transpose" in filters else (w, h)
            pw = preview_w or 480
            ph = max(2, round(pw * oh / ow / 2) * 2)
            self.pw, self.ph = pw, ph
            graph = (f"[0:v]{vf},format=yuv420p,split=2[cam][pv];"
                     f"[pv]scale={pw}:{ph},format=bgr0[out]")
            cmd = FFMPEG_IN + ["-filter_complex", graph,
                               "-map", "[cam]", "-f", "v4l2", sink,
                               "-map", "[out]", "-fps_mode", "passthrough", "-f", "rawvideo", "pipe:1"]
        else:
            self.pw, self.ph = w, h
            cmd = FFMPEG_IN + ["-vf", f"{vf},scale={w}:{h},format=bgr0", "-fps_mode", "passthrough",
                               "-f", "rawvideo", "pipe:1"]
        self.proc = popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     bufsize=0)
        threading.Thread(target=self._read_frames, daemon=True).start()
        threading.Thread(target=self._read_err, daemon=True).start()

    def _read_err(self):
        for line in self.proc.stderr:
            msg = line.decode(errors="replace").strip()
            if msg:
                print(f"ffmpeg[{self.channel}]:", msg)
                self.errors = (self.errors + [msg])[-5:]
                if "v4l2" in msg.lower() or "/dev/video" in msg:
                    STORE.status.emit(self.channel, msg)

    def _read_frames(self):
        size = self.pw * self.ph * 4
        buf = bytearray(size)
        view = memoryview(buf)
        out = self.proc.stdout
        try:
            while self.alive:
                got = 0
                while got < size:
                    n = out.readinto(view[got:])
                    if not n:
                        return
                    got += n
                img = QImage(bytes(buf), self.pw, self.ph, self.pw * 4, QImage.Format.Format_RGB32)
                self.frames += 1
                STORE.frame.emit(self.channel, img)
        except (OSError, ValueError):
            pass
        finally:
            # ffmpeg упал, не выдав ни кадра, — сообщаем, а не ждём вечно
            if self.alive and self.frames == 0:
                time.sleep(0.2)
                err = next((e for e in reversed(self.errors) if "rror" in e), self.errors[-1] if self.errors else "")
                STORE.status.emit(self.channel, f"декодер не запустился: {err[:160]}")

    def feed(self, data):
        try:
            self.proc.stdin.write(data)
        except (OSError, ValueError):
            self.alive = False

    def close(self):
        self.alive = False
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        try:
            self.proc.terminate()
            self.proc.wait(2)
        except Exception:
            self.proc.kill()


class VideoStream:
    """Приём одного видеопотока из сокета (выполняется в потоке сокета)."""

    def __init__(self, channel, make_decoder, on_config=None, on_end=None):
        self.channel = channel
        self.make_decoder = make_decoder
        self.on_config = on_config
        self.on_end = on_end
        self.decoder = None
        self.config = None
        self.sock = None
        self.stopped = False
        self._restart = False

    def restart_decoder(self):
        self._restart = True

    def run(self, sock):
        self.sock = sock
        sock.settimeout(15)
        try:
            while not self.stopped:
                (n,) = struct.unpack(">I", read_exact(sock, 4))
                kind = read_exact(sock, 1)[0]
                data = read_exact(sock, n - 1) if n > 1 else b""
                if kind == 0:
                    self.config = json.loads(data)
                    self._new_decoder()
                elif kind == 1 and DUMP:
                    with open(f"{DUMP}.{self.channel}.h264", "ab") as f:
                        f.write(data)
                if kind == 1 and self.decoder:
                    if self._restart:
                        self._restart = False
                        self._new_decoder()
                    self.decoder.feed(data)
        except Exception as e:  # noqa: BLE001
            if not self.stopped:
                print(f"{self.channel} stream ended: {e!r}")
        finally:
            if self.decoder:
                self.decoder.close()
                self.decoder = None
            if self.on_end:
                self.on_end()

    def _new_decoder(self):
        if self.decoder:
            self.decoder.close()
        self.decoder = self.make_decoder(int(self.config["w"]), int(self.config["h"]))
        if self.on_config:
            self.on_config(self.config)

    def stop(self):
        self.stopped = True
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass


class _Bits:
    """Чтение битов и exp-Golomb для разбора SPS."""

    def __init__(self, data):
        self.d = data
        self.i = 0

    def bit(self):
        b = (self.d[self.i >> 3] >> (7 - (self.i & 7))) & 1
        self.i += 1
        return b

    def bits(self, n):
        v = 0
        for _ in range(n):
            v = (v << 1) | self.bit()
        return v

    def ue(self):
        z = 0
        while self.bit() == 0:
            z += 1
        return (1 << z) - 1 + self.bits(z)

    def se(self):
        v = self.ue()
        return (v + 1) // 2 if v & 1 else -(v // 2)


def sps_size(nal):
    """Размер кадра из SPS (nal — без стартового кода, с байтом заголовка). None, если не разобрать."""
    try:
        rbsp = bytearray()
        zeros = 0
        for b in nal[1:]:   # убираем emulation prevention (00 00 03)
            if zeros >= 2 and b == 3:
                zeros = 0
                continue
            rbsp.append(b)
            zeros = zeros + 1 if b == 0 else 0
        r = _Bits(rbsp)
        profile = r.bits(8)
        r.bits(16)
        r.ue()
        chroma = 1
        if profile in (100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135):
            chroma = r.ue()
            if chroma == 3:
                r.bit()
            r.ue(); r.ue(); r.bit()
            if r.bit():
                for i in range(8 if chroma != 3 else 12):
                    if r.bit():
                        last, nxt = 8, 8
                        for _ in range(16 if i < 6 else 64):
                            if nxt:
                                nxt = (last + r.se() + 256) % 256
                            last = nxt or last
        r.ue()
        poc = r.ue()
        if poc == 0:
            r.ue()
        elif poc == 1:
            r.bit(); r.se(); r.se()
            for _ in range(r.ue()):
                r.se()
        r.ue(); r.bit()
        w_mbs = r.ue() + 1
        h_map = r.ue() + 1
        frame_mbs_only = r.bit()
        if not frame_mbs_only:
            r.bit()
        r.bit()
        w, h = w_mbs * 16, h_map * 16 * (2 - frame_mbs_only)
        if r.bit():   # обрезка
            cl, cr, ct, cb = r.ue(), r.ue(), r.ue(), r.ue()
            cx = 1 if chroma in (0, 3) else 2
            cy = (2 if chroma == 1 else 1) * (2 - frame_mbs_only)
            w -= (cl + cr) * cx
            h -= (ct + cb) * cy
        return w, h
    except (IndexError, ValueError):
        return None


class RawVideoStream:
    """Сырой H.264 без заголовков (scrcpy-server raw_stream): размер берём из SPS,
    при повороте (новый SPS с другим размером) пересоздаём декодер."""

    def __init__(self, channel, make_decoder, on_config=None, on_end=None, on_stop=None):
        self.channel = channel
        self.make_decoder = make_decoder
        self.on_config = on_config
        self.on_end = on_end
        self.on_stop = on_stop
        self.decoder = None
        self.size = None
        self.sock = None
        self.stopped = False

    def restart_decoder(self):
        pass   # scrcpy сам шлёт SPS+IDR при перезапуске кодировщика

    def run(self, sock, first=b""):
        self.sock = sock
        sock.settimeout(20)
        pending = first
        try:
            while not self.stopped:
                chunk = sock.recv(1 << 16)
                if not chunk:
                    break
                data = pending + chunk
                pending = b""
                pos = 0
                while True:
                    i = data.find(b"\x00\x00\x01", pos)
                    if i < 0 or i + 3 >= len(data):
                        break
                    if data[i + 3] & 0x1F == 7:
                        if len(data) - i < 64:          # SPS обрезан на границе — дочитаем
                            start = i - 1 if i > 0 and data[i - 1] == 0 else i
                            self._feed(data[:start])
                            pending = data[start:]
                            data = b""
                            break
                        end = data.find(b"\x00\x00\x01", i + 3)
                        size = sps_size(data[i + 3:end if end > 0 else len(data)])
                        if size and size != self.size:
                            start = i - 1 if i > 0 and data[i - 1] == 0 else i
                            self._feed(data[:start])
                            data = data[start:]
                            pos = 4
                            self._new_decoder(size)
                            continue
                    pos = i + 3
                if data:
                    self._feed(data)
        except Exception as e:  # noqa: BLE001
            if not self.stopped:
                print(f"{self.channel} raw stream ended: {e!r}")
        finally:
            if self.decoder:
                self.decoder.close()
                self.decoder = None
            if self.on_end:
                self.on_end()

    def _feed(self, data):
        if data and self.decoder:
            if DUMP:
                with open(f"{DUMP}.{self.channel}.h264", "ab") as f:
                    f.write(data)
            self.decoder.feed(data)

    def _new_decoder(self, size):
        if self.decoder:
            self.decoder.close()
        self.size = size
        self.decoder = self.make_decoder(*size)
        if self.on_config:
            self.on_config({"w": size[0], "h": size[1], "source": "adb"})

    def stop(self):
        self.stopped = True
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        if self.on_stop:
            self.on_stop()


def ffmpeg_available():
    return bool(shutil.which("ffmpeg"))


def camera_filters(rotate, mirror):
    f = []
    if rotate == 90:
        f.append("transpose=1")
    elif rotate == 270:
        f.append("transpose=2")
    elif rotate == 180:
        f.append("hflip,vflip")
    if mirror:
        f.append("hflip")
    return ",".join(f)
