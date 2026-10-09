import QtQuick
import qs.services

Rectangle {
    id: btn

    property string text: ""
    property string icon: ""
    property bool primary: false
    property bool danger: false
    signal clicked

    implicitWidth: row.implicitWidth + 28
    implicitHeight: 34
    radius: 8
    opacity: enabled ? 1 : 0.4
    color: primary ? (area.pressed ? Theme.fgPressed : area.containsMouse ? Theme.fgHover : Theme.accent)
                   : (area.pressed ? Theme.line : area.containsMouse ? Theme.surfaceHi2 : Theme.surfaceHi)
    border.width: primary ? 0 : 1
    border.color: Theme.surfaceHi2

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Text {
            visible: btn.icon !== ""
            text: btn.icon
            color: btn.primary ? Theme.bg : btn.danger ? Theme.urgent : Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.iconSize - 1
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: btn.text !== ""
            text: I18n.tr(btn.text)
            color: btn.primary ? Theme.bg : btn.danger ? Theme.urgent : Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            font.bold: btn.primary
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
