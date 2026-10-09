import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services

// уведомление с телефона: иконка приложения, текст, действия, быстрый ответ, смахнуть
Rectangle {
    id: card

    required property var n
    property bool replying: false
    property int replyAction: -1

    function startReply(i) {
        replyAction = i;
        replying = true;
        replyField.focusInput();
    }

    function sendReply() {
        if (replyField.text.trim()) Rexlink.notifReply(n.key, replyAction, replyField.text, n.device);
        replyField.text = "";
        replying = false;
    }

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 28
    radius: 10
    color: Theme.surface

    ColumnLayout {
        id: col
        x: 16
        y: 14
        width: parent.width - 32
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 34
                implicitHeight: 34
                radius: 9
                color: Theme.surfaceHi

                IconImage {
                    anchors.centerIn: parent
                    visible: !!card.n.icon
                    source: card.n.icon ?? ""
                    implicitSize: 22
                }
                Text {
                    anchors.centerIn: parent
                    visible: !card.n.icon
                    text: String.fromCodePoint(0xF009A)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: card.n.app ?? ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                    Text {
                        text: Rexlink.ago(card.n.time)
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                    Item { Layout.fillWidth: true }
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.n.title ?? ""
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.n.text ?? ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            SButton {
                Layout.alignment: Qt.AlignTop
                visible: card.n.clearable !== false
                icon: String.fromCodePoint(0xF0156)
                onClicked: Rexlink.notifDismiss(card.n.key, card.n.device)
            }
        }

        // действия
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 48
            visible: (card.n.actions ?? []).length > 0 && !card.replying
            spacing: 6

            Repeater {
                model: card.n.actions ?? []
                SButton {
                    required property var modelData
                    text: modelData.title
                    icon: modelData.reply ? String.fromCodePoint(0xF045A) : ""
                    onClicked: modelData.reply ? card.startReply(modelData.i) : Rexlink.notifAction(card.n.key, modelData.i, card.n.device)
                }
            }
        }

        // быстрый ответ
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 48
            visible: card.replying
            spacing: 6

            SField {
                id: replyField
                placeholder: "Reply…"
                icon: String.fromCodePoint(0xF045A)
                onAccepted: card.sendReply()
                input.Keys.onEscapePressed: card.replying = false
            }
            SButton {
                icon: String.fromCodePoint(0xF048A)
                primary: true
                onClicked: card.sendReply()
            }
            SButton {
                icon: String.fromCodePoint(0xF0156)
                onClicked: card.replying = false
            }
        }
    }
}
