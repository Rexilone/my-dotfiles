import QtQuick
import qs.services

// воркспейсы: точки или цифры (Настройки → Бар); активный индикатор «перетекает» между ними
Item {
    id: root

    required property string output

    readonly property var list: Niri.workspaces.filter(ws => ws.output === output)
    readonly property int activeIndex: list.findIndex(ws => ws.is_active)

    readonly property bool numbers: Settings.workspaceStyle === "numbers"
    readonly property int dot: numbers ? 18 : 8
    readonly property int wide: numbers ? 26 : 22
    readonly property int gap: numbers ? 4 : 6

    function slotX(i) {
        return i * (dot + gap) + (activeIndex >= 0 && i > activeIndex ? wide - dot : 0);
    }

    implicitWidth: list.length ? (list.length - 1) * (dot + gap) + wide : 0
    implicitHeight: dot

    Repeater {
        model: root.list

        Rectangle {
            required property var modelData
            required property int index
            readonly property bool occupied: modelData.active_window_id !== null

            x: root.slotX(index)
            width: index === root.activeIndex ? root.wide : root.dot
            height: root.dot
            radius: root.numbers ? 6 : height / 2
            color: root.numbers
                ? (modelData.is_urgent ? Theme.urgent : area.containsMouse ? Theme.surfaceHi2 : "transparent")
                : (modelData.is_urgent ? Theme.urgent : area.containsMouse ? Theme.fg : occupied ? Theme.dim : Theme.faint)

            Text {
                anchors.centerIn: parent
                visible: root.numbers
                text: parent.modelData.idx
                color: parent.index === root.activeIndex ? Theme.bg : parent.occupied ? Theme.fg : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
                font.bold: parent.index === root.activeIndex
                z: 2
            }

            Behavior on x { NumberAnimation { duration: Theme.animSlow + 80; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Theme.animSlow + 80; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -3
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Niri.focusWorkspace(parent.modelData)
            }
        }
    }

    // индикатор: передний край движется быстрее заднего — эффект «гусеницы»
    Rectangle {
        id: indicator

        property real lo: 0
        property real hi: 0
        property bool forward: true
        property bool ready: false

        readonly property real target: root.activeIndex * (root.dot + root.gap)

        function moveTo(t) {
            if (root.activeIndex < 0) return;
            forward = t >= lo;
            lo = t;
            hi = t + root.wide;
            ready = true;  // первую позицию ставим без анимации
        }

        onTargetChanged: moveTo(target)
        Component.onCompleted: moveTo(target)

        visible: root.activeIndex >= 0
        x: lo
        width: hi - lo
        height: root.dot
        radius: root.numbers ? 6 : height / 2
        color: Theme.accent
        z: root.numbers ? -1 : 1

        Behavior on lo {
            enabled: indicator.ready
            NumberAnimation { duration: indicator.forward ? 380 : 200; easing.type: Easing.OutCubic }
        }
        Behavior on hi {
            enabled: indicator.ready
            NumberAnimation { duration: indicator.forward ? 200 : 380; easing.type: Easing.OutCubic }
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: ev => Niri.action([ev.angleDelta.y > 0 ? "focus-workspace-up" : "focus-workspace-down"])
    }
}
