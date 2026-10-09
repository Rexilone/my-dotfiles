import QtQuick
import QtQuick.Layouts
import qs.services

// заметки и напоминания на сегодня
ColumnLayout {
    id: root

    readonly property var today: Notes.notes ? Notes.list(new Date()) : []

    width: 280
    spacing: 8

    Text {
        text: `${String.fromCodePoint(0xF00ED)}  ${I18n.tr("Today")}`
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize + 1
        font.bold: true
    }

    Text {
        visible: root.today.length === 0
        text: I18n.tr("No notes for today")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    Repeater {
        model: root.today

        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: parent.modelData.time || "•"
                color: parent.modelData.time ? Theme.accent : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                text: parent.modelData.text
                wrapMode: Text.Wrap
                color: parent.modelData.time && parent.modelData.notified ? Theme.dim : Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }
}
