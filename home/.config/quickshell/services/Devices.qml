pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// подключённые устройства ввода (scripts/input-devices.py): клавиатуры, мыши, тачпады,
// графические планшеты, геймпады. Опрашивается, пока кто-то смотрит (need(true)).
Singleton {
    id: root

    property var list: []   // [{ id, name, kind, bus, wireless, battery, js, widthMm, heightMm, … }]
    property int users: 0

    readonly property var keyboards: list.filter(d => d.kind === "keyboard")
    readonly property var mice: list.filter(d => d.kind === "mouse")
    readonly property var touchpads: list.filter(d => d.kind === "touchpad")
    readonly property var tablets: list.filter(d => d.kind === "tablet")
    readonly property var gamepads: list.filter(d => d.kind === "gamepad")

    function need(on) {
        users = Math.max(0, users + (on ? 1 : -1));
        if (on) refresh();
    }

    function refresh() {
        if (!proc.running) proc.running = true;
    }

    function kindIcon(kind) {
        return String.fromCodePoint({
            keyboard: 0xF030C, mouse: 0xF037D, touchpad: 0xF0741, tablet: 0xF03EB, gamepad: 0xF0EB5, printer: 0xF042A,
        }[kind] ?? 0xF0335);
    }

    function busLabel(d) {
        if (d.bus === "bluetooth") return "Bluetooth";
        if (d.wireless) return "Wireless receiver";
        return { usb: "USB", ps2: "Built-in", i2c: "Built-in", builtin: "Built-in" }[d.bus] ?? "Connected";
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.users > 0
        onTriggered: root.refresh()
    }

    Process {
        id: proc
        command: ["python3", Quickshell.shellPath("scripts/input-devices.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const next = JSON.parse(text);
                    if (JSON.stringify(next) !== JSON.stringify(root.list)) root.list = next;
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: refresh()
}
