import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

Page {
    title: "Notifications"
    subtitle: "Pop-ups and Do not disturb"

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: Notifs.dnd ? Icons.bellOff : Icons.bell
            title: "Do not disturb"
            desc: "Hide pop-ups; critical notifications and reminders still show"

            SSwitch {
                checked: Notifs.dnd
                onToggled: Notifs.toggleDnd()
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF051B)
            title: "Pop-up duration"
            desc: "When the app doesn't set its own"

            SSlider {
                from: 2
                to: 15
                step: 1
                value: Settings.popupTimeout
                suffix: " s"
                onMoved: v => Settings.popupTimeout = Math.round(v)
            }
        }

        SCard {
            icon: Icons.trash
            title: "Notification history"
            desc: `${Notifs.list.length} notification${Notifs.list.length === 1 ? "" : "s"}`

            SButton {
                text: I18n.tr("Clear all")
                enabled: Notifs.list.length > 0
                onClicked: Notifs.clearAll()
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF00ED)
            title: "Send a test notification"
            clickable: true
            onClicked: Quickshell.execDetached(["notify-send", "-a", "Settings", "Test notification", "This is how notifications look."])
        }
    }
}
