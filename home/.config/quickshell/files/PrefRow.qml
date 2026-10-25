import QtQuick
import QtQuick.Layouts
import qs.services

// строка настройки Adwaita: заголовок, подсказка, справа — переключатель или кнопка (controls).
// switchable: строка сама переключает (щелчок по всей строке), как AdwSwitchRow
Item {
    id: r

    property string title: ""
    property string subtitle: ""
    property bool sep: true            // линия сверху (у первой строки группы — нет)
    property bool switchable: false
    property bool checked: false
    default property alias controls: trail.data
    signal toggled(bool value)

    Layout.fillWidth: true
    implicitHeight: subtitle ? 62 : 52

    Rectangle {
        visible: r.sep
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: FStyle.sep
    }
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: r.sep ? 1 : 0
        color: r.switchable && area.containsMouse ? FStyle.hover : "transparent"
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: r.switchable
        hoverEnabled: true
        onClicked: r.toggled(!r.checked)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: r.title
                wrapMode: Text.Wrap
                color: Theme.fg
                font.family: FStyle.ui
                font.pixelSize: FStyle.fs
            }
            Text {
                visible: r.subtitle !== ""
                Layout.fillWidth: true
                text: r.subtitle
                wrapMode: Text.Wrap
                color: Theme.dim
                font.family: FStyle.ui
                font.pixelSize: FStyle.fsSmall
            }
        }
        ASwitch {
            visible: r.switchable
            checked: r.checked
            onToggled: v => r.toggled(v)
        }
        Row {
            id: trail
            spacing: 8
        }
    }
}
