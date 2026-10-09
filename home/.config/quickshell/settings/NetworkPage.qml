import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// Сеть: Ethernet, Wi-Fi, VPN, файрвол ufw
Page {
    id: page

    title: "Network & Internet"
    subtitle: "Connection status and firewall"

    property bool hasWifi: false
    property bool ufwEnabled: false
    property var rules: []            // [{ num, to, action, from }]
    property bool rulesLoaded: false
    property bool busy: false

    // ── DNS (systemd-resolved)
    readonly property var dnsPresets: [
        { value: "auto", label: "Automatic (from network / VPN)", servers: [] },
        { value: "cloudflare", label: "Cloudflare — 1.1.1.1", servers: ["1.1.1.1#cloudflare-dns.com", "1.0.0.1#cloudflare-dns.com"] },
        { value: "google", label: "Google — 8.8.8.8", servers: ["8.8.8.8#dns.google", "8.8.4.4#dns.google"] },
        { value: "quad9", label: "Quad9 — 9.9.9.9", servers: ["9.9.9.9#dns.quad9.net", "149.112.112.112#dns.quad9.net"] },
        { value: "adguard", label: "AdGuard (blocks ads) — 94.140.14.14", servers: ["94.140.14.14#dns.adguard-dns.com", "94.140.15.15#dns.adguard-dns.com"] },
        { value: "custom", label: "Custom…", servers: [] },
    ]
    property string dnsPreset: "auto"
    property var dnsCustom: []
    property bool dnsTls: false
    property string dnsActive: ""

    function applyDns(preset, custom, tls) {
        const p = dnsPresets.find(x => x.value === preset);
        const servers = preset === "custom" ? custom : (p?.servers ?? []);
        busy = true;
        if (preset === "auto" || servers.length === 0) {
            dnsProc.command = ["pkexec", "sh", "-c",
                "rm -f /etc/systemd/resolved.conf.d/90-quickshell.conf && systemctl restart systemd-resolved"];
        } else {
            const conf = `# managed by Quickshell settings (preset: ${preset})\n[Resolve]\nDNS=${servers.join(" ")}\nDomains=~.\nDNSOverTLS=${tls ? "yes" : "no"}\n`;
            dnsProc.command = ["pkexec", "sh", "-c",
                'mkdir -p /etc/systemd/resolved.conf.d && printf "%b" "$1" > /etc/systemd/resolved.conf.d/90-quickshell.conf && systemctl restart systemd-resolved',
                "sh", conf];
        }
        dnsProc.running = true;
    }

    Process {
        id: dnsProc
        onExited: {
            page.busy = false;
            dnsRead.running = true;
            Net.refreshInfo();
        }
    }

    // что сейчас настроено и что реально используется
    Process {
        id: dnsRead
        command: ["sh", "-c", "cat /etc/systemd/resolved.conf.d/90-quickshell.conf 2>/dev/null; echo '@@'; resolvectl dns 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [conf, active] = text.split("@@");
                const m = conf.match(/preset: (\w+)/);
                page.dnsPreset = m ? m[1] : "auto";
                const d = conf.match(/^DNS=(.*)$/m);
                if (page.dnsPreset === "custom" && d) page.dnsCustom = d[1].trim().split(/\s+/);
                page.dnsTls = /DNSOverTLS=yes/.test(conf);
                page.dnsActive = active.split("\n").map(l => l.trim()).filter(l => /:\s*\S/.test(l)).join("\n");
            }
        }
    }

    Component.onCompleted: {
        Net.refreshInfo();
        wifiCheck.running = true;
        dnsRead.running = true;
    }

    Timer {
        interval: 5000
        running: page.visible
        repeat: true
        onTriggered: Net.refreshInfo()
    }

    Process {
        id: wifiCheck
        command: ["sh", "-c", "ls -d /sys/class/net/*/wireless 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: page.hasWifi = text.trim() !== ""
        }
    }

    // ufw: статус читаем без прав, действия — через pkexec (окно пароля)
    FileView {
        id: ufwConf
        path: "/etc/ufw/ufw.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: page.ufwEnabled = /^ENABLED=yes/m.test(text())
    }

    function ufw(script, ...args) {
        busy = true;
        ufwProc.command = ["pkexec", "sh", "-c", script + "; ufw status numbered", "sh"].concat(args);
        ufwProc.running = true;
    }

    Process {
        id: ufwProc
        stdout: StdioCollector {
            onStreamFinished: {
                page.busy = false;
                const out = [];
                for (const line of text.split("\n")) {
                    const m = line.match(/^\[\s*(\d+)\]\s+(.+?)\s{2,}(ALLOW|DENY|REJECT|LIMIT)(?: (IN|OUT|FWD))?\s+(.+)$/);
                    if (m) out.push({ num: m[1], to: m[2].trim(), action: m[3] + (m[4] ? " " + m[4] : ""), from: m[5].trim() });
                }
                if (/Status:/.test(text)) {
                    page.rules = out;
                    page.rulesLoaded = true;
                }
                ufwConf.reload();
            }
        }
        onExited: busy = false
    }

    // ── подключение
    SSection { text: I18n.tr("Connection") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: Net.type === "wifi" ? Icons.wifi : Net.type === "ethernet" ? Icons.ethernet : Icons.offline
            title: Net.type === "none" ? "Disconnected" : `${Net.type === "wifi" ? "Wi-Fi" : "Ethernet"} · ${Net.iface}`
            desc: Net.type === "none" ? "No active connection" : `${(Net.info.ipv4 ?? []).join(", ") || "no IPv4"}   ·   ${Net.info.linkSpeed || ""}`

            Column {
                spacing: 2
                Text {
                    anchors.right: parent.right
                    text: `${Icons.down} ${Net.formatSpeed(Net.rxSpeed)}`
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                Text {
                    anchors.right: parent.right
                    text: `${Icons.up} ${Net.formatSpeed(Net.txSpeed)}`
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0A5F)  // ip-network
            title: "Gateway & DNS"
            desc: `Gateway ${Net.info.gateway || "—"}   ·   DNS ${(Net.info.dns ?? []).join(", ") || "—"}`
        }

        SCard {
            icon: String.fromCodePoint(0xF0582)
            title: "VPN"
            desc: (Net.info.vpn ?? []).length ? `Active: ${Net.info.vpn.join(", ")}` : "No VPN interfaces up"
        }

        SCard {
            icon: Icons.wifi
            title: "Wi-Fi"
            desc: page.hasWifi ? "Wi-Fi adapter found — install iwd or NetworkManager to manage networks"
                               : "No Wi-Fi adapter detected on this computer"
        }
    }

    // ── DNS
    SSection { text: I18n.tr("DNS") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF0A5F)
            title: "DNS server"
            desc: "Used for all connections. Changing it needs your password."

            SDropdown {
                minWidth: 280
                options: page.dnsPresets.map(p => ({ value: p.value, label: p.label }))
                current: page.dnsPreset
                enabled: !page.busy
                onPicked: v => {
                    page.dnsPreset = v;
                    if (v !== "custom") page.applyDns(v, [], page.dnsTls);
                }
            }
        }

        // свои адреса
        Rectangle {
            visible: page.dnsPreset === "custom"
            Layout.fillWidth: true
            implicitHeight: customCol.implicitHeight + 28
            radius: 10
            color: Theme.surface

            ColumnLayout {
                id: customCol
                x: 18
                y: 14
                width: parent.width - 36
                spacing: 8

                Text {
                    text: I18n.tr("Custom servers")
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: page.dnsCustom

                        Rectangle {
                            id: chip
                            required property string modelData
                            required property int index
                            width: chipRow.implicitWidth + 20
                            height: 30
                            radius: 8
                            color: Theme.surfaceHi

                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: chip.modelData
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 2
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: Icons.close
                                    color: rm.containsMouse ? Theme.urgent : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 2
                                    anchors.verticalCenter: parent.verticalCenter

                                    MouseArea {
                                        id: rm
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: page.dnsCustom = page.dnsCustom.filter((_, i) => i !== chip.index)
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 8
                        color: Theme.surfaceHi
                        border.width: 1
                        border.color: dnsInput.activeFocus ? Theme.line : Theme.surfaceHi2

                        TextInput {
                            id: dnsInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            clip: true
                            // IPv4 / IPv6, по желанию #имя-для-TLS
                            validator: RegularExpressionValidator { regularExpression: /^[0-9a-fA-F:.]*(#[a-zA-Z0-9.-]*)?$/ }
                            Keys.onReturnPressed: addDns.clicked()

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !dnsInput.text
                                text: I18n.tr("e.g. 1.1.1.1 or 2606:4700::1111")
                                color: Theme.dim
                                font: dnsInput.font
                            }
                        }
                    }

                    SButton {
                        id: addDns
                        text: I18n.tr("Add")
                        enabled: /^(\d{1,3}(\.\d{1,3}){3}|[0-9a-fA-F:]{2,})(#[a-zA-Z0-9.-]+)?$/.test(dnsInput.text)
                        onClicked: {
                            if (!enabled) return;
                            page.dnsCustom = page.dnsCustom.concat([dnsInput.text]);
                            dnsInput.text = "";
                        }
                    }

                    SButton {
                        text: I18n.tr("Apply")
                        primary: true
                        enabled: page.dnsCustom.length > 0 && !page.busy
                        onClicked: page.applyDns("custom", page.dnsCustom, page.dnsTls)
                    }
                }
            }
        }

        SCard {
            visible: page.dnsPreset !== "auto"
            icon: String.fromCodePoint(0xF033E)
            title: "Encrypted DNS (DNS over TLS)"
            desc: "Hides your DNS queries from the provider"

            SSwitch {
                checked: page.dnsTls
                enabled: !page.busy
                onToggled: v => {
                    page.dnsTls = v;
                    page.applyDns(page.dnsPreset, page.dnsCustom, v);
                }
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF02FC)
            title: "In use now"
            desc: page.dnsActive || "—"
        }
    }

    // ── файрвол
    SSection { text: I18n.tr("Firewall (ufw)") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF0582)
            title: "Firewall"
            desc: page.ufwEnabled ? "Active — incoming connections are filtered" : "Disabled"

            SSwitch {
                checked: page.ufwEnabled
                enabled: !page.busy
                onToggled: v => page.ufw(v ? "ufw --force enable" : "ufw disable")
            }
        }

        SCard {
            visible: !page.rulesLoaded
            icon: String.fromCodePoint(0xF0CB6)
            title: "Rules"
            desc: "Viewing rules needs your password"

            SButton {
                text: page.busy ? "…" : "Show rules"
                onClicked: page.ufw("true")
            }
        }

        Rectangle {
            visible: page.rulesLoaded
            Layout.fillWidth: true
            implicitHeight: rulesCol.implicitHeight + 24
            radius: 10
            color: Theme.surface

            ColumnLayout {
                id: rulesCol
                x: 18
                y: 12
                width: parent.width - 36
                spacing: 4

                Text {
                    visible: page.rules.length === 0
                    text: I18n.tr("No rules")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }

                Repeater {
                    model: page.rules

                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: `#${parent.modelData.num}`
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            Layout.preferredWidth: 170
                            text: parent.modelData.to
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            Layout.preferredWidth: 90
                            text: parent.modelData.action
                            color: /DENY|REJECT/.test(parent.modelData.action) ? Theme.urgent : Theme.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: parent.modelData.from
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                        SButton {
                            icon: Icons.trash
                            danger: true
                            implicitHeight: 28
                            onClicked: page.ufw('ufw --force delete "$1"', parent.modelData.num)
                        }
                    }
                }
            }
        }

        // добавить правило
        SCard {
            icon: "+"
            title: "Add rule"
            desc: "Port or range with optional protocol: 22, 8080/tcp, 6000:6010/udp"

            Rectangle {
                width: 150
                height: 34
                radius: 8
                color: Theme.surfaceHi
                border.width: 1
                border.color: portInput.activeFocus ? Theme.line : Theme.surfaceHi2

                TextInput {
                    id: portInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    clip: true
                    validator: RegularExpressionValidator { regularExpression: /^\d{0,5}(:\d{0,5})?(\/(t|tc|tcp|u|ud|udp)?)?$/ }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !portInput.text
                        text: I18n.tr("port")
                        color: Theme.dim
                        font: portInput.font
                    }
                }
            }

            SChoice {
                id: actionChoice
                property string value: "allow"
                options: [{ value: "allow", label: "Allow" }, { value: "deny", label: "Deny" }]
                current: value
                onPicked: v => value = v
            }

            SButton {
                text: I18n.tr("Add")
                primary: true
                enabled: /^\d{1,5}(:\d{1,5})?(\/(tcp|udp))?$/.test(portInput.text) && !page.busy
                onClicked: {
                    page.ufw('ufw "$1" "$2"', actionChoice.value, portInput.text);
                    portInput.text = "";
                }
            }
        }
    }
}
