import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// снимок, закреплённый поверх окон: тянуть — двигать, колесо — размер, двойной клик или × — закрыть
PanelWindow {
    id: win

    required property var modelData
    required property var ctl

    // большой снимок закрепляется уменьшенным: не больше ~40% экрана, чтобы не закрывать работу
    property real scale: Math.min(1, screen.width * 0.4 / modelData.w, screen.height * 0.4 / modelData.h)
    property real px: modelData.x + (modelData.w - modelData.w * scale) / 2
    property real py: modelData.y + (modelData.h - modelData.h * scale) / 2

    screen: Quickshell.screens.find(s => s.name === modelData.screen) ?? Quickshell.screens[0]
    color: "transparent"
    anchors.top: true
    anchors.left: true
    margins.left: Math.max(0, Math.min(screen.width - implicitWidth, px))
    margins.top: Math.max(0, Math.min(screen.height - implicitHeight, py))
    implicitWidth: Math.max(60, modelData.w * scale)
    implicitHeight: Math.max(40, modelData.h * scale)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-screenshot-pin"

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Theme.surface
        border.width: 2
        border.color: hover.hovered ? Theme.accent : Theme.line

        Image {
            anchors.fill: parent
            anchors.margins: 2
            source: "file://" + win.modelData.path
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point p0
        onPressed: mouse => p0 = Qt.point(mouse.x, mouse.y)
        onPositionChanged: mouse => {
            if (!pressed) return;
            win.px = win.margins.left + mouse.x - p0.x;
            win.py = win.margins.top + mouse.y - p0.y;
        }
        onDoubleClicked: win.ctl.removePin(win.modelData.id)
        onWheel: wheel => win.scale = Math.max(0.2, Math.min(4, win.scale * (wheel.angleDelta.y > 0 ? 1.1 : 1 / 1.1)))
    }

    HoverHandler { id: hover }

    // кнопки при наведении: скопировать, закрыть
    Rectangle {
        visible: hover.hovered
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6
        width: btns.implicitWidth + 8
        height: 42
        radius: 10
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        Row {
            id: btns
            anchors.centerIn: parent
            spacing: 2
            ToolButton {
                icon: 0xF018F
                tip: "Copy"
                onClicked: Quickshell.execDetached(["sh", "-c", 'wl-copy -t image/png < "$1"', "sh", win.modelData.path])
            }
            ToolButton {
                icon: 0xF0156
                tip: "Close"
                onClicked: win.ctl.removePin(win.modelData.id)
            }
        }
    }
}
