"""Устройство (планшет, телефон) как дополнительный монитор ПК — по Wi-Fi или по USB.

niri не умеет виртуальные мониторы, поэтому включаем свободный разъём видеокарты с подставным EDID
под экран устройства (rexlink-display с правами root через pkexec; правило polkit — без пароля).
Композитор видит обычный монитор. Его картинку снимаем по wlr-screencopy (wlcapture), ffmpeg кодирует
в H.264 на видеокарте, поток идёт на устройство по TLS. По USB — тот же TLS через `adb reverse`.
Касания приходят обратно и становятся мышью (uinput).

Пакеты потока: u32 длина | u8 тип | данные.
  устройство → ПК: 0 — JSON {w, h, density} (первым); 3 — JSON касания
  ПК → устройство: 0 — JSON {w, h}; 1 — кадр H.264 (Annex-B); 2 — SPS/PPS; 4 — JSON {error}
"""
import fcntl
import glob
import json
import os
import re
import select
import shutil
import socket
import ssl
import struct
import subprocess
import threading
import time

from .net import read_exact
from .wlcapture import Capture, WaylandError

HELPER = "/usr/local/lib/rexlink/rexlink-display"
USB_PORT = 47830            # порт на устройстве для adb reverse


class DisplayError(Exception):
    pass


# ── EDID: один режим под экран устройства (CVT с сокращённым гашением)
def cvt_rb(w, h, hz):
    hblank, hfp, hsync = 160, 48, 32
    vfp, vsync, min_vbp = 3, 6, 6
    h_period = (1_000_000 / hz - 460) / h                   # мкс на строку
    vblank = max(int(460 / h_period) + 1, vfp + vsync + min_vbp)
    pclk = (w + hblank) * (h + vblank) * hz // 1000        # кГц
    pclk = pclk // 250 * 250
    return pclk, hblank, hfp, hsync, vblank, vfp, vsync


def make_edid(w, h, hz=60, mm=(0, 0), name="Rexlink"):
    pclk, hb, hfp, hs, vb, vfp, vs = cvt_rb(w, h, hz)
    if pclk // 10 > 0xFFFF or w > 4095 or h > 4095:
        raise DisplayError(f"режим {w}x{h}@{hz} не помещается в EDID")
    wmm, hmm = mm
    e = bytearray(b"\x00\xff\xff\xff\xff\xff\xff\x00")
    e += struct.pack(">H", (ord("R") - 64) << 10 | (ord("X") - 64) << 5 | (ord("L") - 64))
    e += struct.pack("<HI", 0x0001, 0x00000001)
    e += bytes([1, 2026 - 1990, 1, 3])                       # неделя, год, EDID 1.3
    e += bytes([0x80, max(1, wmm // 10) if wmm else 0, max(1, hmm // 10) if hmm else 0, 120, 0x0A])
    e += bytes([0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54])   # цвета sRGB
    e += bytes(3) + b"\x01\x01" * 8
    dtd = struct.pack("<H", pclk // 10) + bytes([
        w & 0xFF, hb & 0xFF, (w >> 8) << 4 | hb >> 8,
        h & 0xFF, vb & 0xFF, (h >> 8) << 4 | vb >> 8,
        hfp & 0xFF, hs & 0xFF, (vfp & 0xF) << 4 | (vs & 0xF),
        (hfp >> 8) << 6 | (hs >> 8) << 4 | (vfp >> 4) << 2 | vs >> 4,
        wmm & 0xFF, hmm & 0xFF, (wmm >> 8) << 4 | hmm >> 8, 0, 0, 0x1A])
    e += dtd
    e += bytes([0, 0, 0, 0xFC, 0]) + (name[:12] + "\n").encode().ljust(13, b" ")
    hfreq = pclk // (w + hb)                                  # кГц
    e += bytes([0, 0, 0, 0xFD, 0, max(1, hz - 10), hz + 15, max(1, hfreq - 10), min(255, hfreq + 10),
                min(255, pclk // 10000 + 1), 0, 0x0A]) + b" " * 6
    e += bytes([0, 0, 0, 0x10, 0]) + bytes(13)
    e += bytes([0])                                           # расширений нет
    e.append((-sum(e)) & 0xFF)
    assert len(e) == 128
    return bytes(e)


def fit_mode(w, h, max_size):
    """Режим монитора: экран устройства в альбомной ориентации, длинная сторона не больше max_size."""
    w, h = max(w, h), min(w, h)
    k = min(1.0, max_size / w)
    mw = int(w * k) // 8 * 8
    mh = int(h * k) // 2 * 2
    return mw, mh


def niri_scale(density, mode_w, real_w):
    """Масштаб в niri: интерфейс чуть мельче, чем у самого планшета, кратно 0.25."""
    s = density * 0.75 * mode_w / max(real_w, 1)
    return max(1.0, min(3.0, round(s * 4) / 4))


# ── разъём видеокарты
def free_connectors():
    """Свободные разъёмы: (имя в sysfs, имя для композитора), сначала HDMI, потом DP и DVI."""
    out = []
    for st in sorted(glob.glob("/sys/class/drm/card*-*/status")):
        name = st.split("/")[-2]
        conn = name.split("-", 1)[1]
        if conn.startswith(("eDP", "LVDS", "DSI", "Writeback", "Virtual", "Unknown")):
            continue
        try:
            status = open(st).read().strip()
            ours = status != "disconnected" and b"Rexlink" in open(st[:-6] + "edid", "rb").read()
        except OSError:
            continue
        # «connected» с нашим EDID — остался от прошлого сеанса, разъём свободен
        if status == "disconnected" or ours:
            out.append((name, conn))
    rank = {"HDMI": 0, "DP": 1, "DVI": 2}
    out.sort(key=lambda x: rank.get(x[1].split("-")[0], 3))
    return out


def helper(action, sysname, edid=b""):
    if not os.path.exists(HELPER):
        raise DisplayError("не установлен помощник rexlink-display — запустите install.sh из дотфайлов")
    r = subprocess.run(["pkexec", HELPER, action, sysname], input=edid, capture_output=True, timeout=30)
    if r.returncode != 0:
        err = (r.stderr or r.stdout).decode(errors="replace").strip()
        raise DisplayError(err.splitlines()[-1] if err else f"rexlink-display {action}: код {r.returncode}")


def niri_outputs():
    try:
        r = subprocess.run(["niri", "msg", "-j", "outputs"], capture_output=True, text=True, timeout=3)
        return json.loads(r.stdout) if r.returncode == 0 else {}
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {}


def niri(*args):
    subprocess.run(["niri", "msg", *args], capture_output=True, timeout=3)


def has_output_config(connector):
    """Задан ли монитор в конфиге niri (по порту или по имени Rexlink) — тогда масштаб не трогаем."""
    pat = re.compile(r'^\s*output\s+"(' + re.escape(connector) + r'|PNP\(RXL\) Rexlink[^"]*)"', re.M)
    for f in glob.glob(os.path.expanduser("~/.config/niri/*.kdl")):
        try:
            if pat.search(open(f, encoding="utf-8", errors="replace").read()):
                return True
        except OSError:
            pass
    return False


def cleanup_stale(keep=""):
    """Выключить виртуальные мониторы, оставшиеся от прошлого запуска (служба упала или перезапущена)."""
    for st in glob.glob("/sys/class/drm/card*-*/status"):
        name = st.split("/")[-2]
        try:
            if name == keep or open(st).read().strip() == "disconnected":
                continue
            if b"Rexlink" in open(st[:-6] + "edid", "rb").read():
                helper("off", name)
        except (OSError, DisplayError, subprocess.TimeoutExpired) as e:
            print("display cleanup:", e)


# ── мышь из касаний: абсолютный указатель на всю раскладку мониторов
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_RELBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045566, 0x40045567
UI_DEV_SETUP, UI_ABS_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x405C5503, 0x401C5504, 0x5501, 0x5502
EV_SYN, EV_KEY, EV_REL, EV_ABS = 0, 1, 2, 3
BTN = {"left": 0x110, "right": 0x111, "middle": 0x112}
REL_HWHEEL, REL_WHEEL, REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES = 6, 8, 11, 12


class Pointer:
    def __init__(self):
        self.fd = None
        self.box = None            # (x, y, w, h) всей раскладки
        self.rect = None           # (x, y, w, h) нашего монитора
        self.acc = [0.0, 0.0]      # остаток прокрутки (1/120 щелчка)
        self.checked = 0.0

    def update(self, connector, force=False):
        if not force and time.time() - self.checked < 2:
            return
        self.checked = time.time()
        outs = niri_outputs()
        rects = [(o["logical"]["x"], o["logical"]["y"], o["logical"]["width"], o["logical"]["height"])
                 for o in outs.values() if o.get("logical")]
        mine = outs.get(connector, {}).get("logical")
        if not rects or not mine:
            return
        self.rect = (mine["x"], mine["y"], mine["width"], mine["height"])
        x0, y0 = min(r[0] for r in rects), min(r[1] for r in rects)
        box = (x0, y0, max(r[0] + r[2] for r in rects) - x0, max(r[1] + r[3] for r in rects) - y0)
        if box != self.box:
            self.close()
            self.box = box
            self._create()

    def _create(self):
        fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
        for b in BTN.values():
            fcntl.ioctl(fd, UI_SET_KEYBIT, b)
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_REL)
        for r in (REL_WHEEL, REL_HWHEEL, REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES):
            fcntl.ioctl(fd, UI_SET_RELBIT, r)
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_ABS)
        for axis, size in ((0, self.box[2]), (1, self.box[3])):
            fcntl.ioctl(fd, UI_SET_ABSBIT, axis)
            fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack("HHiiiiii", axis, 0, 0, 0, max(1, size - 1), 0, 0, 0))
        fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack("HHHH80sI", 3, 0x1209, 0x7278, 1, b"Rexlink display touch", 0))
        fcntl.ioctl(fd, UI_DEV_CREATE)
        self.fd = fd
        time.sleep(0.15)           # композитор подхватывает устройство не мгновенно

    def _ev(self, t, c, v):
        os.write(self.fd, struct.pack("llHHi", 0, 0, t, c, v))

    def handle(self, ev):
        if self.fd is None or not self.rect:
            return
        a = ev.get("a")
        if "x" in ev:
            x = self.rect[0] + min(max(float(ev["x"]), 0.0), 0.9999) * self.rect[2] - self.box[0]
            y = self.rect[1] + min(max(float(ev["y"]), 0.0), 0.9999) * self.rect[3] - self.box[1]
            self._ev(EV_ABS, 0, int(x))
            self._ev(EV_ABS, 1, int(y))
        if a in ("down", "up") and ev.get("b") in BTN:
            self._ev(EV_KEY, BTN[ev["b"]], 1 if a == "down" else 0)
        elif a == "click" and ev.get("b") in BTN:
            self._ev(EV_SYN, 0, 0)
            self._ev(EV_KEY, BTN[ev["b"]], 1)
            self._ev(EV_SYN, 0, 0)
            self._ev(EV_KEY, BTN[ev["b"]], 0)
        elif a == "scroll":
            # dx/dy — в щелчках колеса; палец вниз — содержимое едет вниз (как на сенсорном экране)
            for i, (key, hi, lo) in enumerate((("dy", REL_WHEEL_HI_RES, REL_WHEEL), ("dx", REL_HWHEEL_HI_RES, REL_HWHEEL))):
                v = float(ev.get(key, 0)) * (1 if key == "dy" else -1) * 120
                if not v:
                    continue
                self._ev(EV_REL, hi, int(v))
                self.acc[i] += v
                notches = int(self.acc[i] / 120)
                if notches:
                    self._ev(EV_REL, lo, notches)
                    self.acc[i] -= notches * 120
        self._ev(EV_SYN, 0, 0)

    def close(self):
        if self.fd is not None:
            try:
                fcntl.ioctl(self.fd, UI_DEV_DESTROY)
                os.close(self.fd)
            except OSError:
                pass
            self.fd = None


# ── H.264 из ffmpeg: Annex-B → кадры по разделителям (AUD)
class AuSplitter:
    def __init__(self):
        self.buf = b""

    @staticmethod
    def nals(data):
        """Разбить на NAL (со стартовыми кодами)."""
        starts = []
        i = data.find(b"\x00\x00\x01")
        while i >= 0:
            starts.append(i - 1 if i > 0 and data[i - 1] == 0 else i)
            i = data.find(b"\x00\x00\x01", i + 3)
        return [data[s:e] for s, e in zip(starts, starts[1:] + [len(data)])]

    def feed(self, data, flush=False):
        """Вернуть готовые пакеты [(тип, данные)]; при flush — всё, что есть (ffmpeg закончил запись кадра)."""
        self.buf += data
        out = []
        # кадр закончен, когда начался следующий AUD; хвост держим до следующего чтения
        cut = len(self.buf) if flush else self.buf.rfind(b"\x00\x00\x01\x09")
        if cut <= 0:
            return out
        if not flush and cut > 0 and self.buf[cut - 1] == 0:
            cut -= 1
        chunk, self.buf = self.buf[:cut], self.buf[cut:]
        cfg, frame = [], []
        for nal in self.nals(chunk):
            off = 3 if nal[2] == 1 else 4
            if len(nal) <= off:
                continue
            t = nal[off] & 0x1F
            if t in (7, 8):
                cfg.append(nal)
            elif t == 9:
                if frame:
                    out.append((1, b"".join(frame)))
                    frame = []
            elif t != 6:
                frame.append(nal)
        if cfg:
            out.insert(0, (2, b"".join(cfg)))
        if frame:
            out.append((1, b"".join(frame)))
        return out


# ── сеанс
class Session:
    """Один сеанс «устройство — монитор». run(sock) идёт в потоке потока (net.Server.expect_stream)."""

    def __init__(self, config, on_state, adb_cleanup=None):
        self.cfg = config
        self.on_state = on_state            # dict → служба (в любом потоке)
        self.adb_cleanup = adb_cleanup
        self.stopped = False
        self.sock = None
        self.sysname = self.connector = ""
        self.enabled = False
        self.ffmpeg = None
        self.cap = None
        self.pointer = Pointer()
        self.lock = threading.Lock()

    def stop(self):
        self.stopped = True
        if self.sock:
            try:
                self.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

    # пакеты
    def _send(self, kind, data):
        msg = struct.pack(">IB", len(data) + 1, kind) + data
        with self.lock:
            view = memoryview(msg)
            while view:
                try:
                    n = self.sock.send(view)
                    view = view[n:]
                except (ssl.SSLWantWriteError, ssl.SSLWantReadError, BlockingIOError):
                    select.select([], [self.sock], [], 1)

    def run(self, sock):
        self.sock = sock
        try:
            sock.settimeout(60)            # пока на устройстве открывается окно
            n, = struct.unpack(">I", read_exact(sock, 4))
            kind = read_exact(sock, 1)[0]
            hello = json.loads(read_exact(sock, n - 1)) if kind == 0 else {}
            if not hello.get("w"):
                raise DisplayError("устройство не прислало размер экрана")
            self._start(hello)
            self._loop()
        except DisplayError as e:
            self.on_state({"running": False, "error": str(e)})
            try:
                self._send(4, json.dumps({"error": str(e)}, ensure_ascii=False).encode())
            except (OSError, AttributeError):
                pass
        except Exception as e:  # noqa: BLE001
            if not self.stopped:
                print("display:", repr(e))
                self.on_state({"running": False, "error": f"соединение прервано ({e.__class__.__name__})"})
        finally:
            self._cleanup()

    def _start(self, hello):
        dc = self.cfg["display"]
        real_w = max(int(hello["w"]), int(hello["h"]))
        mw, mh = fit_mode(int(hello["w"]), int(hello["h"]), int(dc.get("maxSize", 2560)))
        hz = int(dc.get("fps", 60))
        if not shutil.which("ffmpeg"):
            raise DisplayError("нужен ffmpeg")
        want = dc.get("connector", "auto")
        free = free_connectors()
        pick = next((c for c in free if want in ("auto", "", c[0], c[1])), None)
        if not pick:
            raise DisplayError("нет свободного разъёма видеокарты для виртуального монитора")
        self.sysname, self.connector = pick
        dpi = float(hello.get("density", 2.0)) * 160
        mm = (round(real_w / dpi * 25.4), round(min(int(hello["w"]), int(hello["h"])) / dpi * 25.4))
        self.on_state({"running": True, "starting": True, "output": self.connector, "w": mw, "h": mh})
        helper("on", self.sysname, make_edid(mw, mh, hz, mm))
        self.enabled = True
        # ждём, пока монитор появится у композитора
        for _ in range(40):
            if self.connector in niri_outputs():
                break
            time.sleep(0.25)
        else:
            raise DisplayError(f"композитор не увидел монитор {self.connector} — видеокарта не дала включить разъём")
        # масштаб под плотность планшета — если пользователь не задал свой (Настройки → Дисплей).
        # Шелл может переписать конфиг niri, увидев новый монитор, — ставим, когда всё уляжется
        scale = str(niri_scale(float(hello.get("density", 2.0)), mw, real_w))

        def keep_scale():
            # перезагрузка конфига niri сбрасывает масштаб на свой — возвращаем, пока нет своих настроек
            while not self.stopped:
                time.sleep(3)
                o = niri_outputs().get(self.connector, {}).get("logical") or {}
                if o and abs(o.get("scale", 0) - float(scale)) > 0.01 and not has_output_config(self.connector):
                    niri("output", self.connector, "transform", "normal")
                    niri("output", self.connector, "scale", scale)
                    self.pointer.update(self.connector, force=True)
        threading.Thread(target=keep_scale, daemon=True).start()
        self.cap = Capture(self.connector)
        mv, pix, w, h, stride = self.cap.grab(first=True)
        self.size = (w, h, stride, pix)
        self._send(0, json.dumps({"w": w, "h": h}).encode())
        self._ffmpeg(w, h, pix, int(dc.get("bitrate", 12000000)), hz)
        self.ffmpeg.stdin.write(mv[:stride * h])
        self.pointer.update(self.connector, force=True)
        self.on_state({"running": True, "starting": False, "output": self.connector, "w": w, "h": h, "error": ""})

    def _ffmpeg(self, w, h, pix, bitrate, fps):
        out = getattr(self, "out", None)          # (ш, в) — уменьшить при кодировании
        va_size = f"w={out[0]}:h={out[1]}:" if out else ""
        sw_scale = f"scale={out[0]}:{out[1]}," if out else ""
        enc_va = ["-vaapi_device", "/dev/dri/renderD128", "-vf", f"hwupload,scale_vaapi={va_size}format=nv12",
                  "-c:v", "h264_vaapi", "-profile:v", "high", "-bf", "0", "-async_depth", "1"]
        enc_sw = ["-vf", f"{sw_scale}format=yuv420p", "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency",
                  "-profile:v", "high"]
        enc = enc_va if os.path.exists("/dev/dri/renderD128") and self.cfg["display"].get("encoder", "auto") != "x264" else enc_sw
        cmd = (["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-f", "rawvideo", "-pix_fmt", pix,
                "-s", f"{w}x{h}", "-framerate", str(fps), "-i", "pipe:0"] + enc +
               ["-g", str(fps * 2), "-b:v", str(bitrate), "-maxrate", str(bitrate), "-bufsize", str(bitrate // 4),
                "-aud", "1", "-flush_packets", "1", "-fps_mode", "passthrough", "-f", "h264", "pipe:1"])
        self.ffmpeg = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       bufsize=0)
        threading.Thread(target=self._ff_err, daemon=True).start()
        threading.Thread(target=self._capture_loop, daemon=True, name="display-capture").start()

    def _ff_err(self):
        for line in self.ffmpeg.stderr:
            print("ffmpeg[display]:", line.decode(errors="replace").strip())

    def _capture_loop(self):
        w, h, stride, _ = self.size
        try:
            while not self.stopped:
                mv, pix, nw, nh, nstride = self.cap.grab()
                if (nw, nh, nstride) != (w, h, stride):
                    raise DisplayError("размер монитора изменился")
                self.ffmpeg.stdin.write(mv[:stride * h])
        except (OSError, ValueError, WaylandError, DisplayError) as e:
            if not self.stopped:
                print("display capture:", e)
                self.stop()

    def _loop(self):
        """Кадры от ffmpeg → устройству; касания от устройства → мышь. Один поток на TLS-сокет."""
        sock = self.sock
        sock.setblocking(False)
        ff = self.ffmpeg.stdout.fileno()
        split = AuSplitter()
        inbuf = b""
        while not self.stopped:
            ready = sock.pending() > 0
            r, _, _ = select.select([sock, ff], [], [], 0 if ready else 1.0)
            if ff in r:
                data = os.read(ff, 1 << 20)
                if not data:
                    raise DisplayError("кодировщик остановился")
                # ffmpeg пишет кадр целиком; ждём 2 мс, не идёт ли продолжение
                more, _, _ = select.select([ff], [], [], 0.002)
                for kind, pkt in split.feed(data, flush=not more):
                    self._send(kind, pkt)
            if sock in r or ready:
                try:
                    chunk = sock.recv(1 << 16)
                except (ssl.SSLWantReadError, ssl.SSLWantWriteError, BlockingIOError):
                    continue
                if not chunk:
                    return
                inbuf += chunk
                while len(inbuf) >= 5:
                    n, kind = struct.unpack_from(">IB", inbuf)
                    if len(inbuf) < 4 + n:
                        break
                    body, inbuf = inbuf[5:4 + n], inbuf[4 + n:]
                    if kind == 3:
                        try:
                            ev = json.loads(body)
                        except ValueError:
                            continue
                        self._input(ev)

    def _input(self, ev):
        if ev.get("a") in ("down", "click"):
            self.pointer.update(self.connector)
        self.pointer.handle(ev)

    def _cleanup(self):
        self.stopped = True
        if self.ffmpeg:
            try:
                self.ffmpeg.stdin.close()
            except OSError:
                pass
            try:
                self.ffmpeg.kill()
                self.ffmpeg.wait(2)
            except Exception:  # noqa: BLE001
                pass
        if self.cap:
            # поток захвата мог ещё держать последний кадр — память освободится вместе с ним
            try:
                self.cap.close()
            except (BufferError, OSError) as e:
                print("capture close:", e)
        self.pointer.close()
        if self.enabled:
            try:
                helper("off", self.sysname)
            except (DisplayError, OSError, subprocess.TimeoutExpired) as e:
                print("display off:", e)
        if self.adb_cleanup:
            self.adb_cleanup()
        try:
            self.sock.close()
        except OSError:
            pass
        self.on_state({"running": False, "starting": False, "output": ""})


# ── управление компьютером с устройства (как AnyDesk/RustDesk, но по своей связи Rexlink)
def focused_output():
    """Монитор, на котором сейчас работают (в фокусе), иначе первый."""
    try:
        r = subprocess.run(["niri", "msg", "-j", "focused-output"], capture_output=True, text=True, timeout=3)
        name = (json.loads(r.stdout or "null") or {}).get("name", "")
        if name:
            return name
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return next(iter(niri_outputs()), "")


# клавиши с устройства → имена для wtype
KEYS = {"enter": "Return", "backspace": "BackSpace", "tab": "Tab", "esc": "Escape", "delete": "Delete",
        "left": "Left", "right": "Right", "up": "Up", "down": "Down", "home": "Home", "end": "End",
        "pageup": "Prior", "pagedown": "Next", "space": "space", "super": "Super_L",
        **{f"f{i}": f"F{i}" for i in range(1, 13)}}
MODS = {"ctrl": "ctrl", "alt": "alt", "shift": "shift", "super": "logo"}


class RemoteSession(Session):
    """Экран ПК на устройстве как есть, без виртуального монитора: касания — мышь (uinput), текст и клавиши —
    клавиатура (wtype). Кадров не больше remote.fps, длинная сторона — до remote.maxSize."""

    def _start(self, hello):
        rc = self.cfg.get("remote", {})
        if not shutil.which("ffmpeg"):
            raise DisplayError("нужен ffmpeg")
        self.connector = str(hello.get("output") or "") or focused_output()
        if not self.connector:
            raise DisplayError("не найден монитор")
        self.on_state({"running": True, "starting": True, "output": self.connector, "remote": True})
        self.cap = Capture(self.connector)
        mv, pix, w, h, stride = self.cap.grab(first=True)
        self.size = (w, h, stride, pix)
        k = min(1.0, int(rc.get("maxSize", 1920)) / max(w, h))
        self.out = (int(w * k) // 2 * 2, int(h * k) // 2 * 2)
        self.fps = max(5, min(60, int(rc.get("fps", 30))))
        self._send(0, json.dumps({"w": self.out[0], "h": self.out[1], "remote": True, "output": self.connector,
                                  "outputs": list(niri_outputs())}).encode())
        self._ffmpeg(w, h, pix, int(rc.get("bitrate", 8000000)), self.fps)
        self.ffmpeg.stdin.write(mv[:stride * h])
        self.pointer.update(self.connector, force=True)
        self.on_state({"running": True, "starting": False, "output": self.connector, "remote": True, "error": ""})

    def _capture_loop(self):
        # экран ПК может обновляться 180 раз в секунду — устройству хватит remote.fps
        w, h, stride, _ = self.size
        step = 1.0 / self.fps
        nxt = time.time()
        try:
            while not self.stopped:
                nxt += step
                time.sleep(max(0.0, nxt - time.time()))
                nxt = max(nxt, time.time())
                mv, pix, nw, nh, nstride = self.cap.grab()
                if (nw, nh, nstride) != (w, h, stride):
                    raise DisplayError("размер монитора изменился")
                self.ffmpeg.stdin.write(mv[:stride * h])
        except (OSError, ValueError, WaylandError, DisplayError) as e:
            if not self.stopped:
                print("remote capture:", e)
                self.stop()

    def _input(self, ev):
        a = ev.get("a")
        if a == "text":
            text = str(ev.get("s", ""))[:500]
            if text:
                subprocess.run(["wtype", "--", text], capture_output=True, timeout=5)
            return
        if a == "key":
            key = KEYS.get(str(ev.get("k", "")).lower(), str(ev.get("k", "")))
            if not re.fullmatch(r"[A-Za-z0-9_]{1,20}", key or ""):
                return
            mods = [MODS[m] for m in ev.get("mods", []) if m in MODS]
            cmd = ["wtype"]
            for m in mods:
                cmd += ["-M", m]
            cmd += ["-k", key]
            for m in reversed(mods):
                cmd += ["-m", m]
            subprocess.run(cmd, capture_output=True, timeout=5)
            return
        super()._input(ev)

