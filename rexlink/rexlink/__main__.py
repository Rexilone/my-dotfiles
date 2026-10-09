"""rexlink [--send FILE…]                 — служба (без окна: интерфейс — в Настройках шелла)
rexlink ctl <команда> [ключ=значение…]   — управление работающей службой (см. docs/API.md)
"""
import argparse
import json
import signal
import socket
import subprocess
import sys
from pathlib import Path


def forward(msg):
    """Передать команду уже запущенной службе. True — она есть."""
    from .api import SOCKET
    s = socket.socket(socket.AF_UNIX)
    try:
        s.settimeout(2)
        s.connect(SOCKET)
        s.sendall(json.dumps(msg).encode() + b"\n")
        s.recv(4096)
        return True
    except OSError:
        return False
    finally:
        s.close()


def open_settings(page=""):
    """Окна у службы нет: «открыть Rexlink» — это страница «Телефон» в Настройках шелла."""
    subprocess.Popen(["qs", "ipc", "call", "rexlink", "open", page or "overview"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "ctl":
        from . import ctl
        return ctl.main(sys.argv[2:])

    from . import __version__
    ap = argparse.ArgumentParser(prog="rexlink", description="Связь с телефоном, планшетом и часами на Android (служба)")
    ap.add_argument("--send", nargs="+", metavar="FILE", help="отправить файлы на выбранное устройство")
    # старые ключи: окна больше нет, служба всегда работает в фоне
    ap.add_argument("--hidden", "--headless", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--page", default="", help="открыть страницу в Настройках шелла")
    ap.add_argument("--version", action="version", version=__version__)
    args = ap.parse_args()

    if args.send:
        paths = [str(Path(f).resolve()) for f in args.send]
        if forward({"id": 1, "cmd": "send_files", "paths": paths}):
            return 0
    elif forward({"id": 1, "cmd": "ping"}):
        if args.page:
            open_settings(args.page)
        return 0

    from PySide6.QtCore import QCoreApplication, QTimer
    from . import video
    from .api import Api
    from .backend import Backend
    from .config import RUNTIME_DIR, Config
    from .theme import Theme

    app = QCoreApplication(sys.argv)
    app.setApplicationName("Rexlink")
    app.setOrganizationName("rexlink")

    config = Config()
    theme = Theme()
    video.STORE = video.FrameStore(str(RUNTIME_DIR / "frames"))
    backend = Backend(config, theme)

    api = Api(backend)
    api.listen()
    backend.start()
    if args.send:
        api.handle({"cmd": "send_files", "paths": args.send})

    signal.signal(signal.SIGINT, lambda *_: app.quit())
    signal.signal(signal.SIGTERM, lambda *_: app.quit())
    t = QTimer()          # даём Python обрабатывать сигналы
    t.start(500)
    t.timeout.connect(lambda: None)

    code = app.exec()
    backend.shutdown()
    return code


if __name__ == "__main__":
    sys.exit(main())
