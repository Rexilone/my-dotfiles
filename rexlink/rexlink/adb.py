"""ADB (беспроводная отладка) и режим «экран выключен».

Обычное приложение Android не может погасить панель, продолжая рисовать картинку.
Это умеет scrcpy через ADB: панель выключается, а система остаётся в состоянии «экран включён»,
поэтому трансляция Rexlink и управление через спецвозможность продолжают работать.
Порты беспроводной отладки сообщает сам телефон (NsdManager); запасной путь — avahi или ввод вручную.
"""
import os
import re
import secrets
import shutil
import socket
import subprocess
import threading
import time

from PySide6.QtCore import QObject, Signal

from .proc import popen


def _run(args, timeout=10):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except Exception as e:  # noqa: BLE001
        return 1, str(e)


class Adb(QObject):
    changed = Signal()              # состояние режима «экран выключен»
    result = Signal(str, bool, str)  # действие, успех, текст

    def __init__(self):
        super().__init__()
        self.adb = bool(shutil.which("adb")) and not os.environ.get("REXLINK_NO_ADB")
        self.scrcpy = bool(shutil.which("scrcpy"))
        self._procs = {}            # id устройства -> scrcpy

    @property
    def available(self):
        return self.adb and self.scrcpy

    # ── устройства adb
    def devices(self):
        code, out = _run(["adb", "devices", "-l"])
        res = []
        for line in out.splitlines()[1:]:
            parts = line.split()
            if len(parts) < 2:
                continue
            d = {"serial": parts[0], "state": parts[1]}
            for p in parts[2:]:
                if ":" in p:
                    k, v = p.split(":", 1)
                    d[k] = v
            res.append(d)
        return res

    def find(self, ip, model=""):
        """Серийный номер именно этого устройства в adb: по IP (Wi-Fi) или по модели (USB, mDNS)."""
        devs = [d for d in self.devices() if d["state"] == "device"]
        for d in devs:
            if ip and d["serial"].rsplit(":", 1)[0] == ip:
                return d["serial"]
        key = model.replace(" ", "_").lower()
        if not key:
            return devs[0]["serial"] if len(devs) == 1 else None
        for d in devs:
            m = d.get("model", "").lower()
            if m and (key == m or key.endswith("_" + m)):
                return d["serial"]
        return None   # чужое устройство не берём, даже если оно единственное

    def avahi_ports(self, ip):
        """Порты беспроводной отладки через avahi (если запущен avahi-daemon)."""
        ports = {}
        if not shutil.which("avahi-browse"):
            return ports
        for kind, svc in (("connect", "_adb-tls-connect._tcp"), ("pairing", "_adb-tls-pairing._tcp")):
            _, out = _run(["avahi-browse", "-rpt", svc], timeout=4)
            for line in out.splitlines():
                f = line.split(";")
                if len(f) > 8 and f[0] == "=" and f[7] == ip:
                    ports[kind] = int(f[8])
        return ports

    def connect(self, ip, port):
        code, out = _run(["adb", "connect", f"{ip}:{port}"], timeout=15)
        ok = "connected to" in out and "failed" not in out.lower()
        return ok, out

    def pair(self, ip, port, code):
        rc, out = _run(["adb", "pair", f"{ip}:{port}", str(code)], timeout=20)
        return "Successfully paired" in out, out

    def async_call(self, action, fn, *args):
        def run():
            ok, text = fn(*args)
            self.result.emit(action, ok, text)
        threading.Thread(target=run, daemon=True).start()

    # ── экран выключен
    def screen_off(self, device_id, serial):
        self.screen_on(device_id)
        p = popen(["scrcpy", "-s", serial, "--no-window", "--no-video", "--no-audio", "--turn-screen-off",
                   "--no-clipboard-autosync", "--stay-awake"],
                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self._procs[device_id] = p

        def watch():
            log = []
            for line in p.stdout:
                log.append(line.strip())
            p.wait()
            if self._procs.get(device_id) is p:
                del self._procs[device_id]
                tail = next((x for x in reversed(log) if "ERROR" in x), log[-1] if log else "")
                self.result.emit("screen_off", False, re.sub(r"^\S+:\s*", "", tail) or "scrcpy завершился")
            self.changed.emit()
        threading.Thread(target=watch, daemon=True).start()
        self.changed.emit()

    def screen_on(self, device_id):
        p = self._procs.pop(device_id, None)
        if p:
            p.terminate()   # scrcpy при выходе включает экран обратно
            self.changed.emit()

    def is_off(self, device_id):
        p = self._procs.get(device_id)
        return bool(p and p.poll() is None)

    def stop_all(self):
        for did in list(self._procs):
            self.screen_on(did)


# ── видео через scrcpy-server: без запроса на телефоне (права adb shell, как у scrcpy)
SERVER_PATHS = ("/usr/share/scrcpy/scrcpy-server", "/usr/local/share/scrcpy/scrcpy-server",
                os.path.expanduser("~/.nix-profile/share/scrcpy/scrcpy-server"), "/run/current-system/sw/share/scrcpy/scrcpy-server")


def scrcpy_server():
    env = os.environ.get("SCRCPY_SERVER_PATH")
    for p in ([env] if env else []) + list(SERVER_PATHS):
        if p and os.path.isfile(p):
            return p
    exe = shutil.which("scrcpy")
    if exe:   # рядом с бинарником (nix и ручные сборки)
        cand = os.path.join(os.path.dirname(os.path.realpath(exe)), "..", "share", "scrcpy", "scrcpy-server")
        if os.path.isfile(cand):
            return os.path.normpath(cand)
    return None


def scrcpy_version():
    code, out = _run(["scrcpy", "--version"], timeout=5)
    m = re.search(r"scrcpy (\S+)", out)
    return m.group(1) if m else None


class ScrcpyVideo:
    """Поток экрана с устройства по adb: scrcpy-server в режиме raw_stream → сырой H.264."""

    REMOTE = "/data/local/tmp/rexlink-scrcpy-server.jar"

    def __init__(self, serial, max_size=1280, bitrate=8000000, fps=60):
        self.serial = serial
        self.opts = dict(max_size=max_size, video_bit_rate=bitrate, max_fps=fps)
        self.scid = "%08x" % (secrets.randbits(31))
        self.port = None
        self.proc = None

    def _adb(self, *args, timeout=15):
        return _run(["adb", "-s", self.serial, *args], timeout=timeout)

    def start(self):
        """Запускает сервер и возвращает подключённый сокет (блокирует до ~10 с)."""
        server = scrcpy_server()
        version = scrcpy_version()
        if not server or not version:
            raise RuntimeError("не найден scrcpy-server (пакет scrcpy)")
        code, out = self._adb("push", server, self.REMOTE, timeout=30)
        if code:
            raise RuntimeError(f"adb push: {out[-200:]}")
        with socket.socket() as s:   # свободный локальный порт
            s.bind(("127.0.0.1", 0))
            self.port = s.getsockname()[1]
        code, out = self._adb("forward", f"tcp:{self.port}", f"localabstract:scrcpy_{self.scid}")
        if code:
            raise RuntimeError(f"adb forward: {out[-200:]}")
        args = [f"scid={self.scid}", "tunnel_forward=true", "audio=false", "control=false", "raw_stream=true",
                "cleanup=true", "power_on=true", "video_codec=h264"] + [f"{k}={v}" for k, v in self.opts.items()]
        self.proc = popen(["adb", "-s", self.serial, "shell", f"CLASSPATH={self.REMOTE}", "app_process", "/",
                           "com.genymobile.scrcpy.Server", version, *args],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        threading.Thread(target=self._log, daemon=True).start()
        deadline = time.time() + 10
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError("scrcpy-server завершился: " + " ".join(self._last[-3:]))
            try:
                sock = socket.create_connection(("127.0.0.1", self.port), timeout=2)
                # adb принимает соединение сразу, даже если сервер ещё не слушает: ждём первые байты
                sock.settimeout(3)
                first = sock.recv(1 << 16)
                if first:
                    return sock, first
                sock.close()
            except OSError:
                pass
            time.sleep(0.25)
        raise RuntimeError("scrcpy-server не ответил")

    _last = []

    def _log(self):
        self._last = []
        for line in self.proc.stdout:
            line = line.strip()
            if line:
                self._last = (self._last + [line])[-10:]
                if "ERROR" in line or "Exception" in line:
                    print("scrcpy-server:", line)

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
        if self.port:
            _run(["adb", "-s", self.serial, "forward", "--remove", f"tcp:{self.port}"], timeout=5)
            self.port = None
