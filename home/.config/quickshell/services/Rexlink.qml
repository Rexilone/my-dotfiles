pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Rexlink — связь с телефоном/планшетом (пакет rexlink)
// API: unix-сокет $XDG_RUNTIME_DIR/rexlink/rexlink.sock, JSON-строки; события после "subscribe"
Singleton {
    id: root

    readonly property string sockPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/rexlink/rexlink.sock`

    property bool installed: false
    property bool autostart: false
    readonly property bool connected: sock.connected

    property var devices: []          // [{ id, name, kind, model, online, battery, charging, notifications, current, … }]
    property string current: ""
    readonly property var dev: devices.find(d => d.id === current) ?? null
    readonly property bool online: dev?.online ?? false

    property var status: ({})         // { battery, charging, temp, net, wifi:{ssid,level}, cell:{operator,gen,level} }
    property var caps: []
    property var media: ({})          // { active, title, artist, album, app, playing, pos, len }
    property var call: ({})           // { device, state: ringing|offhook|idle|missed, number, name }
    property var notifs: []
    property var transfers: []
    property var settings: ({})
    property var pairing: ({})        // { id, name, code } — запрос сопряжения
    property var camera: ({})

    readonly property bool ringing: call.state === "ringing"

    // данные по каждому устройству (для виджетов): id -> { status, media, notifs, caps }
    property var byDev: ({})

    function devFor(id) { return devices.find(d => d.id === (id || current)) ?? null; }
    function statusFor(id) { return (id && id !== current) ? (byDev[id]?.status ?? {}) : status; }
    function mediaFor(id) { return (id && id !== current) ? (byDev[id]?.media ?? {}) : media; }
    function notifsFor(id) { return (id && id !== current) ? (byDev[id]?.notifs ?? []) : notifs; }

    function putDev(id, key, value) {
        const b = Object.assign({}, byDev);
        b[id] = Object.assign({}, b[id] ?? {}, { [key]: value });
        byDev = b;
    }

    function kindIcon(kind) {
        return String.fromCodePoint(kind === "tablet" ? 0xF04F7 : kind === "watch" ? 0xF0954 : 0xF011C);
    }

    function batteryIcon(level, charging) {
        const g = c => String.fromCodePoint(c);
        if (charging) return g(0xF0084);
        if (level < 0) return g(0xF0091);
        if (level >= 95) return g(0xF0079);
        if (level < 10) return g(0xF008E);
        return g(0xF007A + Math.floor(level / 10) - 1);
    }

    // ── запросы
    property int seq: 1
    property var pending: ({})

    function cmd(name, params, cb) {
        if (!sock.connected) return;
        const id = seq++;
        if (cb) pending[id] = cb;
        sock.write(JSON.stringify(Object.assign({ id, cmd: name }, params ?? {})) + "\n");
        sock.flush();
    }

    function refresh() {
        cmd("devices", {}, r => {
            if (!r) return;
            root.devices = r;
            for (const d of r) if (d.id !== root.current && d.online) refreshOther(d.id);
        });
        cmd("state", {}, r => {
            if (!r) return;
            root.current = r.current ?? "";
            refreshDevice();
        });
        cmd("settings", {}, r => { if (r) root.settings = r; });
        cmd("transfers", {}, r => { if (r) root.transfers = r; });
        cmd("pairing", {}, r => { root.pairing = r ?? {}; });
        cmd("camera", {}, r => { root.camera = r ?? {}; });
    }

    function refreshOther(id) {
        cmd("device", { device: id }, r => {
            if (!r) return;
            root.putDev(id, "status", r.status ?? {});
            root.putDev(id, "media", r.media ?? {});
        });
        cmd("notifications", { device: id }, r => root.putDev(id, "notifs", r ?? []));
    }

    function refreshDevice() {
        if (!current) return;
        cmd("device", { device: current }, r => {
            if (!r) return;
            root.status = r.status ?? {};
            root.caps = r.caps ?? [];
            root.media = r.media ?? {};
            if ((r.call ?? {}).state) root.call = Object.assign({ device: current }, r.call);
        });
        cmd("notifications", { device: current }, r => { root.notifs = r ?? []; });
    }

    // ── действия
    function ring(id) { cmd("ring", id ? { device: id } : {}); }
    function select(id) { cmd("select", { device: id }, () => root.refresh()); }
    function dev_(id) { return id ? { device: id } : {}; }
    function mediaAction(a, id) { cmd("media", Object.assign({ action: a }, dev_(id))); }
    function callAction(a) { cmd("call", { action: a, device: call.device || current }); }
    function notifAction(key, i) { cmd("notif_action", { key, action: i }); }
    function notifReply(key, i, text) { cmd("notif_reply", { key, action: i, text }); }
    function notifDismiss(key, id) {
        if (!id || id === current) notifs = notifs.filter(n => n.key !== key);
        else putDev(id, "notifs", notifsFor(id).filter(n => n.key !== key));
        cmd("notif_dismiss", Object.assign({ key }, dev_(id)));
    }
    function clipboardPull(id) { cmd("clipboard_pull", dev_(id)); }
    function sendFiles(paths) { cmd("send_files", { paths }); }
    function cameraToggle(id) { cmd(camera.running ? "camera_stop" : "camera_start", dev_(id), () => cmd("camera", {}, r => root.camera = r ?? {})); }
    function screenStart(id) {
        cmd("screen_start", dev_(id));
        show("screen");
    }
    function rename(id, name) { cmd("rename", { device: id, name }, () => refresh()); }
    function forget(id) { cmd("forget", { device: id }, () => refresh()); }
    function pairAnswer(accept) { cmd("pair_answer", { device: pairing.id, accept }, () => root.pairing = {}); }
    function set(key, value) { cmd("set", { key, value }, () => cmd("settings", {}, r => { if (r) root.settings = r; })); }

    // окно приложения Rexlink (если оно запущено с интерфейсом); иначе — запустить
    function show(page) {
        if (connected) cmd("show", { page: page ?? "" }, (r, err) => { if (err) Quickshell.execDetached(["rexlink", "--page", page || "overview"]); });
        else Quickshell.execDetached(["rexlink", "--page", page || "overview"]);
    }

    function start() {
        Quickshell.execDetached(["sh", "-c", "systemctl --user start rexlink.service || setsid -f rexlink --hidden"]);
        reconnect.restart();
    }

    function setAutostart(on) {
        Quickshell.execDetached(["systemctl", "--user", on ? "enable" : "disable", "rexlink.service"]);
        autostart = on;
    }

    // ── события
    function handle(line) {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (m.id !== undefined && pending[m.id]) {
            const cb = pending[m.id];
            delete pending[m.id];
            cb(m.ok ? m.result : null, m.ok ? "" : m.error);
            return;
        }
        const d = m.data ?? {};
        switch (m.event) {
        case "device_connected":
        case "device_disconnected":
            refresh();
            break;
        case "status":
            if (d.device === current) root.status = d;
            else root.putDev(d.device, "status", d);
            cmd("devices", {}, r => { if (r) root.devices = r; });
            break;
        case "notification":
            if (d.device === current) root.notifs = [d].concat(notifs.filter(n => n.key !== d.key));
            else root.putDev(d.device, "notifs", [d].concat(notifsFor(d.device).filter(n => n.key !== d.key)));
            break;
        case "notification_removed":
            if (d.device === current) root.notifs = notifs.filter(n => n.key !== d.key);
            else root.putDev(d.device, "notifs", notifsFor(d.device).filter(n => n.key !== d.key));
            break;
        case "media":
            if (d.device === current) root.media = d;
            else root.putDev(d.device, "media", d);
            break;
        case "call":
            root.call = d;
            break;
        case "pair_request":
            root.pairing = d;
            break;
        case "pair_finished":
            root.pairing = {};
            refresh();
            break;
        case "transfer":
            cmd("transfers", {}, r => { if (r) root.transfers = r; });
            break;
        case "camera":
            root.camera = d;
            break;
        }
    }

    Socket {
        id: sock
        path: root.sockPath
        connected: root.installed
        onConnectedChanged: {
            if (connected) {
                root.cmd("subscribe");
                root.refresh();
            } else {
                root.devices = [];
                root.notifs = [];
                reconnect.restart();
            }
        }
        parser: SplitParser {
            onRead: line => root.handle(line)
        }
    }

    // переподключение, если Rexlink перезапустили
    Timer {
        id: reconnect
        interval: 4000
        repeat: true
        running: root.installed && !sock.connected
        onTriggered: {
            sock.connected = false;
            sock.connected = true;
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v rexlink >/dev/null && echo yes; systemctl --user is-enabled rexlink.service 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.installed = text.includes("yes");
                root.autostart = text.includes("enabled");
            }
        }
    }
}
