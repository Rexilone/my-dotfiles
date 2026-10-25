import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// Электропитание: экран и сон, режим питания, кнопки
Page {
    id: page

    title: "Power"
    subtitle: "Screen, sleep and power mode"

    property bool hasProfiles: false
    property string profile: ""
    property var profiles: []

    readonly property var minutes: [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
        .map(m => ({ value: m, label: m === 0 ? "Never" : m < 60 ? `${m} min` : `${m / 60} h` }))

    Component.onCompleted: {
        pp.running = true;
        wolStatus.running = true;
    }

    // ── включение по сети (Wake-on-LAN): rexilone-wol
    property var wol: ({})
    property bool wolBusy: false
    readonly property var wolCfg: Rexlink.settings.wol ?? { host: "", port: 9 }

    Process {
        id: wolStatus
        command: ["sh", "-c", '"$HOME/.local/bin/rexilone-wol" status']
        stdout: StdioCollector {
            onStreamFinished: { try { page.wol = JSON.parse(text); } catch (e) {} }
        }
    }
    Process {
        id: wolSet
        onExited: { page.wolBusy = false; wolStatus.running = true; }
    }
    function setWol(on) {
        wolBusy = true;
        wolSet.command = ["sh", "-c", `"$HOME/.local/bin/rexilone-wol" ${on ? "enable" : "disable"}`];
        wolSet.running = true;
    }
    function saveWolAddr(host, port) {
        Rexlink.set("wol", { host: host.trim(), port: parseInt(port) || 9 });
    }

    Process {
        id: pp
        command: ["sh", "-c", "command -v powerprofilesctl >/dev/null || exit 0; echo yes; powerprofilesctl get; powerprofilesctl list | sed -n 's/^[* ] *\\([a-z-]*\\):$/\\1/p'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n").filter(x => x.trim());
                page.hasProfiles = l[0] === "yes";
                page.profile = l[1] ?? "";
                page.profiles = l.slice(2);
            }
        }
    }

    Process {
        id: act
        onExited: pp.running = true
    }

    SSection { text: I18n.tr("Screen & sleep") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF033E)
            title: "Lock the screen after"
            desc: "With swaylock"

            SDropdown {
                minWidth: 140
                options: page.minutes
                current: Settings.power.lock ?? 0
                onPicked: v => Settings.setPower("lock", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0379)
            title: "Turn off the screens after"
            desc: "They wake up on mouse or keyboard"

            SDropdown {
                minWidth: 140
                options: page.minutes
                current: Settings.power.screenOff ?? 0
                onPicked: v => Settings.setPower("screenOff", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0904)
            title: "Put the computer to sleep after"

            SDropdown {
                minWidth: 140
                options: page.minutes
                current: Settings.power.suspend ?? 0
                onPicked: v => Settings.setPower("suspend", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF033E)
            title: "Lock before sleep"

            SSwitch {
                checked: Settings.power.lockOnSuspend ?? true
                onToggled: v => Settings.setPower("lockOnSuspend", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0176)  // coffee
            title: "Keep awake"
            desc: "Pause all timers above (also: qs ipc call idle caffeine). Videos and games already keep the screen on."

            SSwitch {
                checked: Power.caffeine
                onToggled: v => Power.caffeine = v
            }
        }
    }

    SSection { text: I18n.tr("Power mode") }

    SCard {
        visible: !page.hasProfiles
        icon: String.fromCodePoint(0xF06A5)
        title: "Power profiles are not installed"
        desc: "power-profiles-daemon switches between Power saver, Balanced and Performance"

        SButton {
            text: I18n.tr("Install")
            primary: true
            onClicked: {
                act.command = ["pkexec", "sh", "-c", "pacman -S --needed --noconfirm power-profiles-daemon && systemctl enable --now power-profiles-daemon"];
                act.running = true;
            }
        }
    }

    SCard {
        visible: page.hasProfiles
        icon: String.fromCodePoint(0xF06A5)
        title: "Power mode"

        SChoice {
            options: page.profiles.map(p => ({ value: p, label: { "power-saver": "Saver", "balanced": "Balanced", "performance": "Performance" }[p] ?? p }))
            current: page.profile
            onPicked: v => {
                act.command = ["powerprofilesctl", "set", v];
                act.running = true;
            }
        }
    }

    SSection { text: I18n.tr("Wake-on-LAN") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF0425)
            title: "Turn on over the network"
            desc: page.wol.iface
                ? `${page.wol.iface} · ${page.wol.mac}` + (page.wol.mode ? ` · Wake-on: ${page.wol.mode}` : "")
                : "Wake the computer from the phone (Rexlink) with a magic packet"

            SSwitch {
                enabled: !page.wolBusy && !!page.wol.iface
                checked: page.wol.enabled ?? false
                onToggled: v => page.setWol(v)
            }
        }

        SCard {
            visible: page.wol.iface !== undefined && page.wol.wired === false
            icon: String.fromCodePoint(0xF0026)
            title: "Connected over Wi-Fi"
            desc: "Wake-on-LAN almost always works only over a network cable"
        }

        SCard {
            visible: page.wol.supported === "false"
            icon: String.fromCodePoint(0xF0026)
            title: "The network card can't wake on a magic packet"
        }

        SCard {
            visible: page.wol.enabled ?? false
            icon: String.fromCodePoint(0xF02FC)
            title: "Also turn it on in BIOS / UEFI"
            desc: "«Wake on LAN», «Power On by PCI-E» or «Resume by LAN». Turn the computer off normally (not by unplugging) — the network card stays powered"
        }

        // внешний адрес: телефон получит его от Rexlink, в приложении его можно поменять
        SCard {
            visible: page.wol.enabled ?? false
            icon: String.fromCodePoint(0xF059F)
            title: "From the internet"
            desc: Rexlink.connected
                ? "Your home IP or DDNS name and the UDP port forwarded on the router to this computer (port 9). Sent to your devices in Rexlink"
                : "Start Rexlink (Settings → Phone) to send the address to your phone"

            // сохраняется через секунду после ввода
            Timer {
                id: wolSave
                interval: 1000
                onTriggered: if (wolHost.text.trim() !== (page.wolCfg.host ?? "") || wolPort.text !== String(page.wolCfg.port ?? 9))
                    page.saveWolAddr(wolHost.text, wolPort.text)
            }
            SField {
                id: wolHost
                Layout.preferredWidth: 200
                Layout.fillWidth: false
                enabled: Rexlink.connected
                placeholder: "IP / DDNS"
                text: page.wolCfg.host ?? ""
                onAccepted: page.saveWolAddr(wolHost.text, wolPort.text)
                onTextChanged: wolSave.restart()
            }
            SField {
                id: wolPort
                Layout.preferredWidth: 80
                Layout.fillWidth: false
                enabled: Rexlink.connected
                placeholder: "9"
                text: String(page.wolCfg.port ?? 9)
                onAccepted: page.saveWolAddr(wolHost.text, wolPort.text)
                onTextChanged: wolSave.restart()
            }
        }
        // проброс на сам ПК часто не работает: выключенный компьютер роутер через минуту «забывает» —
        // надёжнее пробросить порт на устройство, которое остаётся дома (Rexlink повторит пакет в сеть)
        SCard {
            visible: page.wol.enabled ?? false
            icon: String.fromCodePoint(0xF04F6)
            title: "Reliable way: through a device at home"
            desc: "A minute after shutdown the router forgets the computer, and a packet forwarded to it gets lost. Leave a tablet or an old phone at home with Rexlink, turn on «Wake the computer through this device» in it, and forward the UDP port on the router to that device, port 40009 — it repeats the packet to the whole home network. Check that the router's internet address (WAN) is the same as the one above: an address like 100.64–100.127.x.x, 10.x.x.x or 172.16–31.x.x means the provider shares it, and nothing gets in from outside — ask the provider for a public IP"
        }
    }

    SSection { text: I18n.tr("Power") }

    RowLayout {
        spacing: 8

        SButton { text: I18n.tr("Lock"); icon: String.fromCodePoint(0xF033E); onClicked: Power.lock() }
        SButton { text: I18n.tr("Sleep"); icon: String.fromCodePoint(0xF0904); onClicked: Power.suspend() }
        SButton { text: I18n.tr("Power menu…"); icon: String.fromCodePoint(0xF0425); onClicked: Quickshell.execDetached(["qs", "ipc", "call", "power", "toggle"]) }
    }
}
