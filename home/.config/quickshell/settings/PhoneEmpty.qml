import QtQuick
import QtQuick.Layouts
import qs.services

// пустой список: иконка, текст, подсказка — по центру
Item {
    id: root

    property string icon: ""
    property string text: ""
    property string hint: ""

    Layout.fillWidth: true
    implicitWidth: 300
    implicitHeight: col.implicitHeight + 48

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        width: Math.min(root.width, 560)
        spacing: 8

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.icon
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 40
        }
        Text {
            Layout.fillWidth: true
            text: I18n.tr(root.text)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
        }
        Text {
            Layout.fillWidth: true
            visible: root.hint !== ""
            text: I18n.tr(root.hint)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }
}
