"""Локальный API для интеграции (шелл, скрипты, бар): JSON-строки через unix-сокет.

Сокет: $XDG_RUNTIME_DIR/rexlink/rexlink.sock (доступен только своему пользователю).
Запрос:  {"id": 1, "cmd": "devices"}
Ответ:   {"id": 1, "ok": true, "result": [...]}   или   {"id": 1, "ok": false, "error": "..."}
События после {"cmd": "subscribe"}: {"event": "notification", "data": {...}}

Полный список команд и событий — docs/API.md.
"""
import json
from pathlib import Path

from PySide6.QtCore import QObject, QTimer, QUrl
from PySide6.QtNetwork import QLocalServer

from . import __version__, video
from .config import RUNTIME_DIR

SOCKET = str(RUNTIME_DIR / "rexlink.sock")
API_VERSION = 2


class ApiError(Exception):
    pass


class Api(QObject):
    def __init__(self, backend):
        super().__init__()
        self.b = backend
        self.server = QLocalServer(self)
        self.server.setSocketOptions(QLocalServer.SocketOption.UserAccessOption)
        self.subs = {}              # сокет -> set(события) | None (все)
        self.watching = {}          # сокет -> set(каналов видео), см. команду frames
        self._later = {}            # событие -> таймер (частые изменения шлём не чаще раза в 250 мс)
        backend.event.connect(self._broadcast)

        # окна у службы нет — всё, что раньше показывало окно, уходит событиями в шелл
        b = backend
        b.showRequested.connect(lambda page: self._broadcast("show", {"page": page}))
        b.replyRequested.connect(lambda data: self._broadcast("reply_request", data))
        b.toast.connect(lambda text: self._broadcast("toast", {"text": text}))
        self._coalesce(b.settingsChanged, "settings", lambda: b.settings)
        self._coalesce(b.transfersChanged, "transfers", lambda: b.transfers.snapshot())
        self._coalesce(b.devicesChanged, "devices", lambda: b._get_devices())
        self._coalesce(b.screenChanged, "screen_state", lambda: self._screens())
        self._coalesce(b.cameraChanged, "camera_state", lambda: b.camera)
        self._coalesce(b.pcMediaChanged, "pc_media", lambda: b.pcMedia)
        self._coalesce(b.clipChanged, "clips", lambda: b.clips)
        self._coalesce(b.smsChanged, "sms_state", lambda: {"device": b.current, "thread": b.thread,
                                                           "threads": b.threads, "messages": b.messages})
        video.STORE.exported.connect(lambda ch, path, w, h, seq: self._broadcast(
            "frame", {"channel": ch, "path": path, "w": w, "h": h, "seq": seq}))

    def _coalesce(self, signal, name, data):
        t = QTimer(self)
        t.setSingleShot(True)
        t.setInterval(250)
        t.timeout.connect(lambda: self._broadcast(name, data()))
        self._later[name] = t
        signal.connect(t.start)

    def _screens(self):
        """Экран каждого устройства: показ, размер, режим «экран выключен», ADB."""
        return {did: self.b.screenFor(did) for did in self.b.devs}

    def _drop(self, conn):
        self.subs.pop(conn, None)
        for ch in self.watching.pop(conn, ()):
            video.STORE.set_watch(ch, False)
        conn.deleteLater()

    def listen(self):
        QLocalServer.removeServer(SOCKET)
        if not self.server.listen(SOCKET):
            raise RuntimeError(self.server.errorString())
        self.server.newConnection.connect(self._accept)

    def _accept(self):
        while self.server.hasPendingConnections():
            conn = self.server.nextPendingConnection()
            conn.setProperty("buf", b"")
            conn.readyRead.connect(lambda c=conn: self._read(c))
            conn.disconnected.connect(lambda c=conn: self._drop(c))

    def _read(self, conn):
        buf = (conn.property("buf") or b"") + bytes(conn.readAll())
        *lines, rest = buf.split(b"\n")
        conn.setProperty("buf", rest)
        for line in lines:
            if not line.strip():
                continue
            rid = None
            try:
                req = json.loads(line)
                rid = req.get("id")
                result = self.handle(req, conn)
                self._write(conn, {"id": rid, "ok": True, "result": result})
            except (ApiError, ValueError, KeyError, TypeError) as e:
                self._write(conn, {"id": rid, "ok": False, "error": str(e) or e.__class__.__name__})

    @staticmethod
    def _write(conn, obj):
        conn.write(json.dumps(obj, ensure_ascii=False, default=str).encode() + b"\n")
        conn.flush()

    def _broadcast(self, name, data):
        for conn, wanted in list(self.subs.items()):
            if wanted is None or name in wanted:
                self._write(conn, {"event": name, "data": data})

    # ── команды
    def _dev(self, req):
        did = req.get("device") or self.b.current
        if did not in self.b.devs:
            raise ApiError(f"неизвестное устройство: {did or '(нет)'}")
        return did

    def _online(self, req):
        did = self._dev(req)
        if not self.b.server.online(did):
            raise ApiError("устройство не подключено")
        return did

    def handle(self, req, conn=None):
        b = self.b
        cmd = req.get("cmd", "")

        # общее
        if cmd == "ping":
            return "pong"
        if cmd == "version":
            return {"version": __version__, "api": API_VERSION}
        if cmd == "state":
            return b.snapshot()
        if cmd == "subscribe":
            ev = req.get("events")
            self.subs[conn] = set(ev) if ev else None
            return {"subscribed": sorted(ev) if ev else "all"}
        if cmd == "unsubscribe":
            self.subs.pop(conn, None)
            return True

        # устройства
        if cmd == "devices":
            return b._get_devices()
        if cmd == "device":
            d = b.devs[self._dev(req)]
            return {k: d[k] for k in ("id", "name", "kind", "model", "address", "online", "caps", "status", "media",
                                      "call", "lastSeen")} | {"notifications": len(d["notifs"])}
        if cmd == "select":
            b.selectDevice(self._dev(req))
            return b.current
        if cmd == "rename":
            b.renameDevice(self._dev(req), str(req["name"]))
            return True
        if cmd == "forget":
            b.forget(self._dev(req))
            return True
        if cmd == "pair_answer":
            b.answerPairFor(str(req.get("device") or b.pairing.get("id", "")), bool(req.get("accept")))
            return True
        if cmd == "pairing":
            return b.pairing

        # уведомления
        if cmd == "notifications":
            return b.devs[self._dev(req)]["notifs"]
        if cmd == "notif_action":
            b.notifActionFor(self._online(req), str(req["key"]), int(req["action"]))
            return True
        if cmd == "notif_reply":
            b.notifReplyFor(self._online(req), str(req["key"]), int(req["action"]), str(req["text"]))
            return True
        if cmd == "notif_dismiss":
            b.notifDismissFor(self._online(req), str(req["key"]))
            return True

        # медиа, звонки, SMS
        if cmd == "media":
            if "cmd2" in req or "action" in req:
                b.mediaCmdFor(self._online(req), str(req.get("action") or req.get("cmd2")), float(req.get("value", 0)))
                return True
            return b.devs[self._dev(req)]["media"]
        if cmd == "pc_media":
            if req.get("action"):
                b.pcMediaCmd(str(req["action"]))
                return True
            return b.pcMedia
        if cmd == "call":
            if req.get("action"):
                b.server.send(self._online(req), {"t": "call_cmd", "cmd": str(req["action"])})
                return True
            return b.ringing or b.devs[self._dev(req)]["call"]
        if cmd == "dial":
            b.server.send(self._online(req), {"t": "dial", "number": str(req["number"])})
            return True
        if cmd == "sms_threads":
            did = self._online(req)
            b.server.send(did, {"t": "sms_threads"})
            return b.devs[did]["threads"]   # свежий список придёт событием sms_threads
        if cmd == "sms_messages":
            b.server.send(self._online(req), {"t": "sms_messages", "thread": req["thread"]})
            return "requested"              # придёт событием sms_messages
        if cmd == "sms_send":
            b.sendSmsFrom(self._online(req), str(req["address"]), str(req["body"]))
            return True

        # буфер, файлы, поиск
        if cmd == "clipboard_pull":
            b.server.send(self._online(req), {"t": "clip_request"})
            return True
        if cmd == "clipboard_history":
            return b.clips
        if cmd == "send_files":
            paths = [str(Path(p).expanduser().resolve()) for p in req["paths"]]
            b.sendFilesTo(self._online(req), [QUrl.fromLocalFile(p).toString() for p in paths])
            return True
        if cmd == "transfers":
            return b.transfers.snapshot()
        if cmd == "transfer_cancel":
            b.cancelTransfer(str(req["fid"]))
            return True
        if cmd == "update_device":
            b.updateDevice(self._online(req))
            return True
        if cmd == "apk":
            return b._get_apk()
        if cmd == "ring":
            b.ringDevice(self._online(req))
            return True

        # камера и экран
        if cmd == "camera_start":
            b.startCameraFor(self._online(req))
            return True
        if cmd == "camera_stop":
            b.stopCamera()
            return True
        if cmd == "camera":
            return b.camera
        if cmd == "screen_start":
            b.startScreenFor(self._online(req))
            return True
        if cmd == "screen_stop":
            b.stopScreenFor(self._dev(req))
            return True
        if cmd == "screen_off":
            b.setScreenOffFor(self._online(req), bool(req.get("off", True)))
            return True
        if cmd == "input":
            ev = {k: v for k, v in req.items() if k not in ("cmd", "id", "device")}
            b.inputFor(self._online(req), ev)
            return True

        if cmd == "screen":
            return b.screenFor(self._dev(req))
        if cmd == "frames":
            # смотреть канал видео ("screen:<id>" | "camera"): пока смотрят, кадры идут событием frame
            ch, on = str(req["channel"]), bool(req.get("on", True))
            mine = self.watching.setdefault(conn, set())
            if on and ch not in mine:
                mine.add(ch)
                video.STORE.set_watch(ch, True)
            elif not on and ch in mine:
                mine.discard(ch)
                video.STORE.set_watch(ch, False)
            return sorted(mine)
        if cmd == "camera_switch":
            b.switchCamera(str(req["facing"]))
            return True
        if cmd == "adb_info":
            b.server.send(self._online(req), {"t": "adb_info"})
            return True
        if cmd == "adb_pair":
            b.adbPairFor(self._online(req), int(req["port"]), str(req["code"]))
            return True
        if cmd == "adb_connect":
            b.adbConnectFor(self._online(req), int(req["port"]))
            return True

        # SMS: открытый разговор (для переписки в шелле)
        if cmd == "sms_open":
            b.selectDevice(self._dev(req))
            if req.get("thread") in (None, ""):
                b.newThread()
            else:
                b.openThread(req["thread"])
            return True
        if cmd == "sms_state":
            return {"device": b.current, "thread": b.thread, "threads": b.threads, "messages": b.messages}

        # списки
        if cmd == "clipboard_clear":
            b.clearClips()
            return True
        if cmd == "transfers_clear":
            b.clearTransfers()
            return True
        if cmd == "notif_dismiss_all":
            did = self._online(req)
            for n in list(b.devs[did]["notifs"]):
                if n.get("clearable", True):
                    b.notifDismissFor(did, n["key"])
            return True

        # настройки
        if cmd == "settings":
            return b.settings
        if cmd == "set":
            b.setSetting(str(req["key"]), req["value"])
            return True
        if cmd == "download_dir":
            b.setDownloadDir(str(req["path"]))
            return True
        if cmd == "autostart":
            b.setAutostart(bool(req["on"]))
            return True
        if cmd == "firewall_check":
            b._check_firewall()
            return b.settings.get("firewall")

        # окно: его роль играет страница «Телефон» в Настройках шелла
        if cmd in ("show", "toggle"):
            self._broadcast("show", {"page": req.get("page", "")})
            return True
        if cmd == "hide":
            return True

        raise ApiError(f"неизвестная команда: {cmd}")
