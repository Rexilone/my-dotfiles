"""Цветовая схема из Quickshell (Rexilone Shell).

Итоговая палитра (в том числе «под обои») лежит в themesync.json, имя схемы, шрифт
и масштаб — в settings.json. Файлы проверяются раз в секунду, смена схемы подхватывается сразу.
"""
import json
import os
from pathlib import Path

from PySide6.QtCore import QObject, Property, QTimer, Signal

SCHEMES = {
    "dark": dict(name="Dark", bg="#151515", surface="#1b1b1b", surfaceHi="#222222", surfaceHi2="#2a2a2a", line="#3a3a3a",
                 fg="#d4d4d4", fgHover="#e6e6e6", fgPressed="#bdbdbd", muted="#a0a0a0", dim="#6b6b6b", faint="#333333",
                 urgent="#c96a6a", warn="#d7a65f", accent="#d4d4d4", rec="#e05d5d"),
    "light": dict(name="Light", bg="#f3f3f3", surface="#e8e8e8", surfaceHi="#dfdfdf", surfaceHi2="#d4d4d4", line="#c2c2c2",
                  fg="#1f1f1f", fgHover="#3a3a3a", fgPressed="#555555", muted="#474747", dim="#858585", faint="#c6c6c6",
                  urgent="#c0463f", warn="#b7791f", accent="#1f1f1f", rec="#d64545"),
    "nord": dict(name="Nord", bg="#1e222a", surface="#252a33", surfaceHi="#2e3440", surfaceHi2="#3b4252", line="#4c566a",
                 fg="#d8dee9", fgHover="#e5e9f0", fgPressed="#b8c0cc", muted="#a3adbd", dim="#6c7689", faint="#3b4252",
                 urgent="#bf616a", warn="#ebcb8b", accent="#88c0d0", rec="#bf616a"),
    "gruvbox": dict(name="Gruvbox", bg="#1d2021", surface="#242627", surfaceHi="#2c2e2f", surfaceHi2="#353230", line="#504945",
                    fg="#ebdbb2", fgHover="#fbf1c7", fgPressed="#d5c4a1", muted="#bdae93", dim="#7c6f64", faint="#3c3836",
                    urgent="#fb4934", warn="#fabd2f", accent="#fe8019", rec="#fb4934"),
    "rose": dict(name="Rosé", bg="#191724", surface="#1f1d2e", surfaceHi="#26233a", surfaceHi2="#2d2a44", line="#403d52",
                 fg="#e0def4", fgHover="#eeecfb", fgPressed="#c4c1da", muted="#908caa", dim="#6e6a86", faint="#312e47",
                 urgent="#eb6f92", warn="#f6c177", accent="#c4a7e7", rec="#eb6f92"),
}


def _state_root():
    base = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    return base / "quickshell" / "by-shell"


def _shell_dir():
    # по одной папке на каждый конфиг Quickshell; берём ту, где настройки менялись последними
    root = _state_root()
    best, best_t = None, -1
    try:
        for d in root.iterdir():
            f = d / "settings.json"
            if f.exists() and f.stat().st_mtime > best_t:
                best, best_t = d, f.stat().st_mtime
    except OSError:
        pass
    return best


class Theme(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self._palette = dict(SCHEMES["dark"])
        self._scheme = "dark"
        self._font = "JetBrainsMono Nerd Font"
        self._scale = 1.0
        self._transparency = False
        self._opacity = 1.0
        self._stamp = None
        self.reload()
        self._timer = QTimer(self)
        self._timer.setInterval(1000)
        self._timer.timeout.connect(self.reload)
        self._timer.start()

    def _files(self):
        d = _shell_dir()
        return (d / "settings.json", d / "themesync.json") if d else (None, None)

    def reload(self):
        settings_f, sync_f = self._files()
        stamp = tuple((f.stat().st_mtime_ns if f and f.exists() else 0) for f in (settings_f, sync_f))
        if stamp == self._stamp:
            return
        self._stamp = stamp
        settings, synced = {}, None
        try:
            settings = json.loads(settings_f.read_text())
        except (OSError, ValueError, AttributeError):
            pass
        try:
            synced = json.loads(json.loads(sync_f.read_text())["last"])
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            pass

        scheme = settings.get("scheme", "dark")
        palette = None
        # палитра, которую шелл применил последней (для «под обои» другого источника нет)
        if synced and isinstance(synced.get("p"), dict) and synced.get("s") == scheme:
            palette = synced["p"]
        elif scheme in SCHEMES:
            palette = SCHEMES[scheme]
        elif synced and isinstance(synced.get("p"), dict):
            palette = synced["p"]
        merged = dict(SCHEMES["dark"])
        merged.update({k: v for k, v in (palette or {}).items() if isinstance(v, str)})

        self._palette = merged
        self._scheme = scheme
        self._font = settings.get("font") or "JetBrainsMono Nerd Font"
        self._scale = float(settings.get("uiScale") or 1)
        self._transparency = bool(settings.get("transparency", False))
        self._opacity = float(settings.get("opacity", 0.85))
        self.changed.emit()

    def get_palette(self):
        return self._palette

    def get_scheme(self):
        return self._scheme

    def get_font(self):
        return self._font

    def get_scale(self):
        return self._scale

    def get_alpha(self):
        return self._opacity if self._transparency else 1.0

    def get_light(self):
        return self._scheme == "light"

    palette = Property("QVariantMap", get_palette, notify=changed)
    scheme = Property(str, get_scheme, notify=changed)
    font = Property(str, get_font, notify=changed)
    scale = Property(float, get_scale, notify=changed)
    panelAlpha = Property(float, get_alpha, notify=changed)
    isLight = Property(bool, get_light, notify=changed)

    def for_phone(self):
        return dict(self._palette, scheme=self._scheme, light=self._scheme == "light")
