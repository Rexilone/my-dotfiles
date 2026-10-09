"""Состояние приложения: несколько устройств сразу (телефон, планшет, часы…).

Интерфейс показывает выбранное устройство (current), уведомления и звонки приходят со всех.
Все изменения дублируются сигналом event(имя, данные) — его слушает API для интеграции (api.py).
"""
import hashlib
import json
import os
import subprocess
import threading
import time
from pathlib import Path

from PySide6.QtCore import QObject, Property, QTimer, QUrl, Signal, Slot

from . import firewall, updates, video
from .i18n import set_lang, tr
from .adb import Adb, ScrcpyVideo
from .clipboard import Clipboard
from .config import CACHE_DIR, RUNTIME_DIR
from .desktop_notify import DesktopNotify
from .mpris import Mpris
from .net import Server
from .transfers import Transfers


def local_ips():
    try:
        out = subprocess.run(["ip", "-4", "-o", "addr", "show", "scope", "global"], capture_output=True, text=True,
                             timeout=2).stdout
        return [line.split()[3].split("/")[0] for line in out.splitlines() if len(line.split()) > 3]
    except Exception:
        return []


def autostart_enabled():
    try:
        r = subprocess.run(["systemctl", "--user", "is-enabled", "rexlink.service"], capture_output=True, text=True,
                           timeout=2)
        return r.stdout.strip() == "enabled"
    except Exception:
        return False


def save_cached(prefix, data: bytes, ext="png"):
    h = hashlib.sha1(data).hexdigest()[:16]
    p = CACHE_DIR / f"{prefix}-{h}.{ext}"
    if not p.exists():
        p.write_bytes(data)
    return p


def new_dev(did, entry):
    return {"id": did, "name": entry.get("alias") or entry.get("name", ""), "kind": entry.get("kind", "phone"),
            "model": entry.get("model", ""), "caps": [], "address": entry.get("address", ""), "online": False,
            "lastSeen": entry.get("lastSeen", 0), "status": {}, "notifs": [], "media": {}, "call": {},
            "threads": [], "messages": [], "thread": {}, "screen": {"running": False, "w": 0, "h": 0},
            "adb": {"ports": {}}, "app": {}}


class Backend(QObject):
    stateChanged = Signal()
    statusChanged = Signal()
    notifsChanged = Signal()
    mediaChanged = Signal()
    pcMediaChanged = Signal()
    callChanged = Signal()
    smsChanged = Signal()
    transfersChanged = Signal()
    cameraChanged = Signal()
    screenChanged = Signal()
    clipChanged = Signal()
    settingsChanged = Signal()
    devicesChanged = Signal()
    showRequested = Signal(str)            # открыть окно на странице
    replyRequested = Signal(object)        # быстрый ответ: { device, key, action, app, title, text }
    toast = Signal(str)
    event = Signal(str, object)            # для API: имя события, данные
    _videoEvent = Signal(str, object)      # из рабочих потоков видео — в главный поток

    def __init__(self, config, theme):
        super().__init__()
        self.config = config
        self.theme = theme
        self.server = Server(config)
        self.clip = Clipboard()
        self.notifier = DesktopNotify()
        self.mpris = Mpris()
        self.adb = Adb()
        self.transfers = Transfers(self.server, config)

        self.devs = {did: new_dev(did, e) for did, e in config["devices"].items()}
        self._current = config.get("currentDevice") if config.get("currentDevice") in self.devs else \
            next(iter(self.devs), "")
        self._pairing = {}
        self._pc_media = {}
        self._camera = {"running": False, "device": "", "error": "", "owner": ""}
        self._clips = []
        self._firewall = {}
        self._desk = {}             # (устройство, ключ) -> id уведомления на рабочем столе
        self._desk_rev = {}         # id -> (вид, устройство, ключ)
        self._call_nids = {}        # устройство -> id уведомления о звонке
        self._pair_nids = {}
        self._cam_stream = None
        self._screen_streams = {}   # устройство -> VideoStream
        self._pending_off = ""
        self._apk = updates.bundled_apk()

        s = self.server
        s.message.connect(self._on_message)
        s.connected.connect(self._on_connected)
        s.disconnected.connect(self._on_disconnected)
        s.pairRequested.connect(self._on_pair_request)
        s.pairFinished.connect(self._on_pair_finished)
        self.clip.localChanged.connect(self._on_local_clip)
        self.notifier.action.connect(self._on_desk_action)
        self.notifier.closed.connect(self._on_desk_closed)
        self.mpris.changed.connect(self._on_pc_media)
        self.transfers.changed.connect(self._on_transfers_changed)
        self.transfers.finished.connect(self._on_transfer_done)
        self.adb.changed.connect(self.screenChanged)
        self.adb.result.connect(self._on_adb_result)
        video.STORE.status.connect(self._on_video_status)
        theme.changed.connect(self._send_theme)
        self._videoEvent.connect(self._on_video_event)

        self._state_timer = QTimer(self)
        self._state_timer.setSingleShot(True)
        self._state_timer.setInterval(300)
        self._state_timer.timeout.connect(self._write_state)
        for sig in (self.stateChanged, self.statusChanged, self.notifsChanged, self.mediaChanged, self.callChanged,
                    self.devicesChanged):
            sig.connect(self._state_timer.start)

        # файрвол проверяем при запуске и раз в минуту (правило могли добавить)
        self._fw_timer = QTimer(self)
        self._fw_timer.setInterval(60000)
        self._fw_timer.timeout.connect(self._check_firewall)

    def start(self):
        set_lang(self.config.get("lang", "ru"))
        self.clip.images = bool(self.config["clipboardImages"])
        self.server.start()
        self.clip.start()
        self.notifier.start()
        self.mpris.start()
        self._check_firewall()
        self._fw_timer.start()
        self._write_state()

    def shutdown(self):
        self.adb.stop_all()
        self.server.stop()
        for d in self.devs.values():
            d["online"] = False
        self._write_state()

    # ── вспомогательное
    def dev(self, did=None):
        return self.devs.get(did if did is not None else self._current) or new_dev("", {})

    def _is_cur(self, did):
        return did == self._current

    def _emit(self, did, *signals):
        if self._is_cur(did):
            for s in signals:
                s.emit()

    def _label(self, did):
        """Имя устройства для уведомлений, когда их подключено несколько."""
        online = [d for d in self.devs.values() if d["online"]]
        return f" · {self.devs[did]['name']}" if len(online) > 1 and did in self.devs else ""

    def _check_firewall(self):
        fw = firewall.check()
        if fw != self._firewall:
            self._firewall = fw
            self.settingsChanged.emit()

    # ── свойства для QML (выбранное устройство)
    def _cur_online(self):
        return self.dev()["online"]

    def _cur_device(self):
        d = self.dev()
        return {k: d[k] for k in ("id", "name", "kind", "model", "address", "caps", "online", "lastSeen")}

    online = Property(bool, _cur_online, notify=stateChanged)
    device = Property("QVariantMap", _cur_device, notify=stateChanged)
    current = Property(str, lambda self: self._current, notify=stateChanged)
    pairing = Property("QVariantMap", lambda self: self._pairing, notify=stateChanged)
    status = Property("QVariantMap", lambda self: self.dev()["status"], notify=statusChanged)
    notifications = Property("QVariantList", lambda self: self.dev()["notifs"], notify=notifsChanged)
    media = Property("QVariantMap", lambda self: self.dev()["media"], notify=mediaChanged)
    call = Property("QVariantMap", lambda self: self.dev()["call"], notify=callChanged)
    threads = Property("QVariantList", lambda self: self.dev()["threads"], notify=smsChanged)
    messages = Property("QVariantList", lambda self: self.dev()["messages"], notify=smsChanged)
    thread = Property("QVariantMap", lambda self: self.dev()["thread"], notify=smsChanged)
    pcMedia = Property("QVariantMap", lambda self: self._pc_media, notify=pcMediaChanged)
    camera = Property("QVariantMap", lambda self: self._camera, notify=cameraChanged)
    clips = Property("QVariantList", lambda self: self._clips, notify=clipChanged)

    def _get_screen(self):
        return self.screenFor(self._current)

    def screenFor(self, did):
        d = self.dev(did)
        return dict(d["screen"], off=self.adb.is_off(d["id"]), adbSerial=d["adb"].get("serial", ""),
                    adbPorts=d["adb"].get("ports", {}), adbNeedPair=bool(d["adb"].get("needPair")),
                    adbWireless=bool(d["adb"].get("wireless")))

    screen = Property("QVariantMap", _get_screen, notify=screenChanged)

    def _get_ringing(self):
        """Звонок, который сейчас звонит (с любого устройства)."""
        for d in self.devs.values():
            if d["call"].get("state") == "ringing":
                return dict(d["call"], device=d["id"], deviceName=d["name"])
        return {}

    ringing = Property("QVariantMap", _get_ringing, notify=callChanged)

    def _get_devices(self):
        res = []
        for d in self.devs.values():
            st = d["status"]
            res.append({"id": d["id"], "name": d["name"], "kind": d["kind"], "model": d["model"], "online": d["online"],
                        "address": d["address"], "battery": st.get("battery", -1), "charging": st.get("charging", False),
                        "notifications": len(d["notifs"]), "current": d["id"] == self._current,
                        "ringing": d["call"].get("state") == "ringing", "lastSeen": d["lastSeen"],
                        "appVersion": d["app"].get("version", ""), "update": d["app"].get("update", ""),
                        "updating": bool(d["app"].get("updating"))})
        res.sort(key=lambda x: (not x["online"], x["name"].lower()))
        return res

    devices = Property("QVariantList", _get_devices, notify=devicesChanged)
    transferList = Property("QVariantList", lambda self: self.transfers.snapshot(), notify=transfersChanged)

    def _get_settings(self):
        d = {k: v for k, v in self.config.data.items() if k not in ("devices",)}
        d["downloadDirResolved"] = str(self.config.downloads())
        d["webcamResolved"] = video.find_loopback(self.config["webcamDevice"]) or ""
        d["ffmpeg"] = video.ffmpeg_available()
        d["wlClipboard"] = self.clip.available
        d["playerctl"] = self.mpris.available
        d["adb"] = self.adb.adb
        d["scrcpy"] = self.adb.scrcpy
        d["fingerprint"] = ":".join(self.server.fingerprint[i:i + 2] for i in range(0, 32, 2)).upper()
        d["ips"] = local_ips()
        d["autostart"] = autostart_enabled()
        d["firewall"] = self._firewall
        return d

    settings = Property("QVariantMap", _get_settings, notify=settingsChanged)

    @Slot(str)
    def selectDevice(self, did):
        if did in self.devs and did != self._current:
            self._current = did
            self.config.set("currentDevice", did)
            for s in (self.stateChanged, self.statusChanged, self.notifsChanged, self.mediaChanged, self.callChanged,
                      self.smsChanged, self.screenChanged, self.devicesChanged):
                s.emit()
            if self.dev()["online"]:
                self.smsRefresh()

    # ── соединение и сопряжение
    def _on_connected(self, did, info):
        entry = self.config["devices"].get(did, {})
        d = self.devs.get(did) or new_dev(did, entry)
        self.devs[did] = d
        d.update(name=entry.get("alias") or info["name"], kind=info["kind"], model=info["model"], caps=info["caps"],
                 address=info["address"], online=True, lastSeen=int(time.time()))
        d["app"] = {"version": info.get("version", ""), "versionCode": info.get("versionCode", 0),
                    "update": self._apk["versionName"] if updates.is_outdated(info, self._apk) else "",
                    "updater": bool(info.get("versionCode"))}   # с 1.3.0 приложение умеет обновляться само
        if not self._current or not self.dev()["online"]:
            self._current = did
        if self._pairing.get("id") == did:
            self._pairing = {}
        self.stateChanged.emit()
        self.devicesChanged.emit()
        self.settingsChanged.emit()
        self._send_theme(did)
        self._send_settings(did)
        if self.mpris.state and self.config["pcMedia"]:
            self.server.send(did, dict(self.mpris.state, t="pc_media"), self.mpris._art or b"")
        self.toast.emit(tr("{} подключён", d["name"]))
        self.event.emit("device_connected", self._dev_info(did))
        if d["app"]["update"] and self.config.get("autoUpdateDevices", True):
            QTimer.singleShot(3000, lambda: self.updateDevice(did, auto=True))

    def _dev_info(self, did):
        d = self.devs[did]
        return {k: d[k] for k in ("id", "name", "kind", "model", "address", "online", "caps")}

    def _on_disconnected(self, did):
        d = self.devs.get(did)
        if not d:
            return
        d.update(online=False, status={}, media={}, call={}, notifs=[])
        for key in [k for k in self._desk if k[0] == did]:
            nid = self._desk.pop(key)
            self._desk_rev.pop(nid, None)
            self.notifier.close(nid)
        nid = self._call_nids.pop(did, 0)
        if nid:
            self.notifier.close(nid)
        if self._camera.get("owner") == did:
            self._stop_camera_local()
        self._stop_screen_local(did)
        for s in (self.stateChanged, self.statusChanged, self.notifsChanged, self.mediaChanged, self.callChanged,
                  self.devicesChanged):
            s.emit()
        self.event.emit("device_disconnected", {"id": did})

    def _on_pair_request(self, did, name, code):
        self._pairing = {"id": did, "name": name, "code": code}
        self.stateChanged.emit()
        self.showRequested.emit("pair")
        self.event.emit("pair_request", dict(self._pairing))

        def done(nid):
            self._pair_nids[did] = nid
            self._desk_rev[nid] = ("pair", did, "")
        self.notifier.notify_async(done, summary=tr("Сопряжение: {}", name), body=tr("Код: {}. Сверьте его с устройством.", code),
                                   actions=[("pair-yes", tr("Принять")), ("pair-no", tr("Отклонить"))], icon="phone", urgency=2)

    def _on_pair_finished(self, did):
        nid = self._pair_nids.pop(did, 0)
        if nid:
            self.notifier.close(nid)
        if self._pairing.get("id") == did:
            self._pairing = {}
        self.stateChanged.emit()
        self.event.emit("pair_finished", {"id": did})

    @Slot(bool)
    def answerPair(self, ok):
        if self._pairing:
            self.server.answer_pair(self._pairing["id"], ok)

    @Slot(str, bool)
    def answerPairFor(self, did, ok):
        self.server.answer_pair(did, ok)

    @Slot(str)
    def forget(self, did):
        self.server.forget(did)
        self.devs.pop(did, None)
        if self._current == did:
            self._current = next(iter(self.devs), "")
        self.stateChanged.emit()
        self.devicesChanged.emit()
        self.settingsChanged.emit()

    @Slot(str, str)
    def renameDevice(self, did, name):
        self.server.rename(did, name)
        if did in self.devs and name.strip():
            self.devs[did]["name"] = name.strip()
        self.devicesChanged.emit()
        self.stateChanged.emit()

    @Slot(str, "QVariant")
    def setSetting(self, key, value):
        if hasattr(value, "toVariant"):
            value = value.toVariant()
        if isinstance(self.config.get(key), dict) and isinstance(value, dict):
            value = dict(self.config[key], **value)
        self.config.set(key, value)
        if key == "clipboardImages":
            self.clip.images = bool(value)
        if key == "lang":
            set_lang(value)
        if key == "camera" and self._cam_stream:
            self._restart_camera_decoder()
        self.settingsChanged.emit()
        for did in list(self.server.conns):
            self._send_settings(did)

    @Slot(bool)
    def setAutostart(self, on):
        subprocess.run(["systemctl", "--user", "enable" if on else "disable", "rexlink.service"],
                       capture_output=True, timeout=10)
        self.settingsChanged.emit()

    @Slot(str)
    def setDownloadDir(self, url):
        self.config.set("downloadDir", QUrl(url).toLocalFile() if url.startswith("file:") else url)
        self.settingsChanged.emit()

    def _send_settings(self, did):
        c = self.config
        self.server.send(did, {"t": "pc_settings", "clipboard": c["clipboard"], "clipboardImages": c["clipboardImages"],
                               "notifications": c["notifications"], "calls": c["calls"], "sms": c["sms"],
                               "media": c["media"], "pcMedia": c["pcMedia"]})

    def _send_theme(self, did=None):
        h = {"t": "theme", "palette": self.theme.for_phone()}
        if did:
            self.server.send(did, h)
        else:
            self.server.broadcast(h)

    # ── входящие сообщения
    def _on_message(self, did, h, payload):
        if did not in self.devs:
            return
        t = h.get("t")
        handler = getattr(self, f"_m_{t}", None)
        if handler:
            try:
                handler(did, h, payload)
            except Exception as e:  # noqa: BLE001
                print(f"handler {t}:", e)

    def _m_status(self, did, h, _):
        self.devs[did]["status"] = {k: v for k, v in h.items() if k != "t"}
        self._emit(did, self.statusChanged)
        self.devicesChanged.emit()
        self.event.emit("status", {"device": did, **self.devs[did]["status"]})

    # буфер обмена: общий для всех устройств
    def _m_clip(self, did, h, payload):
        if not self.config["clipboard"]:
            return
        kind = h.get("kind", "text")
        if kind == "image":
            if not self.config["clipboardImages"] or not payload:
                return
            data, mime = payload, h.get("mime", "image/png")
        else:
            data, mime = str(h.get("text", "")), "text/plain"
        if self.clip.set_remote(kind, mime, data):
            self._add_clip("in", kind, data, mime, did)
            # остальным устройствам — тоже: буфер общий
            if kind == "image":
                self.server.broadcast({"t": "clip", "kind": "image", "mime": mime}, data, exclude=did)
            else:
                self.server.broadcast({"t": "clip", "kind": "text", "text": data}, exclude=did)

    def _on_local_clip(self, kind, mime, data):
        if not (self.config["clipboard"] and self.server.conns):
            return
        if kind == "image":
            if not self.config["clipboardImages"]:
                return
            self.server.broadcast({"t": "clip", "kind": "image", "mime": mime}, data)
        else:
            self.server.broadcast({"t": "clip", "kind": "text", "text": data})
        self._add_clip("out", kind, data, mime, "")

    def _add_clip(self, direction, kind, data, mime, did):
        item = {"dir": direction, "kind": kind, "time": time.strftime("%H:%M"),
                "device": self.devs[did]["name"] if did in self.devs else ""}
        if kind == "image":
            ext = mime.split("/")[-1].replace("jpeg", "jpg")
            item["url"] = QUrl.fromLocalFile(str(save_cached("clip", data, ext))).toString()
        else:
            item["text"] = data[:2000]
        self._clips = [item] + self._clips[:29]
        self.clipChanged.emit()
        self.event.emit("clipboard", dict(item, deviceId=did))

    @Slot()
    def clearClips(self):
        self._clips = []
        self.clipChanged.emit()

    @Slot()
    def requestPhoneClipboard(self):
        self.server.send(self._current, {"t": "clip_request"})

    # уведомления
    def _m_notif(self, did, h, payload):
        d = self.devs[did]
        key = h["key"]
        n = {k: v for k, v in h.items() if k not in ("t", "bin")}
        n["device"] = did
        if payload:
            n["icon"] = QUrl.fromLocalFile(str(save_cached("icon", payload))).toString()
        n["received"] = time.time()
        old = next((x for x in d["notifs"] if x["key"] == key), None)
        d["notifs"] = [n] + [x for x in d["notifs"] if x["key"] != key]
        d["notifs"].sort(key=lambda x: x.get("time", 0), reverse=True)
        d["notifs"] = d["notifs"][:200]
        self._emit(did, self.notifsChanged)
        self.devicesChanged.emit()
        self.event.emit("notification", n)
        if not (self.config["notifications"] and self.config["mirrorToDesktop"]):
            return
        if old and old.get("title") == n.get("title") and old.get("text") == n.get("text"):
            return
        if h.get("silent"):
            return
        actions = [("default", tr("Открыть"))]
        for a in n.get("actions", []):
            actions.append((f"r{a['i']}" if a.get("reply") else f"a{a['i']}", a["title"]))
        icon = Path(QUrl(n["icon"]).toLocalFile()) if n.get("icon") else ""
        dk = (did, key)

        def done(nid):
            if not nid:
                return
            prev = self._desk.get(dk)
            if prev and prev != nid:
                self._desk_rev.pop(prev, None)
            self._desk[dk] = nid
            self._desk_rev[nid] = ("notif", did, key)
        self.notifier.notify_async(done, summary=n.get("title") or n.get("app", ""), body=n.get("text", ""),
                                   actions=actions, icon=str(icon), app=n.get("app", tr("Телефон")) + self._label(did),
                                   replaces=self._desk.get(dk, 0))

    def _m_notif_removed(self, did, h, _):
        key = h["key"]
        d = self.devs[did]
        d["notifs"] = [x for x in d["notifs"] if x["key"] != key]
        self._emit(did, self.notifsChanged)
        self.devicesChanged.emit()
        nid = self._desk.pop((did, key), 0)
        if nid:
            self._desk_rev.pop(nid, None)
            self.notifier.close(nid)
        self.event.emit("notification_removed", {"device": did, "key": key})

    def _m_notif_list(self, did, h, _):
        keys = set(h.get("keys", []))
        d = self.devs[did]
        d["notifs"] = [x for x in d["notifs"] if x["key"] in keys]
        self._emit(did, self.notifsChanged)

    def _on_desk_action(self, nid, key):
        kind, did, ref = self._desk_rev.get(nid, (None, None, None))
        if kind == "pair":
            self.server.answer_pair(did, key == "pair-yes")
            return
        if did and did in self.devs and key == "default":
            self.selectDevice(did)
        if kind == "notif":
            if key == "default":
                self.showRequested.emit("notifications")
            elif key.startswith("a"):
                self.notifActionFor(did, ref, int(key[1:]))
            elif key.startswith("r"):
                self.openReplyFor(did, ref, int(key[1:]))
        elif kind == "call":
            if key in ("accept", "reject", "silence"):
                self.server.send(did, {"t": "call_cmd", "cmd": key})
            elif key == "default":
                self.showRequested.emit("calls")
        elif kind == "sms":
            self.selectDevice(did)
            self.showRequested.emit("messages")
            self.openThread(ref)
        elif kind == "file":
            if key == "open-dir":
                self.openPath(str(Path(ref).parent))
            elif key in ("open", "default"):
                self.openPath(ref)

    def _on_desk_closed(self, nid, reason):
        kind, did, ref = self._desk_rev.pop(nid, (None, None, None))
        if kind == "notif":
            if self._desk.get((did, ref)) == nid:
                self._desk.pop((did, ref), None)
            if reason == 2:   # смахнули на ПК — смахиваем и на устройстве
                self.notifDismissFor(did, ref)

    @Slot(str, int)
    def notifAction(self, key, index):
        self.notifActionFor(self._current, key, index)

    @Slot(str, str, int)
    def notifActionFor(self, did, key, index):
        self.server.send(did, {"t": "notif_action", "key": key, "i": index})

    @Slot(str, int, str)
    def notifReply(self, key, index, text):
        self.notifReplyFor(self._current, key, index, text)

    @Slot(str, str, int, str)
    def notifReplyFor(self, did, key, index, text):
        if text.strip():
            self.server.send(did, {"t": "notif_reply", "key": key, "i": index, "text": text})

    @Slot(str)
    def notifDismiss(self, key):
        self.notifDismissFor(self._current, key)

    @Slot(str, str)
    def notifDismissFor(self, did, key):
        d = self.devs.get(did)
        if not d:
            return
        n = next((x for x in d["notifs"] if x["key"] == key), None)
        if n and n.get("clearable") is False:
            return
        self.server.send(did, {"t": "notif_dismiss", "key": key})
        self._m_notif_removed(did, {"key": key}, None)

    @Slot()
    def notifDismissAll(self):
        for n in list(self.dev()["notifs"]):
            if n.get("clearable", True):
                self.notifDismiss(n["key"])

    @Slot(str, int)
    def openReply(self, key, index):
        self.openReplyFor(self._current, key, index)

    def openReplyFor(self, did, key, index):
        n = next((x for x in self.devs[did]["notifs"] if x["key"] == key), None)
        if n:
            self.replyRequested.emit({"device": did, "key": key, "action": index, "app": n.get("app", ""),
                                      "title": n.get("title", ""), "text": n.get("text", ""), "icon": n.get("icon", "")})

    # медиа устройства
    def _m_media(self, did, h, payload):
        d = self.devs[did]
        m = {k: v for k, v in h.items() if k not in ("t", "bin")}
        if payload:
            m["art"] = QUrl.fromLocalFile(str(save_cached("art", payload, "jpg"))).toString()
        elif d["media"].get("title") == m.get("title"):
            m["art"] = d["media"].get("art", "")
        m["at"] = time.time() * 1000
        d["media"] = m
        self._emit(did, self.mediaChanged)
        self.event.emit("media", dict(m, device=did))

    @Slot(str)
    @Slot(str, float)
    def mediaCmd(self, cmd, value=0.0):
        self.server.send(self._current, {"t": "media_cmd", "cmd": cmd, "value": value})

    @Slot(str, str, float)
    def mediaCmdFor(self, did, cmd, value=0.0):
        self.server.send(did, {"t": "media_cmd", "cmd": cmd, "value": value})

    # медиа ПК → устройства
    def _on_pc_media(self, state, art):
        self._pc_media = dict(state)
        self.pcMediaChanged.emit()
        if self.config["pcMedia"]:
            self.server.broadcast(dict(state, t="pc_media"), art if art and len(art) < (2 << 20) else b"")

    def _m_pc_media_cmd(self, did, h, _):
        self.mpris.command(h.get("cmd"), h.get("value"))

    @Slot(str)
    def pcMediaCmd(self, cmd):
        self.mpris.command(cmd)

    # звонки
    def _m_call(self, did, h, _):
        d = self.devs[did]
        state = h.get("state")
        d["call"] = {k: v for k, v in h.items() if k != "t"}
        self.callChanged.emit()
        self.devicesChanged.emit()
        self.event.emit("call", dict(d["call"], device=did))
        if not self.config["calls"]:
            return
        who = h.get("name") or h.get("number") or tr("Неизвестный номер")
        if state == "ringing":
            def done(nid):
                self._call_nids[did] = nid
                self._desk_rev[nid] = ("call", did, "")
            self.notifier.notify_async(done, summary=tr("Входящий звонок") + self._label(did),
                                       body=f"{who}\n{h.get('number', '') if h.get('name') else ''}".strip(),
                                       actions=[("default", tr("Открыть")), ("accept", tr("Принять")), ("reject", tr("Сбросить")),
                                                ("silence", tr("Без звука"))],
                                       icon="call-start", urgency=2, category="call.incoming",
                                       replaces=self._call_nids.get(did, 0))
            self.showRequested.emit("call")
        else:
            nid = self._call_nids.pop(did, 0)
            if nid:
                self.notifier.close(nid)
                self._desk_rev.pop(nid, None)
            if state == "missed":
                self.notifier.notify_async(summary=tr("Пропущенный звонок") + self._label(did), body=who, icon="call-missed")
            if state in ("idle", "missed"):
                d["call"] = {}
                self.callChanged.emit()

    @Slot(str)
    def callCmd(self, cmd):
        """Звонок, который сейчас звонит, иначе — выбранное устройство."""
        ring = self._get_ringing()
        self.server.send(ring.get("device") or self._current, {"t": "call_cmd", "cmd": cmd})

    @Slot(str)
    def dial(self, number):
        self.server.send(self._current, {"t": "dial", "number": number})

    # SMS
    def _m_sms_threads(self, did, h, _):
        self.devs[did]["threads"] = h.get("threads", [])
        self._emit(did, self.smsChanged)
        self.event.emit("sms_threads", {"device": did, "threads": self.devs[did]["threads"]})

    def _m_sms_messages(self, did, h, _):
        d = self.devs[did]
        if str(h.get("thread")) == str(d["thread"].get("id")):
            d["messages"] = h.get("messages", [])
            self._emit(did, self.smsChanged)
        self.event.emit("sms_messages", {"device": did, "thread": h.get("thread"), "messages": h.get("messages", [])})

    def _m_sms_received(self, did, h, _):
        d = self.devs[did]
        self.server.send(did, {"t": "sms_threads"})
        if str(h.get("thread")) == str(d["thread"].get("id")):
            self.server.send(did, {"t": "sms_messages", "thread": d["thread"].get("id")})
        self.event.emit("sms_received", dict({k: v for k, v in h.items() if k != "t"}, device=did))
        if not self.config["sms"]:
            return
        tid = str(h.get("thread", ""))

        def done(nid):
            self._desk_rev[nid] = ("sms", did, tid)
        self.notifier.notify_async(done, summary=h.get("name") or h.get("address", "SMS"), body=h.get("body", ""),
                                   actions=[("default", tr("Ответить"))], icon="mail-message-new", app="SMS" + self._label(did))

    def _m_sms_sent(self, did, h, _):
        self.toast.emit(tr("SMS отправлено") if h.get("ok") else tr("SMS не отправлено: {}", h.get("error", "")))
        d = self.devs[did]
        if d["thread"].get("id") not in (None, ""):
            self.server.send(did, {"t": "sms_messages", "thread": d["thread"]["id"]})
        self.server.send(did, {"t": "sms_threads"})
        self.event.emit("sms_sent", dict({k: v for k, v in h.items() if k != "t"}, device=did))

    @Slot()
    def smsRefresh(self):
        self.server.send(self._current, {"t": "sms_threads"})

    @Slot("QVariant")
    def openThread(self, tid):
        if tid in (None, ""):
            return
        d = self.dev()
        t = next((x for x in d["threads"] if str(x.get("id")) == str(tid)), None)
        d["thread"] = t or {"id": tid}
        d["messages"] = []
        self.smsChanged.emit()
        self.server.send(self._current, {"t": "sms_messages", "thread": tid})

    @Slot()
    def newThread(self):
        d = self.dev()
        d["thread"] = {"id": "", "new": True}
        d["messages"] = []
        self.smsChanged.emit()

    @Slot(str, str)
    def sendSms(self, address, body):
        self.sendSmsFrom(self._current, address, body)

    @Slot(str, str, str)
    def sendSmsFrom(self, did, address, body):
        if address.strip() and body.strip():
            self.server.send(did, {"t": "sms_send", "address": address.strip(), "body": body})

    # файлы
    def _m_file_offer(self, did, h, _):
        self.transfers.incoming(did, h)

    def _m_file_cancel(self, did, h, _):
        fid = h.get("fid")
        s = self.transfers._socks.pop(fid, None)
        for i in self.transfers.items:
            if i["fid"] == fid and i["state"] == "active":
                i["state"] = "cancelled"
        if s:
            s.close()
        self.transfersChanged.emit()

    def _on_transfers_changed(self):
        self.transfersChanged.emit()

    def _on_transfer_done(self, item):
        item = dict(item, deviceName=self.devs.get(item.get("device"), {}).get("name", ""))
        self.event.emit("transfer", item)
        if item["dir"] == "in" and item["state"] == "done":
            path = item["path"]

            def done(nid):
                self._desk_rev[nid] = ("file", item.get("device"), path)
            self.notifier.notify_async(done, summary=tr("Файл получен") + self._label(item.get("device")), body=item["name"],
                                       icon="document-save", actions=[("open", tr("Открыть")), ("open-dir", tr("Папка"))])

    @Slot("QVariantList")
    def sendFiles(self, urls):
        self.sendFilesTo(self._current, urls)

    @Slot(str, "QVariantList")
    def sendFilesTo(self, did, urls):
        paths = []
        for u in urls:
            u = u.toString() if hasattr(u, "toString") else str(u)
            paths.append(QUrl(u).toLocalFile() if u.startswith("file:") else u)
        if not self.server.online(did):
            self.toast.emit(tr("Устройство не подключено"))
            return
        self.transfers.send_files(did, paths)

    @Slot(str)
    def cancelTransfer(self, fid):
        self.transfers.cancel(fid)

    @Slot()
    def clearTransfers(self):
        self.transfers.clear()

    @Slot(str)
    def openPath(self, path):
        subprocess.Popen(["xdg-open", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    # веб-камера: одна на всех (одно устройство v4l2loopback)
    def _camera_decoder(self, w, h):
        cam = self.config["camera"]
        sink = video.find_loopback(self.config["webcamDevice"])
        self._videoEvent.emit("camera_config", {"device": sink or "", "w": w, "h": h,
                                                "error": "" if sink else tr("Нет устройства v4l2loopback — показываю только превью")})
        filters = video.camera_filters(int(cam.get("rotate", 0)), bool(cam.get("mirror", False)))
        if sink:
            return video.Decoder("camera", w, h, sink=sink, filters=filters)
        if filters:
            ow, oh = (h, w) if "transpose" in filters else (w, h)
            return video.Decoder("camera", ow, oh, filters=filters)
        return video.Decoder("camera", w, h)

    @Slot()
    def startCamera(self):
        self.startCameraFor(self._current)

    @Slot(str)
    def startCameraFor(self, did):
        if not self.server.online(did) or self._cam_stream:
            return
        stream = video.VideoStream("camera", self._camera_decoder,
                                   on_end=lambda: self._videoEvent.emit("camera_end", stream))
        self._cam_stream = stream
        cam = self.config["camera"]
        sid = self.server.expect_stream(did, stream.run)
        self.server.send(did, {"t": "camera_start", "sid": sid, "facing": cam["facing"], "w": cam["width"],
                               "h": cam["height"], "fps": cam["fps"], "bitrate": cam["bitrate"]})
        self._camera = {"running": True, "device": "", "error": "", "starting": True, "owner": did,
                        "ownerName": self.devs[did]["name"]}
        self.cameraChanged.emit()
        self.event.emit("camera", dict(self._camera))

    @Slot()
    def stopCamera(self):
        owner = self._camera.get("owner")
        if owner:
            self.server.send(owner, {"t": "camera_stop"})
        self._stop_camera_local()

    def _stop_camera_local(self):
        if self._cam_stream:
            self._cam_stream.stop()
            self._cam_stream = None
        self._camera = {"running": False, "device": "", "error": "", "owner": ""}
        self.cameraChanged.emit()
        self.event.emit("camera", dict(self._camera))

    def _on_video_event(self, kind, data):
        if kind == "camera_config":
            self._camera = dict(self._camera, **data)
            self.cameraChanged.emit()
        elif kind == "camera_end":
            if self._cam_stream is data:
                self._cam_stream = None
                self._camera = dict(self._camera, running=False)
                self.cameraChanged.emit()
        elif kind == "screen_config":
            did, cfg = data
            if did in self.devs:
                self.devs[did]["screen"] = dict(self.devs[did]["screen"], running=True, starting=False,
                                                w=cfg["w"], h=cfg["h"])
                self._emit(did, self.screenChanged)
        elif kind == "screen_end":
            did, stream = data
            if self._screen_streams.get(did) is stream:
                self._screen_ended(did)
        elif kind == "update_done":
            did, ok, out = data
            d = self.devs.get(did)
            if d:
                d["app"]["updating"] = False
                if ok:
                    d["app"]["update"] = ""
                self.devicesChanged.emit()
                self.toast.emit(tr("{}: приложение обновлено", d["name"]) if ok else tr("{}: обновить не вышло — {}", d["name"], out))
                self.event.emit("update", {"device": did, "ok": ok})
        elif kind == "screen_fallback":
            did, stream, err = data
            if self._screen_streams.get(did) is stream:
                del self._screen_streams[did]
                print("adb-захват не удался:", err)
                self.toast.emit(tr("Без ADB — Android один раз спросит разрешение на устройстве"))
                self._start_screen_phone(did)

    def _restart_camera_decoder(self):
        if self._cam_stream:
            self._cam_stream.restart_decoder()
            self.server.send(self._camera.get("owner", ""), {"t": "keyframe", "what": "camera"})

    @Slot(str)
    def switchCamera(self, facing):
        self.setSetting("camera", {"facing": facing})
        if self._cam_stream:
            self.server.send(self._camera.get("owner", ""), {"t": "camera_switch", "facing": facing})

    def _m_camera_state(self, did, h, _):
        if h.get("error"):
            self._camera = dict(self._camera, error=h["error"], running=False)
            if self._cam_stream:
                self._cam_stream.stop()
                self._cam_stream = None
        else:
            self._camera = dict(self._camera, starting=False)
        self.cameraChanged.emit()

    def _on_video_status(self, ch, msg):
        if ch == "camera":
            self._camera = dict(self._camera, error=msg)
            self.cameraChanged.emit()
        elif ch.startswith("screen:"):
            did = ch[7:]
            self.toast.emit(tr("Экран: {}", msg))
            if did in self._screen_streams:
                self.stopScreenFor(did)

    # экран устройства (у каждого свой поток; канал кадров — "screen:<id>")
    @Slot()
    def startScreen(self):
        self.startScreenFor(self._current)

    @Slot(str)
    def startScreenFor(self, did):
        if not self.server.online(did) or did in self._screen_streams:
            return
        sc = self.config["screen"]
        d = self.devs[did]
        self.devs[did]["screen"] = {"running": True, "starting": True, "w": 0, "h": 0}
        self._emit(did, self.screenChanged)
        self.event.emit("screen", {"device": did, "running": True})
        if sc.get("keepAwake", True):
            self.server.send(did, {"t": "keep_awake", "on": True})
        # есть adb (USB или «Отладка по Wi-Fi») — как scrcpy, без запроса на устройстве
        if self.adb.available and sc.get("adb", True):
            self._start_screen_adb(did)
        else:
            self._start_screen_phone(did)

    def _screen_decoder(self, did):
        ch = f"screen:{did}"
        return lambda w, h: video.Decoder(ch, w, h)

    def _start_screen_phone(self, did):
        """Захват на устройстве (MediaProjection): Android спросит разрешение."""
        sc = self.config["screen"]
        stream = video.VideoStream(f"screen:{did}", self._screen_decoder(did),
                                   on_config=lambda cfg: self._videoEvent.emit("screen_config", (did, cfg)),
                                   on_end=lambda: self._videoEvent.emit("screen_end", (did, stream)))
        self._screen_streams[did] = stream
        sid = self.server.expect_stream(did, stream.run)
        self.server.send(did, {"t": "screen_start", "sid": sid, "maxSize": sc["maxSize"], "bitrate": sc["bitrate"],
                               "fps": sc["fps"], "keepAwake": bool(sc.get("keepAwake", True))})
        self.devs[did]["screen"]["source"] = "phone"
        self._emit(did, self.screenChanged)

    def _start_screen_adb(self, did):
        sc = self.config["screen"]
        d = self.devs[did]
        holder = {}
        stream = video.RawVideoStream(f"screen:{did}", self._screen_decoder(did),
                                      on_config=lambda cfg: self._videoEvent.emit("screen_config", (did, cfg)),
                                      on_end=lambda: (holder["src"].stop() if "src" in holder else None,
                                                      self._videoEvent.emit("screen_end", (did, stream))),
                                      on_stop=lambda: holder["src"].stop() if "src" in holder else None)
        self._screen_streams[did] = stream
        d["screen"]["source"] = "adb"

        def run():
            serial = self.adb.find(d["address"], d["model"])
            port = d["adb"].get("ports", {}).get("connect")
            if not serial and port:   # «Отладка по Wi-Fi» включена, но adb ещё не подключён
                self.adb.connect(d["address"], port)
                serial = self.adb.find(d["address"], d["model"])
            if not serial:
                self._videoEvent.emit("screen_fallback", (did, stream, "устройство не подключено к adb"))
                return
            d["adb"]["serial"] = serial
            src = holder["src"] = ScrcpyVideo(serial, sc["maxSize"], sc["bitrate"], sc["fps"])
            try:
                sock, first = src.start()
            except Exception as e:  # noqa: BLE001
                src.stop()
                self._videoEvent.emit("screen_fallback", (did, stream, str(e)))
                return
            if stream.stopped:
                sock.close()
                src.stop()
                return
            stream.run(sock, first)
        threading.Thread(target=run, daemon=True, name="scrcpy-video").start()

    @Slot()
    def stopScreen(self):
        self.stopScreenFor(self._current)

    @Slot(str)
    def stopScreenFor(self, did):
        self.server.send(did, {"t": "screen_stop"})
        self._stop_screen_local(did)

    def _stop_screen_local(self, did):
        st = self._screen_streams.pop(did, None)
        if st:
            st.stop()
        self.server.send(did, {"t": "keep_awake", "on": False})
        self.adb.screen_on(did)
        if did in self.devs:
            self.devs[did]["screen"] = {"running": False, "w": 0, "h": 0}
            self._emit(did, self.screenChanged)
            self.event.emit("screen", {"device": did, "running": False})

    def _screen_ended(self, did):
        self._screen_streams.pop(did, None)
        self.server.send(did, {"t": "keep_awake", "on": False})
        self.adb.screen_on(did)
        self.devs[did]["screen"] = {"running": False, "w": 0, "h": 0}
        self._emit(did, self.screenChanged)
        self.event.emit("screen", {"device": did, "running": False})

    def _m_screen_state(self, did, h, _):
        if h.get("error"):
            self.toast.emit(h["error"])
            self._stop_screen_local(did)
        else:
            self.devs[did]["screen"] = dict(self.devs[did]["screen"], **{k: v for k, v in h.items() if k != "t"})
            self._emit(did, self.screenChanged)

    @Slot("QVariantMap")
    def input(self, ev):
        self.server.send(self._current, dict(ev, t="input"))

    @Slot(str, "QVariantMap")
    def inputFor(self, did, ev):
        self.server.send(did, dict(ev, t="input"))

    # ── экран выключен (ADB + scrcpy)
    def _m_adb_info(self, did, h, _):
        d = self.devs[did]
        d["adb"]["ports"] = {k: int(v) for k, v in (h.get("ports") or {}).items() if v}
        d["adb"]["wireless"] = bool(h.get("wireless"))
        self._emit(did, self.screenChanged)

    @Slot()
    def requestAdbInfo(self):
        self.server.send(self._current, {"t": "adb_info"})

    @Slot(bool)
    def setScreenOff(self, off):
        self.setScreenOffFor(self._current, off)

    @Slot(str, bool)
    def setScreenOffFor(self, did, off):
        if did not in self.devs:
            return
        if not off:
            self.adb.screen_on(did)
            return
        if not self.adb.available:
            self.toast.emit(tr("Нужны пакеты android-tools и scrcpy"))
            return
        d = self.devs[did]
        serial = self.adb.find(d["address"], d["model"])
        if serial:
            d["adb"]["serial"] = serial
            d["adb"]["needPair"] = False
            self.adb.screen_off(did, serial)
            self.event.emit("screen", {"device": did, "off": True})
            return
        # к adb не подключены — пробуем по порту беспроводной отладки
        port = d["adb"]["ports"].get("connect") or self.adb.avahi_ports(d["address"]).get("connect")
        if not port:
            self.server.send(did, {"t": "adb_info"})
            d["adb"]["needPair"] = True
            self.screenChanged.emit()
            self.toast.emit(tr("Включите на устройстве «Отладку по Wi-Fi»"))
            return
        self._pending_off = did
        self.adb.async_call("connect", self.adb.connect, d["address"], port)

    @Slot(int, str)
    def adbPair(self, port, code):
        self.adbPairFor(self._current, port, code)

    def adbPairFor(self, did, port, code):
        d = self.dev(did)
        self._pending_off = d["id"]
        self.adb.async_call("pair", self.adb.pair, d["address"], port, code)

    @Slot(int)
    def adbConnect(self, port):
        self.adbConnectFor(self._current, port)

    def adbConnectFor(self, did, port):
        d = self.dev(did)
        self._pending_off = d["id"]
        self.adb.async_call("connect", self.adb.connect, d["address"], port)

    def _on_adb_result(self, action, ok, text):
        did = self._pending_off
        if action == "pair":
            self.toast.emit(tr("ADB: сопряжение выполнено") if ok else tr("ADB: {}", text[-120:]))
            if ok and did:
                self.server.send(did, {"t": "adb_info"})
                QTimer.singleShot(1500, lambda: self.setScreenOffFor(did, True))
        elif action == "connect":
            if ok and did:
                self.setScreenOffFor(did, True)
            else:
                self.toast.emit(tr("ADB: не подключиться — нужно сопряжение по коду"))
                if did in self.devs:
                    self.devs[did]["adb"]["needPair"] = True
        elif action == "screen_off" and not ok:
            self.toast.emit(tr("Экран: {}", text[-120:]))
        self.screenChanged.emit()

    # ── обновление приложения на устройствах
    def _get_apk(self):
        return {k: v for k, v in (self._apk or {}).items() if k != "path"}

    apk = Property("QVariantMap", _get_apk, notify=settingsChanged)

    @Slot(str)
    def updateDevice(self, did, auto=False):
        """По adb — тихо (`adb install -r`); иначе — устройство само скачает APK и поставит."""
        d = self.devs.get(did)
        if not d or not d["online"] or not self._apk:
            return
        serial = self.adb.find(d["address"], d["model"]) if self.adb.adb else None
        if serial:
            d["app"]["updating"] = True
            self.devicesChanged.emit()
            self.toast.emit(tr("{}: обновление через adb…", d["name"]))
            apk = self._apk["path"]

            def run():
                from .adb import _run
                code, out = _run(["adb", "-s", serial, "install", "-r", apk], timeout=180)
                self._videoEvent.emit("update_done", (did, "Success" in out, out[-160:]))
            threading.Thread(target=run, daemon=True).start()
            return
        if d["app"].get("updater"):
            self.server.send(did, {"t": "update_available", "versionCode": self._apk["versionCode"],
                                   "versionName": self._apk["versionName"], "now": not auto})
            if not auto:
                self.toast.emit(tr("{}: обновление отправлено — подтвердите на устройстве, если спросит", d["name"]))
        elif not auto:
            self.toast.emit(tr("{}: старая версия обновляется только по adb (USB или «Отладка по Wi-Fi»)", d["name"]))

    def _m_update_get(self, did, h, _):
        apk = self._apk
        if not apk:
            return

        def stream(sock):
            with open(apk["path"], "rb") as f:
                while chunk := f.read(256 * 1024):
                    sock.sendall(chunk)
            sock.settimeout(60)
            sock.recv(1)
        sid = self.server.expect_stream(did, stream)
        self.server.send(did, {"t": "update_file", "sid": sid, "size": apk["size"], "sha256": apk["sha256"]})

    def _m_update_result(self, did, h, _):
        if not h.get("ok"):
            self.toast.emit(tr("{}: обновление не установлено — {}", self.devs[did]["name"], h.get("error", "")))

    # прочее
    @Slot()
    def ring(self):
        self.server.send(self._current, {"t": "ring"})

    @Slot(str)
    def ringDevice(self, did):
        self.server.send(did, {"t": "ring"})

    def _m_toast(self, did, h, _):
        self.toast.emit(h.get("text", ""))

    # ── снимок состояния (модуль бара Quickshell, API, скрипты)
    def snapshot(self):
        cur = self.dev()
        return {"online": cur["online"], "device": cur["name"], **cur["status"],
                "notifications": len(cur["notifs"]),
                "media": {k: cur["media"].get(k) for k in ("title", "artist", "playing")},
                "call": self._get_ringing().get("state", cur["call"].get("state", "")),
                "current": self._current, "devices": self._get_devices(), "updated": time.time()}

    def _write_state(self):
        p = RUNTIME_DIR / "state.json"
        tmp = p.with_suffix(".tmp")
        try:
            tmp.write_text(json.dumps(self.snapshot(), ensure_ascii=False))
            os.replace(tmp, p)
        except OSError:
            pass
