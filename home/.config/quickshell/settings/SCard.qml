import QtQuick
import QtQuick.Layouts
import qs.services

// строка настройки: иконка, название, описание, справа — элемент управления
Rectangle {
    id: card

    property string icon: ""
    property string title: ""
    property string desc: ""
    property bool clickable: false
    default property alias control: slot.data
    signal clicked

    Layout.fillWidth: true
    implicitHeight: Math.max(64, row.implicitHeight + 26)
    radius: 10
    color: clickable && area.containsMouse ? Theme.surfaceHi : Theme.surface

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: card.clickable
        hoverEnabled: true
        cursorShape: card.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: card.clicked()
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 16
        spacing: 16

        Text {
            visible: card.icon !== ""
            Layout.preferredWidth: 22
            horizontalAlignment: Text.AlignHCenter
            text: card.icon
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.iconSize + 3
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: I18n.tr(card.title)
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
            Text {
                Layout.fillWidth: true
                visible: card.desc !== ""
                text: I18n.tr(card.desc)
                wrapMode: Text.Wrap
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }

        Row {
            id: slot
            Layout.alignment: Qt.AlignVCenter
            spacing: 8
        }

        Text {
            visible: card.clickable
            text: "›"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.iconSize + 4
        }
    }
}
