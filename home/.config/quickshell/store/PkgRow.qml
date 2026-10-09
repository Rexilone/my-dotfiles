import QtQuick
import QtQuick.Layouts
import qs.services
import qs.settings

// строка пакета в списке (поиск по пакетам, установленное, обновления)
Rectangle {
    id: row

    property string pkg: ""
    property string title: Store.displayName(pkg)
    property string subtitle: ""
    property string badge: ""          // core / extra / aur …
    property string meta: ""           // справа: версия, размер
    property bool aur: false
    property bool showAction: true
    default property alias extra: slot.data
    signal open(string pkg, bool aur)

    Layout.fillWidth: true
    implicitHeight: 62
    radius: 10
    color: area.containsMouse ? Theme.surfaceHi : Theme.surface

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.open(row.pkg, row.aur)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 12
        spacing: 14

        StoreIcon {
            pkg: row.pkg
            size: 36
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            // название и метка репозитория — одной строкой
            Text {
                Layout.fillWidth: true
                text: row.badge === "" ? row.title
                    : `${row.title}&nbsp;&nbsp;<font color="${row.badge === "aur" ? Theme.warn : Theme.dim}" size="1">${row.badge}</font>`
                textFormat: row.badge === "" ? Text.PlainText : Text.StyledText
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: row.subtitle
                elide: Text.ElideRight
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
        }
        Text {
            visible: row.meta !== ""
            text: row.meta
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
        Row {
            id: slot
            spacing: 6
        }
        ActionButton {
            visible: row.showAction
            pkg: row.pkg
            aur: row.aur
        }
    }
}
