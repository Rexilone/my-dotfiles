"""Передача файлов в обе стороны по отдельным TLS-потокам, с прогрессом."""
import os
import secrets
import threading
import time
from pathlib import Path

from PySide6.QtCore import QObject, Signal

CHUNK = 256 * 1024


def unique_path(folder: Path, name: str) -> Path:
    name = os.path.basename(name).replace("\0", "") or "file"
    p = folder / name
    stem, suf = p.stem, p.suffix
    i = 1
    while p.exists():
        p = folder / f"{stem} ({i}){suf}"
        i += 1
    return p


class Transfers(QObject):
    changed = Signal()
    finished = Signal(object)   # запись о завершённой передаче

    def __init__(self, server, config):
        super().__init__()
        self.server = server
        self.config = config
        self.items = []          # [{ fid, name, size, done, dir, state, path, speed }]
        self._socks = {}
        self._lock = threading.Lock()
        self._last_emit = 0.0

    def _emit(self, force=False):
        now = time.monotonic()
        if force or now - self._last_emit > 0.1:
            self._last_emit = now
            self.changed.emit()

    def _add(self, **kw):
        item = dict(kw, done=0, state="active", speed=0, started=time.time())
        with self._lock:
            self.items.insert(0, item)
            del self.items[50:]
        self._emit(True)
        return item

    def snapshot(self):
        with self._lock:
            return [dict(i) for i in self.items]

    # ── ПК → телефон
    def send_files(self, device, paths):
        for p in paths:
            p = Path(p)
            if p.is_file():
                self._send_one(device, p)

    def _send_one(self, device, path: Path):
        fid = secrets.token_hex(6)
        size = path.stat().st_size
        item = self._add(fid=fid, name=path.name, size=size, dir="out", path=str(path), device=device)

        def stream(sock):
            self._socks[fid] = sock
            item["started"] = time.time()
            try:
                self._pump(item, open(path, "rb"), sock.sendall)
                # ждём подтверждения, что телефон всё сохранил
                sock.settimeout(60)
                sock.recv(1)
                item["state"] = "done"
            except Exception:
                if item["state"] == "active":
                    item["state"] = "error"
            finally:
                self._socks.pop(fid, None)
                self._emit(True)
                self.finished.emit(dict(item))

        sid = self.server.expect_stream(device, stream)
        if not self.server.send(device, {"t": "file_offer", "fid": fid, "sid": sid, "name": path.name, "size": size}):
            item["state"] = "error"
            self.server.cancel_stream(sid)
            self._emit(True)

    # ── телефон → ПК
    def incoming(self, device, header):
        fid = str(header.get("fid") or secrets.token_hex(6))
        size = int(header.get("size", 0))
        dest = unique_path(self.config.downloads(), str(header.get("name", "file")))
        item = self._add(fid=fid, name=dest.name, size=size, dir="in", path=str(dest), device=device)

        def stream(sock):
            self._socks[fid] = sock
            item["started"] = time.time()
            part = dest.with_name(dest.name + ".part")
            try:
                with open(part, "wb") as f:
                    left = size
                    while left > 0:
                        chunk = sock.recv(min(CHUNK, left))
                        if not chunk:
                            raise ConnectionError("closed")
                        f.write(chunk)
                        left -= len(chunk)
                        self._progress(item, len(chunk))
                part.rename(dest)
                sock.sendall(b"\x01")
                item["state"] = "done"
            except Exception:
                if item["state"] == "active":
                    item["state"] = "error"
                part.unlink(missing_ok=True)
            finally:
                self._socks.pop(fid, None)
                self._emit(True)
                self.finished.emit(dict(item))

        sid = self.server.expect_stream(device, stream)
        self.server.send(device, {"t": "file_accept", "fid": fid, "sid": sid})

    def _pump(self, item, f, write):
        with f:
            while True:
                chunk = f.read(CHUNK)
                if not chunk:
                    break
                write(chunk)
                self._progress(item, len(chunk))

    def _progress(self, item, n):
        item["done"] += n
        el = max(0.001, time.time() - item["started"])
        item["speed"] = item["done"] / el
        self._emit()

    def cancel(self, fid):
        for i in self.items:
            if i["fid"] == fid and i["state"] == "active":
                i["state"] = "cancelled"
        s = self._socks.pop(fid, None)
        if s:
            try:
                s.close()
            except OSError:
                pass
        dev = next((i.get("device") for i in self.items if i["fid"] == fid), None)
        if dev:
            self.server.send(dev, {"t": "file_cancel", "fid": fid})
        self._emit(True)

    def clear(self):
        with self._lock:
            self.items = [i for i in self.items if i["state"] == "active"]
        self._emit(True)
