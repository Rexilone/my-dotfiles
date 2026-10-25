import QtQuick
import qs.services

// переключатель Adwaita
Rectangle {
    id: sw

    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 46
    implicitHeight: 26
    radius: height / 2
    color: checked ? Theme.accent : area.containsMouse ? FStyle.alpha(Theme.fg, 0.22) : FStyle.alpha(Theme.fg, 0.16)
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Rectangle {
        width: parent.height - 6
        height: width
        radius: width / 2
        y: 3
        x: sw.checked ? sw.width - width - 3 : 3
        // светлый акцент (тема под обои) — тёмная ручка, иначе её не видно
        color: sw.checked && (0.299 * Theme.accent.r + 0.587 * Theme.accent.g + 0.114 * Theme.accent.b) > 0.7 ? Theme.bg : "#fafafa"
        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { Sounds.toggle(!sw.checked); sw.toggled(!sw.checked); }
    }
}
