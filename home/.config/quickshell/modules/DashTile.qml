import QtQuick
import qs.services

// плитка дашборда: тёмный скруглённый фон с отступами
Rectangle {
    id: root

    default property alias content: body.data
    property int padding: 16

    implicitWidth: body.implicitWidth + padding * 2
    implicitHeight: body.implicitHeight + padding * 2
    radius: 16
    color: Theme.surface

    Item {
        id: body
        x: root.padding
        y: root.padding
        width: root.width - root.padding * 2
        height: root.height - root.padding * 2
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
