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

    Component.onCompleted: pp.running = true

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

    SSection { text: I18n.tr("Power") }

    RowLayout {
        spacing: 8

        SButton { text: I18n.tr("Lock"); icon: String.fromCodePoint(0xF033E); onClicked: Power.lock() }
        SButton { text: I18n.tr("Sleep"); icon: String.fromCodePoint(0xF0904); onClicked: Power.suspend() }
        SButton { text: I18n.tr("Power menu…"); icon: String.fromCodePoint(0xF0425); onClicked: Quickshell.execDetached(["qs", "ipc", "call", "power", "toggle"]) }
    }
}
