import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.services
import qs.settings

// список уведомлений + «Не беспокоить» + очистка
ColumnLayout {
    id: root

    width: 380
    spacing: 10

    MenuHeader {
        icon: Notifs.dnd ? Icons.bellOff : Icons.bell
        title: "Notifications"
        subtitle: Notifs.list.length ? `${Notifs.list.length} unread` : "All caught up"
        settingsPage: "notifications"

        SButton {
            visible: Notifs.list.length > 0
            text: I18n.tr("Clear")
            implicitHeight: 32
            onClicked: Notifs.clearAll()
        }
    }

    // «Не беспокоить»
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 48
        radius: 12
        color: Theme.surface

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 10

            Text {
                text: Icons.bellOff
                color: Notifs.dnd ? Theme.accent : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.iconSize
            }
            Text {
                Layout.fillWidth: true
                text: I18n.tr("Do not disturb")
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            SSwitch {
                checked: Notifs.dnd
                onToggled: Notifs.toggleDnd()
            }
        }
    }

    Text {
        visible: Notifs.list.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 12
        Layout.bottomMargin: 12
        horizontalAlignment: Text.AlignHCenter
        text: `${String.fromCodePoint(0xF009A)}\n\n${I18n.tr("No notifications")}`
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
    }

    Flickable {
        visible: Notifs.list.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(list.implicitHeight, 520)
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: parent.width
            spacing: 6

            Repeater {
                // новые сверху
                model: Notifs.list.slice().reverse()

                NotificationCard {
                    required property Notification modelData
                    width: list.width
                    notif: modelData
                    color: Theme.surface
                    radius: 12
                    onCloseRequested: modelData.dismiss()
                }
            }
        }
    }
}
