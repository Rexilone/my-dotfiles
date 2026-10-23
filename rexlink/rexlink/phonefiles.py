"""Память телефона как папка на ПК: монтирование WebDAV телефона через gio и закладка в файловом менеджере."""
import re
import subprocess
import threading
from pathlib import Path

BOOKMARKS = Path.home() / ".config" / "gtk-3.0" / "bookmarks"


def uri(host: str, port: int) -> str:
    host = host.removeprefix("::ffff:")
    return f"dav://rexlink@{host}:{port}/"


def _bookmarks(update):
    try:
        lines = BOOKMARKS.read_text().splitlines()
    except OSError:
        lines = []
    lines = update(lines)
    BOOKMARKS.parent.mkdir(parents=True, exist_ok=True)
    BOOKMARKS.write_text("\n".join(lines) + ("\n" if lines else ""))


def bookmark(u: str, name: str):
    # одна закладка на устройство: старый адрес (сменился IP) заменяется
    def upd(lines):
        lines = [l for l in lines if not (l.startswith("dav://rexlink@") and l.split(" ", 1)[-1] == name)]
        return lines + [f"{u} {name}"]
    _bookmarks(upd)


def unbookmark(name: str):
    _bookmarks(lambda lines: [l for l in lines if not (l.startswith("dav://rexlink@") and l.split(" ", 1)[-1] == name)])


def mount(u: str, password: str, done):
    """gio спрашивает пользователя и пароль в stdin; done(ok, текст ошибки) — из фонового потока."""
    def run():
        try:
            subprocess.run(["gio", "mount", "-u", u], capture_output=True, timeout=10)
            p = subprocess.run(["gio", "mount", u], input=f"rexlink\n{password}\n", capture_output=True, text=True, timeout=30)
            ok = p.returncode == 0 or "already mounted" in p.stderr.lower()
            done(ok, "" if ok else re.sub(r"\s+", " ", p.stderr).strip())
        except (OSError, subprocess.TimeoutExpired) as e:
            done(False, str(e))
    threading.Thread(target=run, daemon=True).start()


def unmount(u: str):
    threading.Thread(target=lambda: subprocess.run(["gio", "mount", "-u", u], capture_output=True, timeout=10),
                     daemon=True).start()
