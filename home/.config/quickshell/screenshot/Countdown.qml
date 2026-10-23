import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// табло таймера перед снимком (Shift+Print); исчезает до самого снимка
PanelWindow {
    id: win

    required property var ctl

    screen: Settings.activeScreen()
    visible: ctl.countdown > 0
    color: "transparent"
    anchors.top: true
    margins.top: 60
    implicitWidth: 150
    implicitHeight: 150
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-screenshot-timer"

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.panel
        border.width: 2
        border.color: Theme.accent

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -8
            text: win.ctl.countdown
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 64
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 26
            text: I18n.tr("Screenshot")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }
}
