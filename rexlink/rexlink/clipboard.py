"""Буфер обмена Wayland через wl-clipboard.

Защита от цикла: храним хеш последнего содержимого, которое мы отправили или получили.
Изменение буфера с тем же хешем (эхо нашего же wl-copy) не отправляется,
а входящее содержимое с тем же хешем не записывается повторно.
"""
import hashlib
import shutil
import subprocess
import threading
import time

from PySide6.QtCore import QObject, Signal
from .proc import popen

TEXT_TYPES = ("text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "TEXT", "STRING")
IMAGE_TYPES = ("image/png", "image/jpeg", "image/webp", "image/bmp")
# менеджеры паролей помечают секреты — такое не синхронизируем
SECRET_HINTS = ("x-kde-passwordManagerHint",)
MAX_IMAGE = 25 << 20


def digest(kind, data: bytes):
    return hashlib.sha256(kind.encode() + b"\0" + data).hexdigest()


class Clipboard(QObject):
    localChanged = Signal(str, str, object)   # kind ("text"|"image"), mime, данные (str|bytes)

    def __init__(self):
        super().__init__()
        self.available = bool(shutil.which("wl-paste") and shutil.which("wl-copy"))
        self.last_hash = None
        self._set_at = 0.0
        self._lock = threading.Lock()
        self._proc = None
        self.images = True

    def start(self):
        if not self.available:
            return
        threading.Thread(target=self._watch, daemon=True, name="clipboard").start()

    def _watch(self):
        while True:
            try:
                # каждая смена буфера печатает строку; содержимое читаем сами
                self._proc = popen(["wl-paste", "--watch", "sh", "-c", "cat >/dev/null; echo"],
                                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                first = True
                for _ in self._proc.stdout:
                    if first:  # первое событие — текущее содержимое при запуске, не отправляем
                        first = False
                        self._remember_current()
                        continue
                    self._on_change()
            except Exception as e:  # noqa: BLE001
                print("clipboard watch:", e)
            time.sleep(2)

    def _types(self):
        try:
            out = subprocess.run(["wl-paste", "--list-types"], capture_output=True, text=True, timeout=3).stdout
            return [t.strip() for t in out.splitlines() if t.strip()]
        except Exception:
            return []

    def _read(self, mime):
        try:
            return subprocess.run(["wl-paste", "--no-newline", "--type", mime], capture_output=True, timeout=5).stdout
        except Exception:
            return None

    def _current(self):
        types = self._types()
        if any(h in types for h in SECRET_HINTS):
            return None
        img = next((t for t in IMAGE_TYPES if t in types), None)
        txt = next((t for t in TEXT_TYPES if t in types), None)
        if img and self.images:
            data = self._read(img)
            if data and len(data) <= MAX_IMAGE:
                return "image", img, data
        if txt:
            data = self._read(txt)
            if data is not None:
                return "text", "text/plain", data
        return None

    def _remember_current(self):
        cur = self._current()
        if cur:
            with self._lock:
                self.last_hash = digest(cur[0], cur[2])

    def _on_change(self):
        cur = self._current()
        if not cur:
            return
        kind, mime, data = cur
        h = digest(kind, data)
        with self._lock:
            if h == self.last_hash:
                return
            self.last_hash = h
        if kind == "text":
            text = data.decode("utf-8", "replace")
            if not text.strip():
                return
            self.localChanged.emit(kind, mime, text)
        else:
            self.localChanged.emit(kind, mime, data)

    def set_remote(self, kind, mime, data):
        """Содержимое пришло с телефона: записываем, если оно отличается от последнего."""
        if not self.available:
            return False
        raw = data.encode() if isinstance(data, str) else data
        h = digest(kind, raw)
        with self._lock:
            if h == self.last_hash:
                return False
            self.last_hash = h
        mime = mime if kind == "image" else "text/plain;charset=utf-8"
        try:
            # wl-copy остаётся в фоне и отдаёт содержимое, пока буфер не сменится
            p = subprocess.Popen(["wl-copy", "--type", mime], stdin=subprocess.PIPE,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            p.stdin.write(raw)
            p.stdin.close()
            return True
        except Exception as e:  # noqa: BLE001
            print("wl-copy:", e)
            return False
