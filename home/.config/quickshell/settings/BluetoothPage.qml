import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.services

// Bluetooth через bluez
Page {
    id: page

    title: "Bluetooth"
    subtitle: "Pair and connect devices"

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? adapter.devices.values.slice().sort((a, b) =>
        (b.connected - a.connected) || (b.paired - a.paired) || (a.name ?? "").localeCompare(b.name ?? "")) : []

    SCard {
        visible: !page.adapter
        icon: String.fromCodePoint(0xF00B2)  // bluetooth-off
        title: "No Bluetooth adapter"
        desc: "This computer has no Bluetooth adapter, or the bluetooth service is not running.\nPlug in a USB adapter — it will show up here."
    }

    ColumnLayout {
        visible: !!page.adapter
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF00AF)
            title: "Bluetooth"
            desc: page.adapter ? `${page.adapter.name} · ${page.adapter.enabled ? "on" : "off"}` : ""

            SSwitch {
                checked: page.adapter?.enabled ?? false
                onToggled: v => page.adapter.enabled = v
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0349)
            title: "Search for devices"
            desc: page.adapter?.discovering ? "Searching…" : "Make sure the device is in pairing mode"

            SSwitch {
                checked: page.adapter?.discovering ?? false
                enabled: page.adapter?.enabled ?? false
                onToggled: v => page.adapter.discovering = v
            }
        }
    }

    SSection {
        visible: page.devices.length > 0
        text: I18n.tr("Devices")
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: page.devices

            SCard {
                id: dev
                required property BluetoothDevice modelData

                icon: String.fromCodePoint(0xF00AF)
                title: modelData.name || modelData.address
                desc: [modelData.connected ? "Connected" : modelData.paired ? "Paired" : "Available",
                       modelData.batteryAvailable ? `battery ${Math.round(modelData.battery * 100)}%` : ""].filter(s => s).join(" · ")

                SButton {
                    visible: !dev.modelData.paired
                    text: dev.modelData.pairing ? "Pairing…" : "Pair"
                    onClicked: dev.modelData.pair()
                }
                SButton {
                    visible: dev.modelData.paired
                    text: dev.modelData.connected ? "Disconnect" : "Connect"
                    primary: !dev.modelData.connected
                    onClicked: dev.modelData.connected ? dev.modelData.disconnect() : dev.modelData.connect()
                }
                SButton {
                    visible: dev.modelData.paired
                    icon: Icons.trash
                    danger: true
                    onClicked: dev.modelData.forget()
                }
            }
        }
    }
}
