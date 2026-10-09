import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// Загрузка и вход: меню Limine и экран входа LightDM в стиле шелла, системы на других дисках
Page {
    id: page

    title: "Boot & login"
    subtitle: "Boot menu and login screen follow the shell's colors and wallpaper"

    readonly property var st: BootTheme.status

    // ── служба
    SCard {
        visible: !BootTheme.installed || BootTheme.outdated
        icon: String.fromCodePoint(0xF0026)
        title: BootTheme.installed ? "The boot service has an update" : "The boot service is not set up"
        desc: "rexilone-boot themes the boot menu and the login screen and finds systems on other disks. Needs the password once"

        SButton {
            text: BootTheme.busy ? "Installing…" : BootTheme.installed ? "Update" : "Set up"
            primary: true
            enabled: !BootTheme.busy && BootTheme.dots !== ""
            onClicked: BootTheme.setup()
        }
    }

    SCard {
        visible: BootTheme.installed
        icon: String.fromCodePoint(0xF0493)
        title: page.st.locked ? "The boot menu is locked" : "Applied automatically"
        desc: page.st.locked ? "Limine has an enrolled config hash (Secure Boot) — the boot menu isn't changed; the login screen still is"
            : page.st.time ? `${I18n.tr("On every shutdown and boot")}   ·   ${I18n.tr("last time")} ${Qt.formatDateTime(new Date(page.st.time * 1000), "dd.MM HH:mm")}`
            : "On every shutdown and boot. Apply now to see it on the next start"

        SButton {
            text: BootTheme.busy ? "Applying…" : "Apply now"
            primary: true
            enabled: !BootTheme.busy
            onClicked: BootTheme.applyNow()
        }
    }

    // ── меню загрузки
    SSection { text: I18n.tr("Boot menu (Limine)") }

    SCard {
        icon: String.fromCodePoint(0xF051B)
        title: "Show the menu for"
        desc: "Then the selected system starts by itself"
        SChoice {
            options: [{ value: 0, label: I18n.ru ? "сразу" : "skip" }, { value: 3, label: "3 s" }, { value: 5, label: "5 s" },
                      { value: 10, label: "10 s" }, { value: -1, label: I18n.ru ? "ждать" : "wait" }]
            current: Settings.bootTimeout
            onPicked: v => Settings.bootTimeout = v
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF0450)
        title: "Remember the last system"
        desc: "Start what was chosen last time"
        SSwitch {
            checked: Settings.bootRemember
            onToggled: v => Settings.bootRemember = v
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF0E09)
        title: "Wallpaper in the boot menu"
        desc: "The current wallpaper under a card in the scheme's colors"
        SSwitch {
            checked: Settings.bootWallpaper
            onToggled: v => Settings.bootWallpaper = v
        }
    }

    // ── другие системы
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 16
        Layout.bottomMargin: 4
        SSection {
            Layout.fillWidth: true
            Layout.topMargin: 0
            Layout.bottomMargin: 0
            text: I18n.tr("Other systems")
        }
        SButton {
            visible: BootTheme.installed
            text: "Search disks"
            icon: Icons.search
            enabled: !BootTheme.busy
            onClicked: BootTheme.scanNow()
        }
    }

    SCard {
        icon: String.fromCodePoint(0xF02CA)
        title: "Find systems on connected disks"
        desc: "Windows and other Linux on any disk — plug it in and it appears in the boot menu by itself"
        SSwitch {
            checked: Settings.bootOtherSystems
            onToggled: v => Settings.bootOtherSystems = v
        }
    }

    Text {
        visible: Settings.bootOtherSystems && BootTheme.systems.length === 0
        Layout.fillWidth: true
        Layout.leftMargin: 4
        wrapMode: Text.Wrap
        text: I18n.tr("Nothing yet besides this system. Connect a disk with Windows or another Linux — it's found automatically.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    Repeater {
        model: Settings.bootOtherSystems ? BootTheme.systems : []

        SCard {
            id: sys
            required property var modelData
            icon: String.fromCodePoint(/windows/i.test(modelData.name) ? 0xF05B3 : 0xF033D)
            title: modelData.own ? modelData.name : `${modelData.name}   ·   ${modelData.disk}`
            desc: [modelData.own ? I18n.tr("This disk") : (modelData.removable || modelData.tran === "usb" ? I18n.tr("External disk") : I18n.tr("Another disk")),
                   I18n.tr(modelData.present ? "connected" : "not connected"),
                   modelData.hidden ? I18n.tr("hidden from the menu") : "", modelData.path].filter(x => x).join("   ·   ")

            SButton {
                visible: !sys.modelData.present
                text: "Forget"
                enabled: !BootTheme.busy
                onClicked: BootTheme.forget(sys.modelData.id)
            }
            SSwitch {
                checked: !sys.modelData.hidden
                onToggled: v => v ? BootTheme.show(sys.modelData.id) : BootTheme.hide(sys.modelData.id)
            }
        }
    }

    // ── экран входа
    SSection { text: I18n.tr("Login screen") }

    SCard {
        icon: String.fromCodePoint(0xF0E09)
        title: "Blurred wallpaper"
        desc: "Otherwise the wallpaper as is"
        SSwitch {
            checked: Settings.greeterBlur
            onToggled: v => Settings.greeterBlur = v
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF0954)
        title: "Clock in the top bar"
        SSwitch {
            checked: Settings.greeterClock
            onToggled: v => Settings.greeterClock = v
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF0004)
        title: "User picture"
        desc: "~/.face — the picture next to the password field"
        SSwitch {
            checked: Settings.greeterUserImage
            onToggled: v => Settings.greeterUserImage = v
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.topMargin: 10
        wrapMode: Text.Wrap
        text: I18n.tr("Changes are saved now and reach the boot menu and the login screen on the next shutdown — or right away with Apply now.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }
}
