#!/usr/bin/env python3
"""Трей (StatusNotifierItem) для amane: сам становится StatusNotifierWatcher, а если он уже есть
(например, Quickshell) — только читает его список. Печатает строки JSON:
  {"items": [{id, service, path, title, status, icon, menu, only_menu, tooltip}]}
  {"menu": {"service": ..., "layout": {...}}}
Читает команды строками JSON из stdin: activate / secondary / scroll / menu / event."""
import ctypes, hashlib, json, os, signal, struct, sys, threading, zlib

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

ctypes.CDLL("libc.so.6").prctl(1, signal.SIGTERM)  # умереть вместе с amane

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
WATCHER = "org.kde.StatusNotifierWatcher"
ITEM = "org.kde.StatusNotifierItem"
CACHE = os.path.expanduser("~/.cache/amane/tray")
os.makedirs(CACHE, exist_ok=True)

hosting = False
items = {}  # key "service|path" -> info


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def publish():
    emit({"items": sorted(items.values(), key=lambda i: i["key"])})


def png(w, h, rgba):
    raw = b"".join(b"\x00" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def pixmap_file(pixmaps):
    """ARGB32 (сетевой порядок) → PNG; берём размер ближе к 48"""
    best = None
    for w, h, data in pixmaps or []:
        w, h = int(w), int(h)
        if w <= 0 or h <= 0 or len(data) < w * h * 4:
            continue
        if best is None or abs(w - 48) < abs(best[0] - 48):
            best = (w, h, bytes(bytearray(data)))
    if not best:
        return ""
    w, h, data = best
    rgba = bytearray(w * h * 4)
    for i in range(w * h):
        a, r, g, b = data[i * 4:i * 4 + 4]
        rgba[i * 4:i * 4 + 4] = bytes((r, g, b, a))
    name = os.path.join(CACHE, hashlib.md5(data).hexdigest() + ".png")
    if not os.path.exists(name):
        with open(name + ".part", "wb") as f:
            f.write(png(w, h, bytes(rgba)))
        os.replace(name + ".part", name)
    return name


def theme_icon(theme_path, name):
    if not name:
        return ""
    if name.startswith("/"):
        return name
    if theme_path:
        for root, _, files in os.walk(theme_path):
            for ext in (".png", ".svg"):
                if name + ext in files:
                    return os.path.join(root, name + ext)
    return name  # имя из темы — найдёт amane


def text(v):
    return str(v) if v is not None else ""


def refresh(key):
    info = items.get(key)
    if not info:
        return
    try:
        obj = bus.get_object(info["service"], info["path"])
        props = dbus.Interface(obj, "org.freedesktop.DBus.Properties").GetAll(ITEM)
    except Exception:
        return
    status = text(props.get("Status", "Active"))
    icon = ""
    if status == "NeedsAttention":
        icon = theme_icon(text(props.get("IconThemePath")), text(props.get("AttentionIconName"))) or pixmap_file(props.get("AttentionIconPixmap"))
    if not icon:
        icon = theme_icon(text(props.get("IconThemePath")), text(props.get("IconName"))) or pixmap_file(props.get("IconPixmap"))
    tip = props.get("ToolTip")
    tooltip = text(tip[2]) if tip and len(tip) > 2 else ""
    info.update({
        "id": text(props.get("Id")),
        "title": text(props.get("Title")),
        "status": status,
        "icon": icon,
        "menu": text(props.get("Menu")),
        "only_menu": bool(props.get("ItemIsMenu", False)),
        "tooltip": tooltip,
    })
    publish()


def add(service, sender=None):
    # путь вместо имени (libappindicator): служба — тот, кто зарегистрировал
    if service.startswith("/"):
        svc, path = sender or "", service
    else:
        svc, path = service, "/StatusNotifierItem"
    if not svc:
        return
    key = f"{svc}|{path}"
    if key in items:
        return
    items[key] = {"key": key, "service": svc, "path": path, "id": "", "title": "", "status": "Active",
                  "icon": "", "menu": "", "only_menu": False, "tooltip": ""}
    refresh(key)


def remove_owner(name):
    gone = [k for k, v in items.items() if v["service"] == name]
    for k in gone:
        del items[k]
    if gone:
        publish()


class Watcher(dbus.service.Object):
    def __init__(self):
        name = dbus.service.BusName(WATCHER, bus, do_not_queue=True)
        super().__init__(name, "/StatusNotifierWatcher")

    @dbus.service.method(WATCHER, in_signature="s", sender_keyword="sender")
    def RegisterStatusNotifierItem(self, service, sender=None):
        add(str(service), sender)
        self.StatusNotifierItemRegistered(service if not service.startswith("/") else f"{sender}{service}")

    @dbus.service.method(WATCHER, in_signature="s")
    def RegisterStatusNotifierHost(self, service):
        self.StatusNotifierHostRegistered()

    @dbus.service.signal(WATCHER, signature="s")
    def StatusNotifierItemRegistered(self, service):
        pass

    @dbus.service.signal(WATCHER, signature="s")
    def StatusNotifierItemUnregistered(self, service):
        pass

    @dbus.service.signal(WATCHER, signature="")
    def StatusNotifierHostRegistered(self):
        pass

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        return self.GetAll(iface)[prop]

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        regs = [v["service"] if v["path"] == "/StatusNotifierItem" else v["service"] + v["path"] for v in items.values()]
        return {"RegisteredStatusNotifierItems": dbus.Array(regs, signature="s"),
                "IsStatusNotifierHostRegistered": True, "ProtocolVersion": dbus.Int32(0)}


def as_host():
    """другой watcher уже есть: берём его список и следим за сигналами"""
    try:
        w = bus.get_object(WATCHER, "/StatusNotifierWatcher")
        regs = dbus.Interface(w, dbus.PROPERTIES_IFACE).Get(WATCHER, "RegisteredStatusNotifierItems")
    except Exception:
        regs = []
    for r in regs:
        r = str(r)
        if "/" in r and not r.startswith("/"):
            svc, path = r.split("/", 1)
            key = f"{svc}|/{path}"
            if key not in items:
                items[key] = {"key": key, "service": svc, "path": "/" + path, "id": "", "title": "", "status": "Active",
                              "icon": "", "menu": "", "only_menu": False, "tooltip": ""}
                refresh(key)
        else:
            add(r)
    global hosting
    if not hosting:
        hosting = True
        bus.add_signal_receiver(lambda s: GLib.timeout_add(300, lambda: as_host() and False), "StatusNotifierItemRegistered", WATCHER)


def menu_tree(node):
    mid, props, children = node
    p = {str(k): v for k, v in props.items()}
    return {
        "id": int(mid),
        "label": text(p.get("label", "")),
        "enabled": bool(p.get("enabled", True)),
        "visible": bool(p.get("visible", True)),
        "type": text(p.get("type", "standard")),
        "toggle": text(p.get("toggle-type", "")),
        "state": int(p.get("toggle-state", -1)),
        "icon": text(p.get("icon-name", "")),
        "children": [menu_tree(c) for c in children],
    }


def command(c):
    info = next((v for v in items.values() if v["key"] == c.get("key")), None)
    if not info:
        return
    obj = bus.get_object(info["service"], info["path"])
    item = dbus.Interface(obj, ITEM)
    cmd = c.get("cmd")
    try:
        if cmd == "activate":
            item.Activate(0, 0, ignore_reply=True)
        elif cmd == "secondary":
            item.SecondaryActivate(0, 0, ignore_reply=True)
        elif cmd == "scroll":
            item.Scroll(int(c.get("delta", 0)), "vertical", ignore_reply=True)
        elif cmd in ("menu", "event") and info["menu"]:
            m = dbus.Interface(bus.get_object(info["service"], info["menu"]), "com.canonical.dbusmenu")
            if cmd == "event":
                m.Event(int(c["id"]), "clicked", dbus.Int32(0, variant_level=1), dbus.UInt32(0), ignore_reply=True)
                return
            try:
                m.AboutToShow(0)
            except Exception:
                pass
            _, layout = m.GetLayout(0, -1, dbus.Array([], signature="s"))
            emit({"menu": {"key": info["key"], "layout": menu_tree(layout)}})
    except Exception as e:
        emit({"error": str(e)})


def stdin_loop():
    for line in sys.stdin:
        try:
            c = json.loads(line)
        except ValueError:
            continue
        GLib.idle_add(lambda c=c: command(c) and False)
    os._exit(0)


bus.add_signal_receiver(lambda name, old, new: remove_owner(str(name)) if not new else None,
                        "NameOwnerChanged", "org.freedesktop.DBus")
for sig in ("NewIcon", "NewAttentionIcon", "NewTitle", "NewStatus", "NewToolTip", "NewMenu"):
    bus.add_signal_receiver(lambda *a, **kw: on_item_signal(kw), sig, ITEM, sender_keyword="sender", path_keyword="path")


def on_item_signal(kw):
    s, path = kw.get("sender"), kw.get("path")
    for k, v in list(items.items()):
        if v["path"] != path:
            continue
        owner = v["service"]
        if not owner.startswith(":"):
            try:
                owner = bus.get_name_owner(owner)
            except Exception:
                continue
        if owner == s:
            GLib.timeout_add(80, lambda k=k: refresh(k) and False)


try:
    watcher = Watcher()
    # хосты узнают, что мы на месте
    watcher.StatusNotifierHostRegistered()
except dbus.exceptions.NameExistsException:
    as_host()
except Exception:
    as_host()

publish()
threading.Thread(target=stdin_loop, daemon=True).start()
GLib.MainLoop().run()
