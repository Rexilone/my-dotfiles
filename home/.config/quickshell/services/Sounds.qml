pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// звуки системы (assets/sounds, их делает scripts/gen-sounds.py): тихие «токи» и тёплые колокольчики
// в духе Pixel и iOS — щелчки, громкость, уведомления, снимок экрана, флешки, телефон. Настройки → Звук → Звуки системы. Играет pw-play — свой процесс на звук, без постоянного
// потока в PipeWire. Щелчки в игре и при «Не беспокоить» молчат
Singleton {
    id: root

    readonly property var cfg: Settings.sounds ?? {}
    readonly property bool enabled: cfg.enabled ?? true
    readonly property real volume: cfg.volume ?? 0.6
    readonly property string dir: Quickshell.shellPath("assets/sounds")

    // звук → группа в настройках
    readonly property var groups: ({
        click: "clicks", "toggle-on": "clicks", "toggle-off": "clicks",
        volume: "volume",
        notify: "notify", error: "notify",
        shutter: "screenshot", record: "screenshot",
        plug: "devices", unplug: "devices",
        connect: "phone", disconnect: "phone",
    })
    // группы: подпись и включены ли по умолчанию
    readonly property var groupList: [
        { key: "clicks", label: "Clicks", desc: "Buttons and switches", def: true, sample: "toggle-on" },
        { key: "volume", label: "Volume change", desc: "A soft tick on every step", def: true, sample: "volume" },
        { key: "notify", label: "Notifications", desc: "Not for apps with their own sound (Telegram, Discord)", def: true, sample: "notify" },
        { key: "screenshot", label: "Screenshots and recording", desc: "", def: true, sample: "shutter" },
        { key: "devices", label: "Flash drives and disks", desc: "Plugged in and removed", def: true, sample: "plug" },
        { key: "phone", label: "Phone", desc: "Connected and lost", def: true, sample: "connect" },
    ]
    // приложения со своим звуком уведомлений — второй сверху не нужен
    readonly property var ownSound: ["telegram", "discord", "vesktop", "slack", "element", "steam"]

    function groupOn(g) {
        const def = groupList.find(x => x.key === g)?.def ?? true;
        return cfg[g] ?? def;
    }

    property real lastQuiet: 0
    function play(name, force) {
        if (!force && (!enabled || !groupOn(groups[name] ?? ""))) return;
        const quiet = name === "click" || name === "toggle-on" || name === "toggle-off" || name === "volume";
        if (!force && quiet) {
            if (GameMode.active) return;
            const t = Date.now();
            if (t - lastQuiet < 45) return;
            lastQuiet = t;
        }
        // тихие звуки — тише, сигналы — как есть
        const v = Math.max(0, Math.min(1.5, volume * (quiet ? 0.8 : 1)));
        Quickshell.execDetached(["pw-play", "--volume", v.toFixed(2), `${dir}/${name}.wav`]);
    }
    function click() { play("click"); }
    function toggle(on) { play(on ? "toggle-on" : "toggle-off"); }

    // уведомление: не в «Не беспокоить», не для приложений со своим звуком и не если просили без звука
    function notify(n) {
        if (Notifs.dnd || GameMode.quiet) return;
        const h = n.hints ?? {};
        if (h["suppress-sound"] === true || h["suppress-sound"] === 1) return;
        const app = `${n.appName ?? ""} ${n.desktopEntry ?? ""}`.toLowerCase();
        if (ownSound.some(a => app.includes(a))) return;
        play("notify");
    }

    // ── события устройств и телефона
    Connections {
        target: Drives
        function onPlugged() { root.play("plug"); }
        function onUnplugged() { root.play("unplug"); }
    }
    property bool phoneWas: false
    property bool phoneReady: false
    Connections {
        target: Rexlink
        function onOnlineChanged() {
            if (root.phoneReady && Rexlink.online !== root.phoneWas) root.play(Rexlink.online ? "connect" : "disconnect");
            root.phoneWas = Rexlink.online;
        }
    }
    // при запуске шелла телефон подключается сам — это не событие
    Timer {
        running: true
        interval: 8000
        onTriggered: {
            root.phoneWas = Rexlink.online;
            root.phoneReady = true;
        }
    }

    IpcHandler {
        target: "sounds"
        // qs ipc call sounds play notify
        function play(name: string): void { root.play(name, true); }
    }
}
