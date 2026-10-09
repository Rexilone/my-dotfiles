"""Уведомления на рабочем столе (org.freedesktop.Notifications) через gdbus.

Показываются сервером уведомлений шелла (Quickshell), поэтому выглядят как родные.
Нажатия на действия и закрытие приходят из `gdbus monitor`.
"""
import os
import re
import subprocess
import threading
import time

from PySide6.QtCore import QObject, Signal
from .proc import popen

DEST = ["--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications"]
SIG_RE = re.compile(r"org\.freedesktop\.Notifications\.(ActionInvoked|NotificationClosed) \(uint32 (\d+), (?:'(.*)'|uint32 (\d+))\)")


def gv_str(s: str) -> str:
    """Строка в текстовом формате GVariant."""
    s = str(s).replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\r", "").replace("\t", "\\t")
    return f"'{s}'"


def escape_markup(s: str) -> str:
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


class DesktopNotify(QObject):
    action = Signal(int, str)      # id, ключ действия
    closed = Signal(int, int)      # id, причина (2 — закрыл пользователь)

    def __init__(self):
        super().__init__()
        self._lock = threading.Lock()

    def start(self):
        threading.Thread(target=self._monitor, daemon=True, name="notify-monitor").start()

    def _monitor(self):
        while True:
            try:
                p = popen(["gdbus", "monitor", *DEST], stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True)
                for line in p.stdout:
                    m = SIG_RE.search(line)
                    if not m:
                        continue
                    if m.group(1) == "ActionInvoked":
                        # ключи действий у нас только латиницей, экранирования в них нет
                        self.action.emit(int(m.group(2)), m.group(3) or "")
                    else:
                        self.closed.emit(int(m.group(2)), int(m.group(4) or 0))
            except Exception as e:  # noqa: BLE001
                print("notify monitor:", e)
            time.sleep(3)

    def notify(self, summary, body="", actions=(), icon="", app="Rexlink", replaces=0, urgency=1, timeout=-1,
               category=""):
        """actions: [(ключ, подпись)]. Возвращает id уведомления (0 — не получилось)."""
        if os.environ.get("REXLINK_NO_DESKTOP_NOTIFY"):   # тесты: не беспокоить шелл
            return 0
        acts = "[" + ", ".join(f"{gv_str(k)}, {gv_str(t)}" for k, t in actions) + "]" if actions else "@as []"
        hints = [f"'urgency': <byte {int(urgency)}>", f"'desktop-entry': <'rexlink'>"]
        if category:
            hints.append(f"'category': <{gv_str(category)}>")
        if urgency == 2:
            hints.append("'resident': <true>")
        args = ["gdbus", "call", *DEST, "--method", "org.freedesktop.Notifications.Notify",
                gv_str(app), str(int(replaces)), gv_str(icon), gv_str(summary), gv_str(escape_markup(body)),
                acts, "{" + ", ".join(hints) + "}", str(int(timeout))]
        try:
            out = subprocess.run(args, capture_output=True, text=True, timeout=5).stdout
            m = re.search(r"uint32 (\d+)", out)
            return int(m.group(1)) if m else 0
        except Exception as e:  # noqa: BLE001
            print("notify:", e)
            return 0

    def close(self, nid):
        if not nid:
            return
        subprocess.Popen(["gdbus", "call", *DEST, "--method", "org.freedesktop.Notifications.CloseNotification", str(int(nid))],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def notify_async(self, callback=None, **kw):
        def run():
            nid = self.notify(**kw)
            if callback:
                callback(nid)
        threading.Thread(target=run, daemon=True).start()
