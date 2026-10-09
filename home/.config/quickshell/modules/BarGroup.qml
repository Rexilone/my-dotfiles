import QtQuick
import qs.services

// группа модулей бара; в стиле «пилюли» — на своей плашке
Item {
    id: root

    default property alias content: row.data
    property int spacing: Theme.spacing
    readonly property bool pill: Settings.barStyle === "pills"
    readonly property int pad: pill ? 14 : 0

    implicitWidth: row.implicitWidth + pad * 2
    implicitHeight: parent ? parent.height : Theme.barHeight

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        visible: root.pill
        radius: height / 2
        color: Theme.panel
        border.width: 1
        border.color: Theme.surfaceHi2
    }

    Row {
        id: row
        x: root.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.spacing
    }
}
