import QtQuick
import QtQuick.Effects
import qs.services

// оформление виджета: с фоном (карточка) или без (текст с тенью поверх обоев)
Item {
    id: root

    property bool background: true
    property int padding: 20
    default property alias content: body.data

    implicitWidth: body.implicitWidth + (background ? padding * 2 : 0)
    implicitHeight: body.implicitHeight + (background ? padding * 2 : 0)

    Rectangle {
        anchors.fill: parent
        visible: root.background
        radius: 20
        color: Theme.panel
        border.width: 1
        border.color: Qt.rgba(Theme.line.r, Theme.line.g, Theme.line.b, 0.5)
    }

    Item {
        id: body
        x: root.background ? root.padding : 0
        y: root.background ? root.padding : 0
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        width: implicitWidth
        height: implicitHeight

        // без фона — мягкая тень, чтобы текст читался на любых обоях
        layer.enabled: !root.background
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#cc000000"
            shadowBlur: 0.6
            shadowVerticalOffset: 2
        }
    }
}
