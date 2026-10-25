import QtQuick
import QtQuick.Layouts
import qs.services

// группа настроек Adwaita: подпись и строки в скруглённой рамке
ColumnLayout {
    id: g

    property string title: ""
    default property alias rows: box.data

    Layout.fillWidth: true
    spacing: 10

    Text {
        visible: g.title !== ""
        text: g.title
        color: Theme.fg
        font.family: FStyle.ui
        font.pixelSize: FStyle.fs
        font.weight: Font.Bold
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: box.implicitHeight
        radius: 12
        color: FStyle.alpha(Theme.fg, 0.05)
        border.width: 1
        border.color: FStyle.sep
        clip: true

        ColumnLayout {
            id: box
            width: parent.width
            spacing: 0
        }
    }
}
