import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.settings

// входящий звонок с телефона (Rexlink): карточка сверху с кнопками
PanelWindow {
    id: root

    readonly property bool show: Rexlink.ringing && Settings.moduleOn("phoneCalls", true)

    screen: Settings.screenByName(Settings.primary)
    visible: show || hideTimer.running
    color: "transparent"
    anchors.top: true
    margins.top: 10
    implicitWidth: 440
    implicitHeight: card.height + 30
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-call"

    onShowChanged: if (!show) hideTimer.restart()

    Timer {
        id: hideTimer
        interval: 300
    }

    RectangularShadow {
        anchors.fill: card
        radius: card.radius
        blur: 30
        offset.y: 8
        color: "#80000000"
        opacity: card.opacity
    }

    Rectangle {
        id: card
        x: 10
        width: parent.width - 20
        height: col.implicitHeight + 32
        radius: 20
        color: Theme.panel
        border.width: 1
        border.color: Theme.warn
        opacity: root.show ? 1 : 0
        y: root.show ? 0 : -20

        Behavior on opacity { NumberAnimation { duration: 220 } }
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: col
            x: 18
            y: 16
            width: parent.width - 36
            spacing: 14

            RowLayout {
                spacing: 14

                Rectangle {
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: 24
                    color: Theme.warn

                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xF03F2)
                        color: Theme.bg
                        font.family: Theme.font
                        font.pixelSize: 22
                    }

                    SequentialAnimation on scale {
                        running: root.show
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.12; duration: 500; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: Rexlink.call.name || Rexlink.call.number || "Unknown"
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 4
                        font.bold: true
                    }
                    Text {
                        text: `${I18n.tr("Incoming call")}${Rexlink.call.name && Rexlink.call.number ? " · " + Rexlink.call.number : ""} · ${Rexlink.dev?.name ?? I18n.tr("phone")}`
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                SButton {
                    Layout.fillWidth: true
                    text: I18n.tr("Silence")
                    icon: Icons.volMute
                    onClicked: Rexlink.callAction("silence")
                }
                SButton {
                    Layout.fillWidth: true
                    text: I18n.tr("Decline")
                    icon: String.fromCodePoint(0xF03F4)
                    danger: true
                    onClicked: Rexlink.callAction("reject")
                }
                SButton {
                    Layout.fillWidth: true
                    text: I18n.tr("Answer")
                    icon: String.fromCodePoint(0xF03F2)
                    primary: true
                    onClicked: Rexlink.callAction("accept")
                }
            }
        }
    }
}
