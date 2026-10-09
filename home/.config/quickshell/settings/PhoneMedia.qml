import QtQuick
import QtQuick.Layouts
import qs.services

// плеер: обложка, название, позиция, кнопки (телефон — с перемоткой, ПК — без)
Rectangle {
    id: card

    required property var m
    property string source: ""
    property bool seekable: true
    signal command(string cmd, real value)

    // позиция идёт сама, пока играет: m.at — когда пришло состояние
    property real now: Date.now()
    readonly property real pos: !m.len ? 0 : Math.min(m.len, (m.pos ?? 0) + (m.playing && m.at ? now - m.at : 0))

    Timer {
        interval: 1000
        repeat: true
        running: card.visible && !!card.m.playing
        onTriggered: card.now = Date.now()
    }

    Layout.fillWidth: true
    implicitHeight: 96
    radius: 10
    color: Theme.surface

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 16

        Rectangle {
            Layout.preferredWidth: 68
            Layout.preferredHeight: 68
            radius: 8
            color: Theme.surfaceHi
            clip: true

            Image {
                anchors.fill: parent
                visible: !!card.m.art
                source: card.m.art ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 136
            }
            Text {
                anchors.centerIn: parent
                visible: !card.m.art
                text: String.fromCodePoint(0xF075A)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 26
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            Text {
                text: I18n.tr(card.source) + (card.m.app ? `   ·   ${card.m.app}` : "")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
            Text {
                Layout.fillWidth: true
                text: card.m.title || I18n.tr("Nothing playing")
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: [card.m.artist, card.m.album].filter(s => s).join(" — ")
                elide: Text.ElideRight
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }

            // позиция
            RowLayout {
                Layout.fillWidth: true
                visible: card.seekable && (card.m.len ?? 0) > 0
                spacing: 8

                Text {
                    text: Rexlink.duration(card.pos)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 4
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Theme.surfaceHi2

                    Rectangle {
                        width: parent.width * (card.m.len ? card.pos / card.m.len : 0)
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => card.command("seek", Math.round(card.m.len * Math.max(0, Math.min(1, (mouse.x - 6) / (width - 12)))))
                    }
                }
                Text {
                    text: Rexlink.duration(card.m.len)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 4
                }
            }
        }

        Row {
            spacing: 6
            SButton { icon: String.fromCodePoint(0xF04AE); onClicked: card.command("prev", 0) }
            SButton {
                icon: String.fromCodePoint(card.m.playing ? 0xF03E4 : 0xF040A)
                primary: true
                onClicked: card.command("toggle", 0)
            }
            SButton { icon: String.fromCodePoint(0xF04AD); onClicked: card.command("next", 0) }
        }
    }
}
