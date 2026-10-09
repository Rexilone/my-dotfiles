pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// простой компьютера: блокировка, выключение экранов, сон (Настройки → Электропитание)
// «Не засыпать» (caffeine) отключает все таймеры
Singleton {
    id: root

    property bool caffeine: false
    readonly property var cfg: Settings.power ?? {}

    function lock() {
        Quickshell.execDetached(["sh", "-c", "pgrep -x swaylock >/dev/null || swaylock -f -c 151515"]);
    }

    function suspend() {
        Quickshell.execDetached(["sh", "-c", root.cfg.lockOnSuspend
            ? "pgrep -x swaylock >/dev/null || swaylock -f -c 151515; sleep 0.5; systemctl suspend"
            : "systemctl suspend"]);
    }

    IdleMonitor {
        enabled: !root.caffeine && (root.cfg.lock ?? 0) > 0
        timeout: Math.max(1, root.cfg.lock ?? 0) * 60
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.lock()
    }

    IdleMonitor {
        enabled: !root.caffeine && (root.cfg.screenOff ?? 0) > 0
        timeout: Math.max(1, root.cfg.screenOff ?? 0) * 60
        respectInhibitors: true
        // экраны включатся сами при движении мыши или нажатии клавиши
        onIsIdleChanged: if (isIdle) Quickshell.execDetached(["niri", "msg", "action", "power-off-monitors"])
    }

    IdleMonitor {
        enabled: !root.caffeine && (root.cfg.suspend ?? 0) > 0
        timeout: Math.max(1, root.cfg.suspend ?? 0) * 60
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.suspend()
    }

    IpcHandler {
        target: "idle"

        // qs ipc call idle caffeine
        function caffeine(): void { root.caffeine = !root.caffeine; }
        function lock(): void { root.lock(); }
    }
}
