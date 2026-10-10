pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Голосовой ввод — Voxtype (служба voxtype.service): Super+H — начать, ещё раз Super+H — закончить,
// распознанный текст печатается в активное окно. Состояние берём у самого Voxtype
// (`voxtype status --follow --format json`), его показывает нижний индикатор (Osd.qml).
Singleton {
    id: root

    property bool available: false
    property string state: "idle"        // idle | recording | transcribing | stopped
    property string text: ""

    function toggle() {
        Quickshell.execDetached(["voxtype", "record", "toggle"]);
    }

    Process {
        id: probe
        running: true
        command: ["sh", "-c", "command -v voxtype >/dev/null && echo yes"]
        stdout: StdioCollector {
            onStreamFinished: root.available = text.includes("yes")
        }
    }

    // поток состояния; если служба перезапустилась — подключаемся заново
    Process {
        id: follow
        running: root.available
        command: ["voxtype", "status", "--follow", "--format", "json"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const m = JSON.parse(line);
                    const s = String(m.class ?? m.alt ?? m.state ?? "idle").toLowerCase();
                    root.state = /record/.test(s) ? "recording" : /transcrib|process/.test(s) ? "transcribing"
                        : /stop|off|error/.test(s) ? "stopped" : "idle";
                    root.text = m.tooltip ?? m.text ?? "";
                } catch (e) {}
            }
        }
        onExited: {
            root.state = "idle";
            if (root.available) retry.restart();
        }
    }
    Timer {
        id: retry
        interval: 5000
        onTriggered: follow.running = true
    }

    // qs ipc call voice toggle
    IpcHandler {
        target: "voice"
        function toggle(): void { root.toggle(); }
        function status(): string { return root.state; }
    }
}
