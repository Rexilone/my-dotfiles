import QtQuick
import qs.services

// кнопка панели скриншотилки: значок, подсказка с клавишей при наведении, активное состояние
Rectangle {
    id: btn

    property int icon: 0
    property string label: ""         // без значка — кнопка с текстом
    property string tip: ""
    property string key: ""
    property bool active: false
    property bool off: false
    property color iconColor: Theme.fg
    signal clicked

    implicitWidth: label ? row.implicitWidth + 22 : 34
    implicitHeight: 34
    radius: 9
    opacity: off ? 0.4 : 1
    color: active ? Theme.accent : area.containsMouse && !off ? Theme.surfaceHi2 : "transparent"

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            visible: btn.icon !== 0
            anchors.verticalCenter: parent.verticalCenter
            text: btn.icon ? String.fromCodePoint(btn.icon) : ""
            color: btn.active ? Theme.bg : btn.iconColor
            font.family: Theme.font
            font.pixelSize: Theme.iconSize + 1
        }
        Text {
            visible: btn.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr(btn.label)
            color: btn.active ? Theme.bg : Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            visible: btn.label !== "" && btn.key !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.key
            color: btn.active ? Theme.bg : Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
    }

    // подсказка над кнопкой
    Rectangle {
        visible: area.containsMouse && btn.tip !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        width: tipText.implicitWidth + 16
        height: 24
        radius: 7
        color: Theme.surfaceHi2
        border.width: 1
        border.color: Theme.line
        z: 10

        Text {
            id: tipText
            anchors.centerIn: parent
            text: I18n.tr(btn.tip) + (btn.key ? "   " + btn.key : "")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.off ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: if (!btn.off) btn.clicked()
    }
}
