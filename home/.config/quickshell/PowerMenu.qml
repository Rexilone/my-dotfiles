import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// меню питания: qs ipc call power toggle
// ←/→ или Tab — выбор, Enter — действие, Esc — закрыть, буквы — быстрый выбор
// выход/перезагрузка/выключение требуют повторного нажатия
PanelWindow {
    id: root

    property bool open: false
    property bool shown: false
    property int current: 0
    property int armed: -1  // индекс действия, ждущего подтверждения
    property real uptime: 0  // секунды

    function formatUptime(sec) {
        const d = Math.floor(sec / 86400);
        const h = Math.floor(sec % 86400 / 3600);
        const m = Math.floor(sec % 3600 / 60);
        const u = I18n.ru ? ["д", "ч", "м"] : ["d", "h", "m"];
        return [d ? `${d}${u[0]}` : "", d || h ? `${h}${u[1]}` : "", `${m}${u[2]}`].filter(x => x).join(" ");
    }

    readonly property var actions: [
        { name: "Lock", key: "l", ru: "д", icon: 0xF033E, confirm: false,
          cmd: ["swaylock"] },
        { name: "Suspend", key: "s", ru: "ы", icon: 0xF0904, confirm: false,
          cmd: ["sh", "-c", "swaylock -f && systemctl suspend"] },
        { name: "Logout", key: "e", ru: "у", icon: 0xF0343, confirm: true,
          cmd: ["niri", "msg", "action", "quit", "--skip-confirmation"] },
        { name: "Reboot", key: "r", ru: "к", icon: 0xF0709, confirm: true,
          cmd: ["systemctl", "reboot"] },
        { name: "Shutdown", key: "p", ru: "з", icon: 0xF0425, confirm: true,
          cmd: ["systemctl", "poweroff"] },
    ]

    function activate(i) {
        current = i;
        const a = actions[i];
        if (a.confirm && armed !== i) {
            armed = i;
            return;
        }
        open = false;
        Quickshell.execDetached(a.cmd);
    }

    onOpenChanged: {
        if (open) {
            targetScreen = Settings.activeScreen();
            hideTimer.stop();
            current = 0;
            armed = -1;
            uptimeProc.running = true;
            shown = true;
            keys.forceActiveFocus();
        } else {
            hideTimer.restart();
        }
    }
    onCurrentChanged: if (armed !== current) armed = -1

    IpcHandler {
        target: "power"

        function toggle(): void { root.open = !root.open; }
        function open(): void { root.open = true; }
        function hide(): void { root.open = false; }
    }

    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: root.uptime = parseFloat(text) || 0
        }
    }

    // пока меню открыто, время обновляется
    Timer {
        interval: 30000
        running: root.open
        repeat: true
        onTriggered: uptimeProc.running = true
    }

    Timer {
        id: hideTimer
        interval: Theme.animSlow
        onTriggered: root.shown = false
    }

    // открывается на мониторе, где сейчас курсор/фокус
    property var targetScreen: Settings.activeScreen()
    screen: targetScreen
    visible: shown
    color: "transparent"
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    // размытие только под карточкой (Персонализация → Прозрачность)
    BackgroundEffect.blurRegion: Theme.blurOn ? blurReg : null
    Region {
        id: blurReg
        item: powerCard
        radius: powerCard.radius
    }
    WlrLayershell.namespace: "quickshell-power"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.open ? 0.5 : 0

        Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }
    }

    Item {
        id: keys
        focus: true

        Keys.onPressed: event => {
            const k = event.key;
            const t = event.text.toLowerCase();
            const n = root.actions.length;
            const byKey = root.actions.findIndex(a => t && (a.key === t || a.ru === t));

            if (k === Qt.Key_Escape) root.open = false;
            else if (k === Qt.Key_Right || k === Qt.Key_Tab || k === Qt.Key_Down) root.current = (root.current + 1) % n;
            else if (k === Qt.Key_Left || k === Qt.Key_Backtab || k === Qt.Key_Up) root.current = (root.current + n - 1) % n;
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.activate(root.current);
            else if (byKey >= 0) root.activate(byKey);
            else return;
            event.accepted = true;
        }
    }

    Rectangle {
        id: powerCard
        anchors.centerIn: parent
        width: content.implicitWidth + 32
        height: content.implicitHeight + 32
        radius: Theme.radius + 4
        color: Theme.panel
        border.width: 1
        border.color: Theme.faint

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.94

        Behavior on opacity { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: content
            anchors.centerIn: parent
            spacing: 12

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                text: `${Icons.clock}  ${I18n.tr("up")} ${root.formatUptime(root.uptime)}`
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            RowLayout {
                spacing: 10

                Repeater {
                    model: root.actions

                    Rectangle {
                        id: button

                        required property var modelData
                        required property int index
                        readonly property bool selected: root.current === index
                        readonly property bool isArmed: root.armed === index

                        implicitWidth: 104
                        implicitHeight: 112
                        radius: Theme.radius
                        color: isArmed ? Qt.rgba(Theme.urgent.r, Theme.urgent.g, Theme.urgent.b, 0.18)
                             : selected ? Theme.surfaceHi2
                             : "transparent"
                        border.width: isArmed ? 1 : 0
                        border.color: Theme.urgent

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 10

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: String.fromCodePoint(button.modelData.icon)
                                color: button.isArmed ? Theme.urgent : button.selected ? Theme.fg : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 30

                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: I18n.tr(button.isArmed ? "Confirm?" : button.modelData.name)
                                color: button.isArmed ? Theme.urgent : button.selected ? Theme.fg : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: button.modelData.key.toUpperCase()
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.current = button.index
                            onClicked: root.activate(button.index)
                        }
                    }
                }
            }
        }
    }
}
