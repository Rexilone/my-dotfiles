import QtQuick
import QtQuick.Layouts
import qs.services

// Телефон → Звонки: текущий звонок и набор номера
ColumnLayout {
    Layout.fillWidth: true
    spacing: 6

    readonly property var c: Rexlink.call

    SCard {
        icon: String.fromCodePoint(0xF03F2)
        title: c.state === "ringing" ? `${I18n.tr("Incoming")}: ${c.name || c.number}`
            : c.state === "offhook" ? `${I18n.tr("Call")}${c.number ? ": " + (c.name || c.number) : ""}`
            : "No active calls"
        desc: c.state === "ringing" && c.name ? c.number ?? "" : "Talk on the phone or a connected headset"

        SButton { visible: c.state === "ringing"; text: "Silence"; onClicked: Rexlink.callAction("silence") }
        SButton {
            visible: c.state === "ringing" || c.state === "offhook"
            text: c.state === "ringing" ? "Decline" : "Hang up"
            danger: true
            onClicked: Rexlink.callAction("reject")
        }
        SButton { visible: c.state === "ringing"; text: "Answer"; primary: true; onClicked: Rexlink.callAction("accept") }
    }

    SSection { text: I18n.tr("Dial a number") }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        SField {
            id: number
            icon: String.fromCodePoint(0xF03F2)
            placeholder: "+7 900 000-00-00"
            onAccepted: callBtn.clicked()
        }
        SButton {
            id: callBtn
            text: "Dial"
            icon: String.fromCodePoint(0xF03F2)
            primary: true
            enabled: Rexlink.online && number.text.trim() !== ""
            onClicked: Rexlink.dial(number.text.trim())
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        wrapMode: Text.Wrap
        text: I18n.tr("The call starts on the phone. Answering and declining need the Phone permission in the app on the phone.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }

    SSection { text: I18n.tr("Notifications") }

    SCard {
        icon: String.fromCodePoint(0xF03F2)
        title: "Incoming call card"
        desc: "Answer or decline calls from the desktop"
        SSwitch {
            checked: Settings.moduleOn("phoneCalls", true)
            onToggled: v => Settings.setModule("phoneCalls", v)
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF009A)
        title: "Calls"
        desc: "Notifications about incoming and missed calls"
        SSwitch {
            checked: Rexlink.settings.calls ?? true
            onToggled: v => Rexlink.set("calls", v)
        }
    }
}
