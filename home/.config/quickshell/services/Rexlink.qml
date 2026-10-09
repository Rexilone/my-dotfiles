pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Rexlink — связь с телефоном, планшетом и часами. Служба — часть системы
// (rexlink.service, код в <дотфайлы>/rexlink), окна у неё нет: весь интерфейс —
// Настройки → Телефон, бар, виджет, карточка звонка.
// API: unix-сокет $XDG_RUNTIME_DIR/rexlink/rexlink.sock, JSON-строки; события после "subscribe"
Singleton {
    id: root

    readonly property string sockPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/rexlink/rexlink.sock`

    property bool installed: false    // служба есть в системе (rexlink.service)
    property bool autostart: false
    readonly property bool connected: sock.connected

    property var devices: []          // [{ id, name, kind, model, online, battery, charging, notifications, current, … }]
    property string current: ""
    readonly property var dev: devices.find(d => d.id === current) ?? null
    readonly property bool online: dev?.online ?? false

    property var status: ({})         // { battery, charging, plug, temp, net, wifi:{ssid,level}, cell:{operator,gen,level} }
    property var caps: []
    property var media: ({})          // { active, title, artist, album, app, playing, pos, len, art }
    property var pcMedia: ({})        // плеер ПК (MPRIS)
    property var call: ({})           // { device, state: ringing|offhook|idle|missed, number, name }
    property var notifs: []
    property var transfers: []
    property var settings: ({})
    property var pairing: ({})        // { id, name, code } — запрос сопряжения
    property var camera: ({})         // { running, starting, owner, device, w, h, error }
    property var clips: []            // история буфера: [{ dir, kind, text|url, time, device }]
    property var screens: ({})        // id -> { running, starting, w, h, source, off, adbPorts, adbNeedPair, … }
    property var frames: ({})         // канал -> { path, w, h, seq } — последний кадр (экран, камера)
    property var sms: ({ threads: [], messages: [], thread: {} })
    property var apk: ({})            // APK для устройств: { versionName, versionCode }

    readonly property bool ringing: call.state === "ringing"
    readonly property var screen: screens[current] ?? ({})

    signal toast(string text)
    signal replyRequested(var data)   // быстрый ответ на уведомление (кнопка в уведомлении)

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

    function kindName(kind) {
        return ({ tablet: "Tablet", watch: "Watch" })[kind] ?? "Phone";
    }

    function batteryIcon(level, charging) {
        const g = c => String.fromCodePoint(c);
        if (charging) return g(0xF0084);
        if (level < 0) return g(0xF0091);
        if (level >= 95) return g(0xF0079);
        if (level < 10) return g(0xF008E);
        return g(0xF007A + Math.floor(level / 10) - 1);
    }

    function wifiIcon(level) {
        return String.fromCodePoint([0xF092F, 0xF091F, 0xF0922, 0xF0925, 0xF0928][Math.max(0, Math.min(4, level ?? 0))]);
    }

    function cellIcon(level) {
        return String.fromCodePoint([0xF08BF, 0xF08BC, 0xF08BD, 0xF08BE, 0xF08BE][Math.max(0, Math.min(4, level ?? 0))]);
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
        cmd("settings", {}, r => {
            if (!r) return;
            root.settings = r;
            root.syncLang();
        });
        cmd("transfers", {}, r => { if (r) root.transfers = r; });
        cmd("pairing", {}, r => { root.pairing = r ?? {}; });
        cmd("camera", {}, r => { root.camera = r ?? {}; });
        cmd("clipboard_history", {}, r => { root.clips = r ?? []; });
        cmd("pc_media", {}, r => { root.pcMedia = r ?? {}; });
        cmd("apk", {}, r => { root.apk = r ?? {}; });
        cmd("sms_state", {}, r => { if (r) root.sms = r; });
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
        cmd("screen", { device: current }, r => { if (r) root.putScreen(current, r); });
    }

    function putScreen(id, s) {
        const x = Object.assign({}, screens);
        x[id] = s;
        screens = x;
    }

    // ── действия
    function dev_(id) { return id ? { device: id } : {}; }
    function ring(id) { cmd("ring", dev_(id)); }
    function select(id) { cmd("select", { device: id }, () => root.refresh()); }
    function mediaAction(a, id, value) { cmd("media", Object.assign({ action: a, value: value ?? 0 }, dev_(id))); }
    function pcMediaAction(a) { cmd("pc_media", { action: a }); }
    function callAction(a) { cmd("call", { action: a, device: call.device || current }); }
    function dial(number) { cmd("dial", { number }); }
    function notifAction(key, i, id) { cmd("notif_action", Object.assign({ key, action: i }, dev_(id))); }
    function notifReply(key, i, text, id) { cmd("notif_reply", Object.assign({ key, action: i, text }, dev_(id))); }
    function notifDismiss(key, id) {
        if (!id || id === current) notifs = notifs.filter(n => n.key !== key);
        else putDev(id, "notifs", notifsFor(id).filter(n => n.key !== key));
        cmd("notif_dismiss", Object.assign({ key }, dev_(id)));
    }
    function notifDismissAll() {
        notifs = notifs.filter(n => n.clearable === false);
        cmd("notif_dismiss_all");
    }
    function clipboardPull(id) { cmd("clipboard_pull", dev_(id)); }
    function clipboardClear() { cmd("clipboard_clear"); }
    function sendFiles(paths, id) { cmd("send_files", Object.assign({ paths }, dev_(id))); }
    function transferCancel(fid) { cmd("transfer_cancel", { fid }); }
    function transfersClear() { cmd("transfers_clear"); }
    function smsRefresh() { cmd("sms_threads"); }
    function smsOpen(thread) { cmd("sms_open", { thread: thread ?? "" }); }
    function smsSend(address, body) { cmd("sms_send", { address, body }); }
    function cameraStart(id) { cmd("camera_start", dev_(id)); }
    function cameraStop() { cmd("camera_stop"); }
    function cameraToggle(id) { camera.running ? cameraStop() : cameraStart(id); }
    function cameraSwitch(facing) { cmd("camera_switch", { facing }); }
    function screenStart(id) {
        cmd("screen_start", dev_(id));
        show("screen");
    }
    function screenStop(id) { cmd("screen_stop", dev_(id)); }
    function screenOff(off, id) { cmd("screen_off", Object.assign({ off }, dev_(id))); }
    function input(ev) { cmd("input", ev); }
    function key(k) { cmd("input", { kind: "key", key: k }); }
    function adbInfo() { cmd("adb_info"); }
    function adbPair(port, code) { cmd("adb_pair", { port, code }); }
    function adbConnect(port) { cmd("adb_connect", { port }); }
    function updateDevice(id) { cmd("update_device", dev_(id)); }
    function rename(id, name) { cmd("rename", { device: id, name }, () => refresh()); }
    function forget(id) { cmd("forget", { device: id }, () => refresh()); }
    function pairAnswer(accept) { cmd("pair_answer", { device: pairing.id, accept }, () => root.pairing = {}); }
    function set(key, value) { cmd("set", { key, value }); }
    function setDownloadDir(path) { cmd("download_dir", { path }); }

    // смотреть видеоканал ("screen:<id>" | "camera"): пока смотрим, служба присылает кадры
    function watch(channel, on) { cmd("frames", { channel, on }); }

    // порты Rexlink в файрволе (ufw): TCP 47820 — связь, UDP 47821 — поиск
    function openFirewall() {
        fwProc.running = true;
    }
    Process {
        id: fwProc
        command: ["pkexec", "sh", "-c", "ufw allow 47820/tcp comment Rexlink && ufw allow 47821/udp comment Rexlink"]
        onExited: root.cmd("firewall_check", {}, () => root.cmd("settings", {}, r => { if (r) root.settings = r; }))
    }

    // виртуальная камера: модуль v4l2loopback с устройством «Rexlink Camera» (/dev/video42), сразу и после перезагрузки.
    // Файлы настроек модуля — в <дотфайлы>/rexlink/system (путь — по ссылке ~/.local/bin/rexlink)
    function setupWebcam() {
        camProc.running = true;
    }
    Process {
        id: camProc
        command: ["sh", "-c", 'd="$(dirname "$(readlink -f "$HOME/.local/bin/rexlink")")/../../../rexlink/system"; '
            + 'exec pkexec sh -c \'install -Dm644 "$1/rexlink-v4l2loopback.conf" /etc/modprobe.d/rexlink-v4l2loopback.conf '
            + '&& install -Dm644 "$1/rexlink-modules-load.conf" /etc/modules-load.d/rexlink.conf '
            + '&& { modprobe -r v4l2loopback 2>/dev/null; modprobe v4l2loopback; }\' sh "$(realpath "$d")"']
        onExited: root.cmd("settings", {}, r => { if (r) root.settings = r; })
    }

    // ── форматирование
    function bytes(n) {
        const u = I18n.ru ? ["Б", "КБ", "МБ", "ГБ", "ТБ"] : ["B", "KB", "MB", "GB", "TB"];
        if (!n) return `0 ${u[0]}`;
        let i = 0;
        while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
        return `${n.toFixed(i && n < 10 ? 1 : 0)} ${u[i]}`;
    }

    function duration(ms) {
        if (!ms || ms < 0) return "0:00";
        const s = Math.floor(ms / 1000);
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, ss = s % 60;
        const p = x => String(x).padStart(2, "0");
        return h ? `${h}:${p(m)}:${p(ss)}` : `${m}:${p(ss)}`;
    }

    function ago(ms) {
        if (!ms) return "";
        const d = new Date(ms), now = new Date();
        const min = Math.floor((now - d) / 60000);
        if (min < 1) return I18n.ru ? "сейчас" : "now";
        if (min < 60) return I18n.ru ? `${min} мин` : `${min} min`;
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm");
        const y = new Date(now);
        y.setDate(now.getDate() - 1);
        if (d.toDateString() === y.toDateString()) return I18n.ru ? "вчера" : "yesterday";
        return Qt.locale(I18n.locale).toString(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "dd.MM.yy");
    }

    function initials(s) {
        s = (s || "").trim();
        if (!s) return "?";
        if (/^[+\d\s()-]+$/.test(s)) return "#";
        const parts = s.split(/\s+/);
        return (parts[0][0] + (parts.length > 1 ? parts[1][0] : "")).toUpperCase();
    }

    // «открыть Rexlink» — страница «Телефон» в Настройках (с нужной вкладкой)
    function show(page) {
        const tab = ({ overview: "", pair: "", call: "calls" })[page ?? ""] ?? (page ?? "");
        Ui.phoneTab = tab || "home";
        Ui.openSettings("phone");
    }

    function start() {
        Quickshell.execDetached(["systemctl", "--user", "start", "rexlink.service"]);
        reconnect.restart();
    }

    function restart() {
        Quickshell.execDetached(["systemctl", "--user", "restart", "rexlink.service"]);
        reconnect.restart();
    }

    function setAutostart(on) {
        Quickshell.execDetached(["systemctl", "--user", on ? "enable" : "disable", "rexlink.service"]);
        autostart = on;
    }

    // язык уведомлений службы — как у шелла
    function syncLang() {
        if (connected && settings.name !== undefined && settings.lang !== I18n.lang) set("lang", I18n.lang);
    }
    Connections {
        target: I18n
        function onLangChanged() { root.syncLang(); }
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
        case "devices":
            root.devices = d;
            if (!d.some(x => x.id === root.current)) root.current = d.find(x => x.current)?.id ?? "";
            break;
        case "status":
            if (d.device === current) root.status = d;
            else root.putDev(d.device, "status", d);
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
        case "pc_media":
            root.pcMedia = d;
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
        case "transfers":
            root.transfers = d;
            break;
        case "camera":
        case "camera_state":
            root.camera = d;
            break;
        case "screen_state":
            root.screens = d;
            break;
        case "frame": {
            const f = Object.assign({}, frames);
            f[d.channel] = d;
            root.frames = f;
            break;
        }
        case "clips":
            root.clips = d;
            break;
        case "settings":
            root.settings = d;
            root.syncLang();
            break;
        case "sms_state":
            if (d.device === current) root.sms = d;
            break;
        case "sms_threads":
            if (d.device === current) root.sms = Object.assign({}, sms, { threads: d.threads });
            break;
        case "sms_messages":
            if (d.device === current && String(d.thread) === String(sms.thread?.id))
                root.sms = Object.assign({}, sms, { messages: d.messages });
            break;
        case "update":
            cmd("devices", {}, r => { if (r) root.devices = r; });
            break;
        case "toast":
            root.toast(d.text ?? "");
            break;
        case "reply_request":
            root.replyRequested(d);
            break;
        case "show":
            // нажали «Открыть» в уведомлении телефона; запросы сопряжения и звонки показывает сам шелл
            if (d.page && d.page !== "pair" && d.page !== "call") root.show(d.page);
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
                root.screens = {};
                root.frames = {};
                reconnect.restart();
            }
        }
        parser: SplitParser {
            onRead: line => root.handle(line)
        }
    }

    // переподключение, если службу перезапустили
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

    function detect() {
        detectProc.running = true;
    }
    Process {
        id: detectProc
        running: true
        command: ["sh", "-c", "{ systemctl --user cat rexlink.service || [ -S \"$XDG_RUNTIME_DIR/rexlink/rexlink.sock\" ]; } >/dev/null 2>&1 && echo yes; systemctl --user is-enabled rexlink.service 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.installed = text.includes("yes");
                root.autostart = text.includes("enabled");
            }
        }
    }

    // qs ipc call rexlink open [overview|notifications|messages|calls|files|clipboard|camera|screen|settings]
    IpcHandler {
        target: "rexlink"
        function open(page: string): void { root.show(page); }
        function ring(): void { root.ring(""); }
    }
}
