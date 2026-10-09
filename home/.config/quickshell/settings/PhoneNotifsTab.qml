import QtQuick
import QtQuick.Layouts
import qs.services

// Телефон → Уведомления: все уведомления выбранного устройства с действиями и ответом
ColumnLayout {
    Layout.fillWidth: true
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: !Rexlink.online ? I18n.tr("The device is not connected")
                : Rexlink.notifs.length ? `${Rexlink.notifs.length} ${I18n.plural(Rexlink.notifs.length, "notification", "notifications", "уведомление", "уведомления", "уведомлений")}   ·   ${Rexlink.dev?.name ?? ""}`
                : ""
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
        SButton {
            visible: Rexlink.notifs.some(n => n.clearable !== false)
            text: "Clear all"
            icon: Icons.trash
            onClicked: Rexlink.notifDismissAll()
        }
    }

    PhoneEmpty {
        visible: Rexlink.notifs.length === 0
        icon: String.fromCodePoint(0xF009B)
        text: "No notifications"
        hint: "The Rexlink app on the device needs notification access"
    }

    Repeater {
        model: Rexlink.notifs
        PhoneNotif {
            required property var modelData
            n: modelData
        }
    }

    SCard {
        Layout.topMargin: 10
        icon: String.fromCodePoint(0xF0379)
        title: "Show them on the desktop"
        desc: "As regular pop-up notifications, with actions and quick reply"

        SSwitch {
            checked: Rexlink.settings.mirrorToDesktop ?? true
            onToggled: v => Rexlink.set("mirrorToDesktop", v)
        }
    }
}
