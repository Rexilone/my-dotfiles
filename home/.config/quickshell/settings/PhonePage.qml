import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// Телефон (Rexlink): служба, сопряжение, устройства, синхронизация, камера, бар
Page {
    id: page

    title: "Phone"
    subtitle: "Rexlink — notifications, calls, files and clipboard from your Android devices"

    property string renaming: ""

    readonly property var st: Rexlink.settings

    // ── служба
    SCard {
        icon: String.fromCodePoint(0xF011C)
        title: !Rexlink.installed ? "Rexlink is not installed" : Rexlink.connected ? "Rexlink is running" : "Rexlink is not running"
        desc: Rexlink.connected ? `PC name: ${page.st.name ?? "—"}   ·   ${(page.st.ips ?? []).join(", ")}` : "Start it to connect your phone"

        SButton {
            visible: Rexlink.installed && !Rexlink.connected
            text: I18n.tr("Start")
            primary: true
            onClicked: Rexlink.start()
        }
        SButton {
            visible: Rexlink.installed
            text: I18n.tr("Open app")
            onClicked: Rexlink.show("overview")
        }
    }

    SCard {
        visible: Rexlink.installed
        icon: String.fromCodePoint(0xF0412)
        title: "Start with the system"
        desc: "Runs Rexlink in the background after login (rexlink.service)"

        SSwitch {
            checked: Rexlink.autostart
            onToggled: v => Rexlink.setAutostart(v)
        }
    }

    // ── запрос сопряжения
    Rectangle {
        visible: !!Rexlink.pairing.id
        Layout.fillWidth: true
        implicitHeight: 72
        radius: 10
        color: Theme.surfaceHi
        border.width: 1
        border.color: Theme.accent

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: `${Rexlink.pairing.name ?? ""} wants to pair`
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                Text {
                    text: `Check the code on the device: ${Rexlink.pairing.code ?? ""}`
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
            SButton { text: I18n.tr("Decline"); onClicked: Rexlink.pairAnswer(false) }
            SButton { text: I18n.tr("Pair"); primary: true; onClicked: Rexlink.pairAnswer(true) }
        }
    }

    // ── устройства
    SSection {
        visible: Rexlink.connected
        text: I18n.tr("Devices")
    }

    Text {
        visible: Rexlink.connected && Rexlink.devices.length === 0
        text: I18n.tr("No devices yet — install Rexlink on your phone and pair it")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: Rexlink.devices

            Rectangle {
                id: d
                required property var modelData
                readonly property bool editing: page.renaming === modelData.id

                Layout.fillWidth: true
                implicitHeight: 64
                radius: 10
                color: Theme.surface
                border.width: modelData.current ? 1 : 0
                border.color: Theme.accent

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 14

                    Text {
                        text: Rexlink.kindIcon(d.modelData.kind)
                        color: d.modelData.online ? Theme.accent : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.iconSize + 6
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        visible: !d.editing

                        Text {
                            text: d.modelData.name + (d.modelData.current ? "   ·   current" : "")
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            font.bold: d.modelData.current
                        }
                        Text {
                            text: [d.modelData.model,
                                   d.modelData.online ? "online" : "offline",
                                   d.modelData.battery >= 0 ? `${d.modelData.battery}%${d.modelData.charging ? " ⚡" : ""}` : "",
                                   d.modelData.appVersion ? `app ${d.modelData.appVersion}` : ""].filter(s => s).join("  ·  ")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }

                    Rectangle {
                        visible: d.editing
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 8
                        color: Theme.surfaceHi
                        border.width: 1
                        border.color: Theme.line

                        TextInput {
                            id: nameInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            onVisibleChanged: if (visible) { text = d.modelData.name; forceActiveFocus(); selectAll(); }
                            Keys.onReturnPressed: { Rexlink.rename(d.modelData.id, text); page.renaming = ""; }
                            Keys.onEscapePressed: page.renaming = ""
                        }
                    }

                    SButton {
                        visible: d.editing
                        text: I18n.tr("Save")
                        primary: true
                        onClicked: { Rexlink.rename(d.modelData.id, nameInput.text); page.renaming = ""; }
                    }
                    SButton {
                        visible: !d.editing && !d.modelData.current
                        text: I18n.tr("Make current")
                        onClicked: Rexlink.select(d.modelData.id)
                    }
                    SButton {
                        visible: !d.editing && d.modelData.online
                        icon: String.fromCodePoint(0xF08D3)
                        onClicked: Rexlink.ring(d.modelData.id)
                    }
                    SButton {
                        visible: !d.editing
                        icon: String.fromCodePoint(0xF03EB)  // pencil
                        onClicked: page.renaming = d.modelData.id
                    }
                    SButton {
                        visible: !d.editing
                        icon: Icons.trash
                        danger: true
                        onClicked: Rexlink.forget(d.modelData.id)
                    }
                }
            }
        }
    }

    // ── синхронизация
    SSection {
        visible: Rexlink.connected
        text: I18n.tr("Sync")
    }

    ColumnLayout {
        visible: Rexlink.connected
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: [
                { key: "notifications", icon: 0xF009A, title: "Phone notifications", desc: "Get notifications from the phone" },
                { key: "mirrorToDesktop", icon: 0xF0379, title: "Show them on the desktop", desc: "As regular pop-up notifications" },
                { key: "calls", icon: 0xF03F2, title: "Calls", desc: "Incoming call card with Answer / Decline" },
                { key: "sms", icon: 0xF0369, title: "Messages (SMS)", desc: "Read and send SMS from the PC" },
                { key: "clipboard", icon: 0xF014D, title: "Shared clipboard", desc: "Copy on one device — paste on the other" },
                { key: "clipboardImages", icon: 0xF02E9, title: "Images in clipboard", desc: "Also sync copied pictures" },
                { key: "media", icon: 0xF075A, title: "Phone media", desc: "Control what plays on the phone" },
                { key: "pcMedia", icon: 0xF0379, title: "PC media on phone", desc: "Control PC players from the phone" },
                { key: "autoUpdateDevices", icon: 0xF06B0, title: "Update the phone app", desc: "Install new app versions on devices automatically" },
            ]

            SCard {
                id: sc
                required property var modelData
                icon: String.fromCodePoint(modelData.icon)
                title: modelData.title
                desc: modelData.desc

                SSwitch {
                    checked: page.st[sc.modelData.key] ?? false
                    onToggled: v => Rexlink.set(sc.modelData.key, v)
                }
            }
        }
    }

    // ── файлы и камера
    SSection {
        visible: Rexlink.connected
        text: I18n.tr("Files & camera")
    }

    ColumnLayout {
        visible: Rexlink.connected
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: Icons.folder
            title: "Received files"
            desc: page.st.downloadDirResolved ?? ""

            SButton {
                text: I18n.tr("Open")
                onClicked: Quickshell.execDetached(["xdg-open", page.st.downloadDirResolved ?? Quickshell.env("HOME")])
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0100)
            title: "Phone as webcam"
            desc: page.st.webcamResolved ? `Virtual camera: ${page.st.webcamResolved}` : "Needs v4l2loopback (see Rexlink docs)"

            SChoice {
                options: [{ value: "front", label: "Front" }, { value: "back", label: "Back" }]
                current: page.st.camera?.facing ?? "front"
                onPicked: v => Rexlink.set("camera", { facing: v })
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0A30)
            title: "Webcam quality"

            SDropdown {
                minWidth: 190
                options: [
                    { value: "1280x720x30", label: "720p · 30 fps" },
                    { value: "1280x720x60", label: "720p · 60 fps" },
                    { value: "1920x1080x30", label: "1080p · 30 fps" },
                    { value: "1920x1080x60", label: "1080p · 60 fps" },
                ]
                current: `${page.st.camera?.width ?? 1920}x${page.st.camera?.height ?? 1080}x${page.st.camera?.fps ?? 60}`
                onPicked: v => {
                    const [w, h, f] = v.split("x").map(Number);
                    Rexlink.set("camera", { width: w, height: h, fps: f });
                }
            }
        }
    }

    // ── демонстрация экрана
    SSection { text: I18n.tr("Screen sharing") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: [
                { key: "phoneCastHideCalls", icon: 0xF03F2, title: "Hide calls from screencast",
                  desc: "Viewers see an empty spot instead of the incoming call card. You still see it" },
                { key: "phoneCastHideNotifs", icon: 0xF0209, title: "Hide phone notifications from screencast",
                  desc: "Phone notifications and the phone menu in the bar are blacked out for viewers" },
            ]

            SCard {
                id: cc
                required property var modelData
                icon: String.fromCodePoint(modelData.icon)
                title: modelData.title
                desc: modelData.desc

                SSwitch {
                    checked: Settings.moduleOn(cc.modelData.key, true)
                    onToggled: v => Settings.setModule(cc.modelData.key, v)
                }
            }
        }
    }

    // ── шелл
    SSection { text: I18n.tr("In the shell") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: [
                { key: "phone", def: true, icon: 0xF011C, title: "Phone in the bar", desc: "Battery and notifications; click for the phone menu, right-click to find it" },
                { key: "phonePercent", def: true, icon: 0xF0079, title: "Battery percent", desc: "Show the number next to the battery icon" },
                { key: "phoneOffline", def: false, icon: 0xF0318, title: "Show when offline", desc: "Keep the icon in the bar when the phone isn't connected" },
                { key: "phoneCalls", def: true, icon: 0xF03F2, title: "Incoming call card", desc: "Answer or decline calls from the desktop" },
            ]

            SCard {
                id: bc
                required property var modelData
                icon: String.fromCodePoint(modelData.icon)
                title: modelData.title
                desc: modelData.desc

                SSwitch {
                    checked: Settings.moduleOn(bc.modelData.key, bc.modelData.def)
                    onToggled: v => Settings.setModule(bc.modelData.key, v)
                }
            }
        }
    }
}
