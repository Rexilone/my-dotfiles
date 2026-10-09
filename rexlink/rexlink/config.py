"""Пути, настройки и доверенные устройства (~/.config/rexlink/config.json)."""
import json
import os
import socket
import subprocess
import threading
from pathlib import Path


def _xdg(var, default):
    return Path(os.environ.get(var) or Path.home() / default)


CONFIG_DIR = _xdg("XDG_CONFIG_HOME", ".config") / "rexlink"
CACHE_DIR = _xdg("XDG_CACHE_HOME", ".cache") / "rexlink"
STATE_DIR = _xdg("XDG_STATE_HOME", ".local/state") / "rexlink"
RUNTIME_DIR = Path(os.environ.get("REXLINK_RUNTIME_DIR") or
                   Path(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/rexlink-{os.getuid()}") / "rexlink")


def download_dir() -> Path:
    try:
        out = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True, timeout=2).stdout.strip()
        if out and out != str(Path.home()):
            return Path(out) / "Rexlink"
    except Exception:
        pass
    return Path.home() / "Downloads" / "Rexlink"


DEFAULTS = {
    "name": socket.gethostname(),
    "devices": {},          # id -> { name, token }
    "clipboard": True,
    "clipboardImages": True,
    "notifications": True,
    "mirrorToDesktop": True,  # показывать уведомления телефона в шелле
    "calls": True,
    "sms": True,
    "media": True,
    "pcMedia": True,          # отдавать плеер ПК телефону
    "autoUpdateDevices": True,  # обновлять приложение на устройствах из пакета Rexlink
    "downloadDir": "",
    "lang": "ru",             # язык уведомлений службы — его задаёт шелл
    "webcamDevice": "auto",
    "camera": {"facing": "back", "width": 1280, "height": 720, "fps": 30, "bitrate": 6000000},
    "screen": {"maxSize": 1280, "bitrate": 8000000, "fps": 60},
}


class Config:
    def __init__(self):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
        self.path = CONFIG_DIR / "config.json"
        self._lock = threading.Lock()
        self.data = json.loads(json.dumps(DEFAULTS))
        try:
            saved = json.loads(self.path.read_text())
            for k, v in saved.items():
                if isinstance(v, dict) and isinstance(self.data.get(k), dict) and k != "devices":
                    self.data[k].update(v)
                else:
                    self.data[k] = v
        except (OSError, ValueError):
            pass
        self.save()

    def __getitem__(self, key):
        return self.data[key]

    def get(self, key, default=None):
        return self.data.get(key, default)

    def set(self, key, value):
        self.data[key] = value
        self.save()

    def save(self):
        with self._lock:
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self.data, indent=2, ensure_ascii=False))
            os.chmod(tmp, 0o600)
            tmp.replace(self.path)

    def downloads(self) -> Path:
        d = Path(self.data["downloadDir"]) if self.data.get("downloadDir") else download_dir()
        d.mkdir(parents=True, exist_ok=True)
        return d

    # сертификат ПК: самоподписанный, создаётся один раз
    def ensure_cert(self):
        cert, key = CONFIG_DIR / "cert.pem", CONFIG_DIR / "key.pem"
        if not (cert.exists() and key.exists()):
            subprocess.run(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
                            "-nodes", "-keyout", str(key), "-out", str(cert), "-days", "7300",
                            "-subj", "/CN=rexlink"], check=True, capture_output=True)
            os.chmod(key, 0o600)
        return cert, key
