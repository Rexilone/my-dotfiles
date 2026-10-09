pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ночной свет через wlsunset: тёплые цвета экрана вечером
Singleton {
    id: root

    property bool installed: false
    readonly property var cfg: Settings.nightLight ?? {}
    readonly property bool on: cfg.enabled === true

    function toggle() {
        Settings.setNight("enabled", !on);
    }

    function install() {
        Quickshell.execDetached(["pkexec", "pacman", "-S", "--needed", "--noconfirm", "wlsunset"]);
        recheck.restart();
    }

    readonly property var args: {
        const t = Math.round(cfg.temp ?? 4500);
        if (cfg.auto && Weather.configured)
            return ["wlsunset", "-t", String(t), "-T", "6500", "-l", String(Weather.latitude), "-L", String(Weather.longitude)];
        // всегда включено: «ночь» почти весь день
        return ["wlsunset", "-t", String(t), "-T", String(Math.min(6500, t + 1)), "-s", "00:00", "-S", "23:59", "-d", "1"];
    }

    Process {
        id: sunset
        running: root.on && root.installed
        command: root.args
        onCommandChanged: if (running) { running = false; restartTimer.restart(); }
    }

    Timer {
        id: restartTimer
        interval: 200
        onTriggered: sunset.running = root.on && root.installed
    }

    Process {
        id: check
        running: true
        command: ["sh", "-c", "command -v wlsunset"]
        stdout: StdioCollector {
            onStreamFinished: root.installed = text.trim() !== ""
        }
    }

    Timer {
        id: recheck
        interval: 15000
        onTriggered: check.running = true
    }

    IpcHandler {
        target: "nightlight"
        function toggle(): void { root.toggle(); }
    }
}
