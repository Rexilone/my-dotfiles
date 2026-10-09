import QtQuick
import QtQuick.Layouts
import qs.services

// заголовок меню бара: иконка, название, подпись, действия справа и шестерёнка в настройки
RowLayout {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string settingsPage: ""
    default property alias actions: slot.data

    Layout.fillWidth: true
    spacing: 12

    Rectangle {
        visible: root.icon !== ""
        implicitWidth: 36
        implicitHeight: 36
        radius: 11
        color: Theme.surfaceHi

        Glyph {
            anchors.centerIn: parent
            text: root.icon
            color: Theme.accent
            pixelSize: Theme.iconSize + 2
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        Text {
            Layout.fillWidth: true
            text: I18n.tr(root.title)
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
        }
        Text {
            Layout.fillWidth: true
            visible: root.subtitle !== ""
            text: I18n.tr(root.subtitle)
            elide: Text.ElideRight
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }

    Row {
        id: slot
        Layout.alignment: Qt.AlignVCenter
        spacing: 6
    }

    // в настройки
    Rectangle {
        visible: root.settingsPage !== ""
        implicitWidth: 32
        implicitHeight: 32
        radius: 10
        color: gear.containsMouse ? Theme.surfaceHi2 : Theme.surfaceHi

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Glyph {
            anchors.centerIn: parent
            text: String.fromCodePoint(0xF0493)
            rotation: gear.containsMouse ? 60 : 0
            color: gear.containsMouse ? Theme.fg : Theme.dim

            Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: gear
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Ui.openSettings(root.settingsPage)
        }
    }
}
