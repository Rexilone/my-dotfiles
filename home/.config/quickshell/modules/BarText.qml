import QtQuick
import qs.services

// текст/иконка с hover-эффектом и кликами
Text {
    id: root

    property bool active: true
    signal clicked(var mouse)
    signal wheel(var wheel)

    color: area.containsMouse ? Theme.fg : (active ? Theme.fg : Theme.dim)
    opacity: area.containsMouse || active ? 1 : 0.9
    font.family: Theme.font
    font.pixelSize: Theme.fontSize
    verticalAlignment: Text.AlignVCenter

    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => root.clicked(mouse)
        onWheel: wheel => root.wheel(wheel)
    }
}
