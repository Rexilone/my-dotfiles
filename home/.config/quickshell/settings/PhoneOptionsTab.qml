import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// Телефон → Настройки Rexlink: синхронизация, экран, устройства, служба, бар и демонстрация экрана
ColumnLayout {
    id: tab

    readonly property var st: Rexlink.settings

    Layout.fillWidth: true
    spacing: 3

    component Toggle: SCard {
        id: tg
        property string key: ""
        property bool def: true
        SSwitch {
            checked: Rexlink.settings[tg.key] ?? tg.def
            onToggled: v => Rexlink.set(tg.key, v)
        }
    }
    component ShellToggle: SCard {
        id: sh
        property string key: ""
        property bool def: true
        SSwitch {
            checked: Settings.moduleOn(sh.key, sh.def)
            onToggled: v => Settings.setModule(sh.key, v)
        }
    }

    // ── синхронизация
    SSection { text: I18n.tr("What to sync"); Layout.topMargin: 0 }

    Toggle { key: "notifications"; icon: String.fromCodePoint(0xF009A); title: "Phone notifications"; desc: "Get notifications from the device" }
    Toggle { key: "mirrorToDesktop"; icon: String.fromCodePoint(0xF0379); title: "Show them on the desktop"; desc: "As regular pop-up notifications, with actions and quick reply" }
    Toggle { key: "calls"; icon: String.fromCodePoint(0xF03F2); title: "Calls"; desc: "Notifications about incoming and missed calls" }
    Toggle { key: "sms"; icon: String.fromCodePoint(0xF0369); title: "New SMS"; desc: "Notify about incoming messages" }
    Toggle { key: "clipboard"; icon: String.fromCodePoint(0xF014D); title: "Shared clipboard"; desc: tab.st.wlClipboard === false ? "Needs the wl-clipboard package" : "Text and images both ways" }
    Toggle { key: "media"; icon: String.fromCodePoint(0xF075A); title: "Device media"; desc: "Control what plays on the device" }
    Toggle { key: "pcMedia"; icon: String.fromCodePoint(0xF0379); title: "PC player on the device"; desc: tab.st.playerctl === false ? "Needs the playerctl package" : "Control the computer's music from the phone's notification shade (MPRIS)" }

    // ── экран устройства
    SSection { text: I18n.tr("Device screen") }

    SCard {
        icon: String.fromCodePoint(0xF00E4)
        title: "Capture over ADB"
        desc: tab.st.adb && tab.st.scrcpy ? "Like scrcpy, no prompt on the device — when it's on USB or wireless debugging. Otherwise Android asks “Start”"
            : "Needs the android-tools and scrcpy packages"
        SSwitch {
            checked: tab.st.screen?.adb !== false
            onToggled: v => Rexlink.set("screen", { adb: v })
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF05A8)
        title: "Keep the device screen on while showing"
        desc: "The device doesn't sleep or lock while its screen is shown here"
        SSwitch {
            checked: tab.st.screen?.keepAwake !== false
            onToggled: v => Rexlink.set("screen", { keepAwake: v })
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF0379)
        title: "Maximum size"
        desc: "Long side of the picture, in pixels"
        SChoice {
            options: [{ value: 960, label: "960" }, { value: 1280, label: "1280" }, { value: 1600, label: "1600" }, { value: 1920, label: "1920" }]
            current: tab.st.screen?.maxSize ?? 1280
            onPicked: v => Rexlink.set("screen", { maxSize: v })
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF040A)
        title: "Bitrate"
        SChoice {
            options: [{ value: 4000000, label: I18n.ru ? "4 Мбит" : "4 Mbit" }, { value: 8000000, label: I18n.ru ? "8 Мбит" : "8 Mbit" }, { value: 16000000, label: I18n.ru ? "16 Мбит" : "16 Mbit" }]
            current: tab.st.screen?.bitrate ?? 8000000
            onPicked: v => Rexlink.set("screen", { bitrate: v })
        }
    }

    // ── устройства
    SSection { text: I18n.tr("Devices") }

    SCard {
        icon: String.fromCodePoint(0xF01DA)
        title: "Update the app on devices"
        desc: Rexlink.apk.versionName ? `${I18n.tr("Version next to the service")}: ${Rexlink.apk.versionName}   ·   ${I18n.tr("over adb silently, otherwise the device downloads and installs it")}`
            : "rexlink.apk not found next to the service"
        SButton {
            visible: !!Rexlink.apk.versionName
            text: "Show file"
            icon: Icons.folder
            onClicked: Quickshell.execDetached(["sh", "-c", 'xdg-open "$(dirname "$(readlink -f "$HOME/.local/bin/rexlink")")/../../../rexlink"'])
        }
        SSwitch {
            checked: tab.st.autoUpdateDevices !== false
            onToggled: v => Rexlink.set("autoUpdateDevices", v)
        }
    }

    // ── в шелле
    SSection { text: I18n.tr("In the shell") }

    ShellToggle { key: "phone"; icon: String.fromCodePoint(0xF011C); title: "Phone in the bar"; desc: "Battery and notifications; click for the phone menu, right-click to find it" }
    ShellToggle { key: "phonePercent"; icon: String.fromCodePoint(0xF0079); title: "Battery percent"; desc: "Show the number next to the battery icon" }
    ShellToggle { key: "phoneOffline"; def: false; icon: String.fromCodePoint(0xF0318); title: "Show when offline"; desc: "Keep the icon in the bar when the phone isn't connected" }
    ShellToggle { key: "phoneCalls"; icon: String.fromCodePoint(0xF03F2); title: "Incoming call card"; desc: "Answer or decline calls from the desktop" }

    // ── демонстрация экрана
    SSection { text: I18n.tr("Screen sharing") }

    ShellToggle { key: "phoneCastHideCalls"; icon: String.fromCodePoint(0xF03F2); title: "Hide calls from screencast"; desc: "Viewers see an empty spot instead of the incoming call card. You still see it" }
    ShellToggle { key: "phoneCastHideNotifs"; icon: String.fromCodePoint(0xF0209); title: "Hide phone notifications from screencast"; desc: "Phone notifications and the phone menu in the bar are blacked out for viewers" }

    // ── служба
    SSection { text: I18n.tr("Service") }

    SCard {
        icon: String.fromCodePoint(0xF0493)
        title: Rexlink.connected ? "Rexlink service is running" : "Rexlink service is not running"
        desc: Rexlink.connected ? `${I18n.tr("Computer")} «${tab.st.name ?? ""}»   ·   ${(tab.st.ips ?? []).join(", ")}   ·   ${I18n.tr("port")} 47820` : "rexlink.service"
        SButton {
            text: Rexlink.connected ? "Restart" : "Start"
            primary: !Rexlink.connected
            onClicked: Rexlink.connected ? Rexlink.restart() : Rexlink.start()
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF0412)
        title: "Start with the system"
        desc: "Runs the service after login (rexlink.service)"
        SSwitch {
            checked: Rexlink.autostart
            onToggled: v => Rexlink.setAutostart(v)
        }
    }
    SCard {
        visible: Rexlink.connected
        icon: String.fromCodePoint(0xF0498)
        title: "Certificate fingerprint"
        desc: tab.st.fingerprint ?? ""
    }
    SCard {
        visible: Rexlink.connected
        icon: String.fromCodePoint(0xF02FD)
        title: "Components"
        desc: [["ffmpeg", tab.st.ffmpeg], ["wl-clipboard", tab.st.wlClipboard], ["playerctl", tab.st.playerctl],
               ["adb", tab.st.adb], ["scrcpy", tab.st.scrcpy], ["v4l2loopback", tab.st.webcamResolved]]
            .map(([n, ok]) => `${n} ${ok ? "✓" : "✗"}`).join("   ·   ")
    }
}
