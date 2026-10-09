import QtQuick
import QtQuick.Layouts
import qs.services

// скорость (график за минуту) и сведения о подключении
ColumnLayout {
    id: root

    property bool active: false
    onActiveChanged: if (active) Net.refreshInfo()

    width: 340
    spacing: 10

    Timer {
        interval: 5000
        running: root.active
        repeat: true
        onTriggered: Net.refreshInfo()
    }

    component Label: Text {
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    component Value: Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideMiddle
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    MenuHeader {
        icon: Net.type === "wifi" ? Icons.wifi : Net.type === "ethernet" ? Icons.ethernet : Icons.offline
        title: Net.type === "none" ? "Disconnected" : Net.type === "wifi" ? (Net.info.ssid || "Wi-Fi") : "Ethernet"
        subtitle: Net.type === "none" ? "No active connection" : `${Net.iface}${Net.info.linkSpeed ? "  ·  " + Net.info.linkSpeed : ""}`
        settingsPage: "network"
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: speedCol.implicitHeight + 24
        radius: 12
        color: Theme.surface

        ColumnLayout {
            id: speedCol
            x: 14
            y: 12
            width: parent.width - 28
            spacing: 8

            // текущая скорость
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Text {
                    Layout.fillWidth: true
                    text: `${Icons.down} ${Net.formatSpeed(Net.rxSpeed)}`
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                }
                Text {
                    text: `${Icons.up} ${Net.formatSpeed(Net.txSpeed)}`
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                }
            }

            // график за последнюю минуту: входящая — светлая, исходящая — серая
            Canvas {
                id: graph
                Layout.fillWidth: true
                Layout.preferredHeight: 60

                Connections {
                    target: Net
                    function onRxHistoryChanged() {
                        if (root.active) graph.requestPaint();
                    }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const rx = Net.rxHistory, tx = Net.txHistory;
                    const max = Math.max(1024, ...rx, ...tx) * 1.15;
                    const step = width / (Net.historySize - 1);

                    const line = (data, color, fill) => {
                        if (data.length < 2) return;
                        const x0 = width - (data.length - 1) * step;
                        ctx.beginPath();
                        ctx.moveTo(x0, height);
                        data.forEach((v, i) => ctx.lineTo(x0 + i * step, height - v / max * height));
                        ctx.lineTo(width, height);
                        ctx.closePath();
                        ctx.fillStyle = fill;
                        ctx.fill();
                        ctx.beginPath();
                        data.forEach((v, i) => {
                            const x = x0 + i * step, y = height - v / max * height;
                            i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
                        });
                        ctx.strokeStyle = color;
                        ctx.lineWidth = 1.5;
                        ctx.stroke();
                    };

                    line(tx, Theme.dim, Qt.rgba(1, 1, 1, 0.03));
                    line(rx, Theme.fg, Qt.rgba(1, 1, 1, 0.06));
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: detailsGrid.implicitHeight + 24
        radius: 12
        color: Theme.surface

            GridLayout {
            id: detailsGrid
            x: 14
            y: 12
            width: parent.width - 28
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 16
                rowSpacing: 6

                Label { text: I18n.tr("IPv4") }
                Value { text: (Net.info.ipv4 ?? []).join(", ") || "—" }

                Label { text: I18n.tr("IPv6"); visible: (Net.info.ipv6 ?? []).length > 0 }
                Value { text: I18n.tr((Net.info.ipv6 ?? []).join("\n")); visible: text !== "" }

                Label { text: I18n.tr("Gateway") }
                Value { text: Net.info.gateway || "—" }

                Label { text: I18n.tr("DNS") }
                Value { text: (Net.info.dns ?? []).join(", ") || "—" }

                Label { text: "Signal"; visible: Net.type === "wifi" }
                Value { text: `${Net.info.signal || "?"}/70`; visible: Net.type === "wifi" }

                Label { text: I18n.tr("MAC") }
                Value { text: Net.info.mac || "—" }

                Label { text: I18n.tr("MTU") }
                Value { text: Net.info.mtu || "—" }

                Label { text: I18n.tr("VPN") }
                Value { text: I18n.tr((Net.info.vpn ?? []).join(", ") || "off") }

                Label { text: I18n.tr("Received") }
                Value { text: Net.formatBytes(Net.rxTotal) }

                Label { text: I18n.tr("Sent") }
                Value { text: Net.formatBytes(Net.txTotal) }
            }
    }
}
