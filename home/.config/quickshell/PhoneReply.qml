import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.settings

// быстрый ответ на уведомление телефона: «Ответить» в уведомлении на рабочем столе.
// Слой — как у уведомлений телефона: скрывается с демонстрации экрана вместе с ними
PanelWindow {
    id: root

    property var req: null
    readonly property bool show: !!req

    screen: Settings.screenByName(Settings.primary)
    visible: show || hideTimer.running
    color: "transparent"
    anchors.top: true
    margins.top: 60
    implicitWidth: 480
    implicitHeight: card.height + 30
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications-phone"
    WlrLayershell.keyboardFocus: show ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function send() {
        if (field.text.trim()) Rexlink.notifReply(req.key, req.action, field.text, req.device);
        close();
    }
    function close() {
        field.text = "";
        req = null;
        hideTimer.restart();
    }

    Connections {
        target: Rexlink
        function onReplyRequested(d) {
            root.req = d;
            field.text = "";
            field.focusInput();
        }
    }

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
        width: root.width - 20
        height: col.implicitHeight + 32
        radius: 18
        color: Theme.panel
        border.width: 1
        border.color: Theme.surfaceHi2
        opacity: root.show ? 1 : 0
        y: root.show ? 0 : -20

        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        Keys.onEscapePressed: root.close()

        ColumnLayout {
            id: col
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: String.fromCodePoint(0xF045A)
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize + 2
                }
                Text {
                    Layout.fillWidth: true
                    text: `${I18n.tr("Reply")}   ·   ${root.req?.app ?? ""}`
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.req?.title ?? ""
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.req?.text ?? ""
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                SField {
                    id: field
                    multiline: true
                    placeholder: "Reply… (Enter — send, Esc — cancel)"
                    onAccepted: root.send()
                    input.Keys.onEscapePressed: root.close()
                }
                SButton {
                    Layout.alignment: Qt.AlignBottom
                    implicitHeight: 38
                    icon: String.fromCodePoint(0xF048A)
                    primary: true
                    onClicked: root.send()
                }
            }
        }
    }
}
