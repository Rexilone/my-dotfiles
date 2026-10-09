import QtQuick
import qs.services

// сегменты: [{ value, label }]
Rectangle {
    id: seg

    property var options: []
    property var current
    signal picked(var value)

    implicitWidth: segRow.implicitWidth + 6
    implicitHeight: 34
    radius: 9
    color: Theme.surfaceHi
    border.width: 1
    border.color: Theme.surfaceHi2

    Rectangle {
        id: hl
        property Item target: null
        x: target ? target.x + 3 : 3
        y: 3
        width: target ? target.width : 0
        height: parent.height - 6
        radius: 7
        color: Theme.accent

        Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
    }

    Row {
        id: segRow
        x: 3
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            model: seg.options

            Item {
                id: opt
                required property var modelData
                readonly property bool selected: JSON.stringify(seg.current) === JSON.stringify(modelData.value)

                width: optText.implicitWidth + 24
                height: 28
                onSelectedChanged: if (selected) hl.target = opt
                Component.onCompleted: if (selected) hl.target = opt

                Text {
                    id: optText
                    anchors.centerIn: parent
                    text: I18n.tr(opt.modelData.label)
                    color: opt.selected ? Theme.bg : optArea.containsMouse ? Theme.fg : Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: opt.selected
                }

                MouseArea {
                    id: optArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(opt.modelData.value)
                }
            }
        }
    }
}
