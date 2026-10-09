"""Плеер ПК (MPRIS) через playerctl: состояние отдаём телефону, команды выполняем."""
import json
import shutil
import subprocess
import threading
import time
import urllib.parse
import urllib.request

from PySide6.QtCore import QObject, Signal
from .proc import popen

FMT = ('{"player":"{{markup_escape(playerName)}}","status":"{{status}}","title":"{{markup_escape(title)}}",'
       '"artist":"{{markup_escape(artist)}}","album":"{{markup_escape(album)}}","len":"{{mpris:length}}",'
       '"pos":"{{position}}","art":"{{mpris:artUrl}}"}')


def _unescape(s):
    return s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&apos;", "'").replace("&amp;", "&")


class Mpris(QObject):
    changed = Signal(object, object)   # dict состояния, обложка (bytes|None)

    def __init__(self):
        super().__init__()
        self.available = bool(shutil.which("playerctl"))
        self.state = {}
        self._art_url = None
        self._art = None

    def start(self):
        if self.available:
            threading.Thread(target=self._follow, daemon=True, name="mpris").start()

    def _follow(self):
        while True:
            try:
                p = popen(["playerctl", "--follow", "metadata", "--format", FMT],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                for line in p.stdout:
                    self._parse(line)
            except Exception as e:  # noqa: BLE001
                print("playerctl:", e)
            time.sleep(3)

    def _parse(self, line):
        line = line.strip()
        if not line:
            self.state = {}
            self.changed.emit({}, None)
            return
        try:
            # markup_escape не экранирует обратную косую черту — JSON может сломаться
            raw = json.loads(line.replace("\\", "\\\\"))
        except ValueError:
            return
        st = {k: _unescape(v) for k, v in raw.items()}
        state = {
            "player": st["player"], "title": st["title"], "artist": st["artist"], "album": st["album"],
            "playing": st["status"] == "Playing", "active": bool(st["title"] or st["status"] in ("Playing", "Paused")),
            "len": int(st["len"]) // 1000 if st["len"].isdigit() else 0,
            "pos": int(st["pos"]) // 1000 if st["pos"].isdigit() else 0,
        }
        art = self._load_art(st["art"])
        self.state = state
        self.changed.emit(state, art)

    def _load_art(self, url):
        if url == self._art_url:
            return self._art
        self._art_url, self._art = url, None
        if not url:
            return None
        try:
            if url.startswith("file://"):
                with open(urllib.parse.unquote(url[7:]), "rb") as f:
                    self._art = f.read(4 << 20)
            elif url.startswith(("http://", "https://")):
                with urllib.request.urlopen(url, timeout=5) as r:
                    self._art = r.read(4 << 20)
        except Exception:
            self._art = None
        return self._art

    def command(self, cmd, value=None):
        if not self.available:
            return
        args = {"play": ["play"], "pause": ["pause"], "toggle": ["play-pause"], "next": ["next"],
                "prev": ["previous"], "stop": ["stop"]}.get(cmd)
        if cmd == "seek" and value is not None:
            args = ["position", str(max(0, float(value)) / 1000)]
        if cmd == "volume" and value is not None:
            args = ["volume", str(max(0.0, min(1.0, float(value))))]
        if args:
            subprocess.Popen(["playerctl", *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def position(self):
        try:
            out = subprocess.run(["playerctl", "position"], capture_output=True, text=True, timeout=2).stdout
            return int(float(out.strip()) * 1000)
        except Exception:
            return None
