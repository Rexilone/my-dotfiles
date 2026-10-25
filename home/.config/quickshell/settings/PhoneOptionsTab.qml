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

    // память телефона как папка в «Файлах» (WebDAV на телефоне, монтирует служба Rexlink)
    Toggle { key: "phoneFiles"; def: false; icon: String.fromCodePoint(0xF0870); title: "Phone storage in Files"; desc: "The phone's memory as a folder in the file manager over Wi-Fi: copy, open, delete" }
    SCard {
        id: filesCard
        readonly property var f: Rexlink.dev?.files ?? {}
        visible: (Rexlink.settings.phoneFiles ?? false) && !!Rexlink.dev
        icon: String.fromCodePoint(f.state === "on" ? 0xF024B : f.state === "error" || f.state === "permission" ? 0xF0026 : 0xF0870)
        title: ({ on: "Phone storage is open", mounting: "Connecting…", permission: "Allow «All files» on the phone",
                  error: "Couldn't open the phone storage", port: "The phone couldn't open a port" })[f.state] ?? "Waiting for the phone"
        desc: f.state === "on" ? f.uri : f.state === "permission" ? "Rexlink on the phone → Accesses → All files"
            : f.state === "error" ? (f.error ?? "") : "The device must be online"
        SButton {
            visible: filesCard.f.state === "on"
            text: I18n.tr("Open")
            primary: true
            onClicked: Quickshell.execDetached(["xdg-open", filesCard.f.uri])
        }
    }

    // звонки: звук через компьютер — ПК как Bluetooth-гарнитура телефона
    SCard {
        icon: String.fromCodePoint(0xF02CE)
        title: "Talk through the computer"
        desc: !CallAudio.adapter ? "Needs a Bluetooth adapter in the computer"
            : CallAudio.inCall ? "Call audio is going through the computer now"
            : "The computer becomes a Bluetooth headset of the phone: calls you answer here use its speakers and microphone. Pair the phone once in Settings → Bluetooth"
        SSwitch {
            enabled: CallAudio.adapter
            checked: CallAudio.enabled
            onToggled: v => CallAudio.setEnabled(v)
        }
    }

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
    // ── управление этим компьютером с устройства (Rexlink: экран, мышь, клавиатура, питание, свои команды)
    SSection { text: I18n.tr("Computer control") }

    SCard {
        icon: String.fromCodePoint(0xF037D)
        title: "Control this computer from the device"
        desc: "Like RustDesk: the screen, mouse and keyboard — touch, or a keyboard and mouse plugged into the phone; lock, sleep, restart and your commands. Away from home: forward TCP 47820 on the router to this computer and enter your home IP or DDNS in Settings → Power → Wake-on-LAN"
        SSwitch {
            checked: tab.st.remote?.enabled ?? true
            onToggled: v => Rexlink.set("remote", { enabled: v })
        }
    }
    SCard {
        visible: tab.st.remote?.enabled ?? true
        icon: String.fromCodePoint(0xF0A07)
        title: "Picture quality"
        desc: "Long side and frames per second — lower is lighter for mobile internet"
        SChoice {
            options: [{ value: 1280, label: "1280" }, { value: 1600, label: "1600" }, { value: 1920, label: "1920" }]
            current: tab.st.remote?.maxSize ?? 1920
            onPicked: v => Rexlink.set("remote", { maxSize: v })
        }
        SChoice {
            options: [{ value: 15, label: "15" }, { value: 30, label: "30" }, { value: 60, label: "60" }]
            current: tab.st.remote?.fps ?? 30
            onPicked: v => Rexlink.set("remote", { fps: v })
        }
    }
    // свои команды: появляются кнопками в приложении (раздел «Компьютер»)
    Repeater {
        model: (tab.st.remote?.enabled ?? true) ? (tab.st.remote?.commands ?? []) : []
        SCard {
            id: rc
            required property var modelData
            required property int index
            icon: String.fromCodePoint(0xF018D)
            title: modelData.name
            desc: modelData.cmd
            SButton {
                icon: Icons.trash
                danger: true
                onClicked: Rexlink.set("remote", { commands: (tab.st.remote?.commands ?? []).filter((_, i) => i !== rc.index) })
            }
        }
    }
    SCard {
        visible: tab.st.remote?.enabled ?? true
        icon: String.fromCodePoint(0xF0415)
        title: "Add a command"
        desc: "A button in the app runs it on this computer, the output comes back to the phone"
        SField {
            id: cmdName
            Layout.preferredWidth: 150
            Layout.fillWidth: false
            placeholder: I18n.tr("Name")
        }
        SField {
            id: cmdLine
            Layout.preferredWidth: 260
            Layout.fillWidth: false
            placeholder: "systemctl --user restart …"
            onAccepted: addCmd.clicked()
        }
        SButton {
            id: addCmd
            text: "Add"
            primary: true
            enabled: cmdName.text.trim() !== "" && cmdLine.text.trim() !== ""
            onClicked: {
                Rexlink.set("remote", { commands: (tab.st.remote?.commands ?? []).concat([{ name: cmdName.text.trim(), cmd: cmdLine.text.trim() }]) });
                cmdName.text = "";
                cmdLine.text = "";
            }
        }
    }

    // ── скан документа камерой устройства
    SCard {
        icon: String.fromCodePoint(0xF06AB)
        title: "Document scans"
        desc: `${I18n.tr("PDF from the phone camera goes to")} ${(tab.st.scanDirResolved ?? "").replace(Quickshell.env("HOME"), "~")} ${I18n.tr("and opens")}`
        SButton {
            text: "Scan"
            enabled: Rexlink.online
            onClicked: Rexlink.scan("")
        }
    }

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
