import QtQuick
import qs.services

// переключатель вкл/выкл
Item {
    id: sw

    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 44
    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: sw.checked ? Theme.accent : "transparent"
        border.width: sw.checked ? 0 : 1.5
        border.color: area.containsMouse ? Theme.fg : Theme.dim

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Rectangle {
            x: sw.checked ? parent.width - width - 5 : 5
            anchors.verticalCenter: parent.verticalCenter
            width: area.pressed ? 16 : 12
            height: 12
            radius: 6
            color: sw.checked ? Theme.bg : (area.containsMouse ? Theme.fg : Theme.dim)

            Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Theme.animFast } }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled(!sw.checked)
    }
}
