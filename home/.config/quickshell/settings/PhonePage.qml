import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// Телефон (Rexlink): служба — часть системы, окна нет — весь интерфейс здесь.
// Главная: устройство, состояние, медиа, устройства; подстраницы — по функциям.
Page {
    id: page

    title: "Phone"
    subtitle: tab === "home" ? "Rexlink — notifications, messages, calls, files, clipboard, webcam and screen of your Android devices" : ""
    crumb: tab === "home" ? "" : (sections.find(t => t.key === tab)?.label ?? "")
    onBack: openTab("home")

    property string tab: "home"
    readonly property bool fullHeight: tab === "messages" || tab === "screen"
    // высота подстраниц во всю высоту окна (переписка, экран устройства)
    readonly property real fillHeight: Math.max(420, page.height - 118)

    interactive: !fullHeight

    readonly property var st: Rexlink.settings
    readonly property var s: Rexlink.status
    readonly property bool has: Rexlink.connected && !!Rexlink.dev
    readonly property var me: Rexlink.dev ?? ({})

    function can(cap) { return (Rexlink.caps ?? []).includes(cap); }

    readonly property var sections: [
        { key: "notifications", label: "Notifications", icon: 0xF009A,
          desc: Rexlink.notifs.length ? `${Rexlink.notifs.length} ${I18n.plural(Rexlink.notifs.length, "notification", "notifications", "уведомление", "уведомления", "уведомлений")}` : "No notifications" },
        { key: "messages", label: "Messages", icon: 0xF0369, desc: "SMS: conversations, replies, new messages" },
        { key: "calls", label: "Calls", icon: 0xF03F2,
          desc: Rexlink.call.state === "ringing" ? `${I18n.tr("Incoming")}: ${Rexlink.call.name || Rexlink.call.number}` : "Answer and decline, dial a number" },
        { key: "files", label: "Files", icon: 0xF0256,
          desc: Rexlink.transfers.some(t => t.state === "active") ? "Transferring…" : "Send files to the device and receive them from it" },
        { key: "clipboard", label: "Clipboard", icon: 0xF014D, desc: page.st.clipboard ? "Shared   ·   text and images both ways" : "Off" },
        { key: "camera", label: "Webcam", icon: 0xF05A0, desc: Rexlink.camera.running ? "On" : "The device camera as a webcam for calls and OBS" },
        { key: "screen", label: "Device screen", icon: 0xF0379, desc: Rexlink.screen.running ? "Showing" : "See and control the device screen with mouse and keyboard" },
        { key: "options", label: "Rexlink settings", icon: 0xF0493, desc: "Sync, screen quality, files folder, bar, screencast" },
    ]

    function openTab(key) {
        tab = key;
        contentY = 0;
    }

    // Rexlink.show("files") и т.п. — открыть вкладку
    function takeTab() {
        if (Ui.phoneTab) {
            openTab(sections.some(x => x.key === Ui.phoneTab) ? Ui.phoneTab : "home");
            Ui.phoneTab = "";
        }
    }
    Component.onCompleted: takeTab()
    Connections {
        target: Ui
        function onPhoneTabChanged() { page.takeTab(); }
    }

    // ── подсказки службы («SMS отправлено», «Файл получен»…)
    property string toastText: ""
    Connections {
        target: Rexlink
        function onToast(text) {
            page.toastText = text;
            toastTimer.restart();
        }
    }
    Timer {
        id: toastTimer
        interval: 3200
        onTriggered: page.toastText = ""
    }

    Rectangle {
        parent: page
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: page.toastText ? 22 : 8
        implicitWidth: Math.min(page.width - 80, toastLabel.implicitWidth + 36)
        implicitHeight: 40
        radius: 10
        color: Theme.surfaceHi
        border.width: 1
        border.color: Theme.surfaceHi2
        opacity: page.toastText ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 180 } }

        Text {
            id: toastLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, page.width - 116)
            text: page.toastText
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
    }

    // ═════════════════════════ общее для всех вкладок: служба, файрвол, сопряжение
    SCard {
        visible: !Rexlink.connected
        icon: String.fromCodePoint(0xF011C)
        title: Rexlink.installed ? "Rexlink service is not running" : "Rexlink service is not set up"
        desc: Dotfiles.missingPackages.length > 0 ? `${I18n.tr("Install the missing packages first")}: ${Dotfiles.missingPackages.join(", ")}`
            : Rexlink.installed ? "Start it to connect your devices (rexlink.service)" : "Run ./install.sh from the dotfiles folder — it sets up rexlink.service"

        SButton {
            visible: Dotfiles.missingPackages.length > 0
            text: "Install packages"
            primary: true
            onClicked: Dotfiles.installPackages()
        }
        SButton {
            visible: Rexlink.installed && Dotfiles.missingPackages.length === 0
            text: "Start"
            primary: true
            onClicked: Rexlink.start()
        }
        SButton {
            visible: !Rexlink.installed
            text: "Check again"
            onClicked: Rexlink.detect()
        }
    }

    // файрвол закрывает порты — устройства найдут ПК, но не подключатся
    Rectangle {
        visible: Rexlink.connected && page.st.firewall?.blocked === true
        Layout.fillWidth: true
        implicitHeight: fwRow.implicitHeight + 28
        radius: 10
        color: Qt.rgba(Theme.urgent.r, Theme.urgent.g, Theme.urgent.b, 0.12)
        border.width: 1
        border.color: Theme.urgent

        RowLayout {
            id: fwRow
            x: 18
            y: 14
            width: parent.width - 36
            spacing: 16

            Text {
                text: String.fromCodePoint(0xF0565)
                color: Theme.urgent
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 4
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: `${I18n.tr("The firewall blocks Rexlink")} (${page.st.firewall?.tool ?? ""})`
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: I18n.tr("Devices see the computer but can't connect. Open TCP 47820 and UDP 47821")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
            SButton {
                visible: page.st.firewall?.tool === "ufw"
                text: "Open ports"
                primary: true
                onClicked: Rexlink.openFirewall()
            }
        }
    }

    // запрос сопряжения
    Rectangle {
        visible: !!Rexlink.pairing.id
        Layout.fillWidth: true
        implicitHeight: 76
        radius: 10
        color: Theme.surfaceHi
        border.width: 1
        border.color: Theme.accent

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 14

            Text {
                text: String.fromCodePoint(0xF0337)
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 6
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: `${Rexlink.pairing.name ?? ""} ${I18n.tr("wants to pair")}`
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                Text {
                    text: I18n.tr("Check that the code matches the device")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
            Text {
                text: (Rexlink.pairing.code ?? "").replace(/(\d{3})(\d{3})/, "$1 $2")
                color: Theme.fg
                font.family: Settings.monoFont || Theme.font
                font.pixelSize: Theme.fontSize + 8
                font.bold: true
                font.letterSpacing: 2
            }
            SButton { text: "Decline"; onClicked: Rexlink.pairAnswer(false) }
            SButton { text: "Pair"; primary: true; onClicked: Rexlink.pairAnswer(true) }
        }
    }

    // ═════════════════════════ главная
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.tab === "home" && Rexlink.connected
        spacing: 6

        // обновление приложения на устройстве
        SCard {
            visible: Rexlink.online && !!page.me.update
            icon: String.fromCodePoint(0xF01DA)
            title: `${I18n.tr("New app version for the device")}: ${page.me.update ?? ""}`
            desc: `${I18n.tr("On the device")}: ${page.me.appVersion || I18n.tr("old version")}`

            SButton {
                text: page.me.updating ? "Updating…" : "Update"
                primary: true
                enabled: !page.me.updating
                onClicked: Rexlink.updateDevice(page.me.id)
            }
        }

        // ── устройство: имя, адрес, состояние
        Rectangle {
            visible: page.has
            Layout.fillWidth: true
            implicitHeight: heroCol.implicitHeight + 36
            radius: 12
            color: Theme.surface

            ColumnLayout {
                id: heroCol
                x: 20
                y: 18
                width: parent.width - 40
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Rectangle {
                        implicitWidth: 52
                        implicitHeight: 52
                        radius: 14
                        color: Theme.surfaceHi
                        Text {
                            anchors.centerIn: parent
                            text: Rexlink.kindIcon(page.me.kind)
                            color: Rexlink.online ? Theme.accent : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 28
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: page.me.name ?? ""
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 5
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: Rexlink.online ? [page.me.model, page.me.address, I18n.tr("secure connection")].filter(x => x).join("   ·   ")
                                : I18n.tr("Offline — connects by itself once it's on the same network")
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                    SButton {
                        visible: Rexlink.online
                        text: "Find"
                        icon: String.fromCodePoint(0xF08D3)
                        onClicked: Rexlink.ring(page.me.id)
                    }
                }

                // плитки состояния
                RowLayout {
                    visible: Rexlink.online
                    Layout.fillWidth: true
                    spacing: 8

                    component Tile: Rectangle {
                        id: tile
                        property string icon
                        property string value
                        property string label
                        property real progress: -1
                        property color tint: Theme.accent
                        property bool clickable: false
                        signal clicked

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 84
                        radius: 10
                        color: clickable && tileArea.containsMouse ? Theme.surfaceHi2 : Theme.surfaceHi

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 2
                            Text {
                                text: tile.icon
                                color: tile.tint
                                font.family: Theme.font
                                font.pixelSize: Theme.iconSize + 2
                            }
                            Item { Layout.fillHeight: true }
                            Text {
                                Layout.fillWidth: true
                                text: tile.value
                                elide: Text.ElideRight
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize + 1
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                text: tile.label
                                elide: Text.ElideRight
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 3
                            }
                        }
                        Rectangle {
                            visible: tile.progress >= 0
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 1
                            width: (parent.width - 2) * Math.max(0, Math.min(1, tile.progress))
                            height: 3
                            radius: 2
                            color: tile.tint
                        }
                        MouseArea {
                            id: tileArea
                            anchors.fill: parent
                            enabled: tile.clickable
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tile.clicked()
                        }
                    }

                    Tile {
                        readonly property int lvl: page.s.battery ?? 0
                        icon: Rexlink.batteryIcon(lvl, page.s.charging)
                        value: `${lvl}%`
                        label: page.s.charging ? I18n.tr(({ ac: "Charging · mains", usb: "Charging · USB", wireless: "Charging · wireless" })[page.s.plug] ?? "Charging")
                            : page.s.temp ? `${I18n.tr("Battery")} · ${Number(page.s.temp).toFixed(1)}°C` : I18n.tr("Battery")
                        progress: lvl / 100
                        tint: lvl <= 15 && !page.s.charging ? Theme.urgent : Theme.accent
                    }
                    Tile {
                        icon: page.s.net === "wifi" ? Rexlink.wifiIcon(page.s.wifi?.level) : page.s.net === "cell" ? Rexlink.cellIcon(page.s.cell?.level) : String.fromCodePoint(0xF092E)
                        value: page.s.net === "wifi" ? (page.s.wifi?.ssid || "Wi-Fi") : page.s.net === "cell" ? (page.s.cell?.operator || I18n.tr("Mobile network")) : I18n.tr("No network")
                        label: page.s.net === "wifi" ? `Wi-Fi · ${page.s.wifi?.level ?? 0}/4` : page.s.net === "cell" ? `${page.s.cell?.gen ?? ""} · ${page.s.cell?.level ?? 0}/4` : I18n.tr("Offline")
                    }
                    Tile {
                        visible: page.can("calls") || !!page.s.cell?.operator
                        icon: Rexlink.cellIcon(page.s.cell?.level)
                        value: page.s.cell?.operator || I18n.tr("No SIM")
                        label: page.s.cell?.operator ? `${page.s.cell?.gen ?? ""} · ${page.s.cell?.level ?? 0}/4` : I18n.tr("Cellular")
                        tint: Theme.muted
                    }
                    Tile {
                        icon: String.fromCodePoint(0xF009A)
                        value: String(Rexlink.notifs.length)
                        label: I18n.plural(Rexlink.notifs.length, "notification", "notifications", "уведомление", "уведомления", "уведомлений")
                        clickable: true
                        onClicked: page.openTab("notifications")
                    }
                }

                // быстрые действия
                RowLayout {
                    visible: Rexlink.online
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { icon: 0xF0552, label: "Send files", act: () => page.pickFiles() },
                            { icon: 0xF0379, label: "Show screen", act: () => { page.openTab("screen"); if (!Rexlink.screen.running) Rexlink.screenStart(); } },
                            { icon: 0xF05A0, label: Rexlink.camera.running ? "Stop webcam" : "Webcam", act: () => Rexlink.cameraToggle() },
                            { icon: 0xF014D, label: "Get clipboard", act: () => Rexlink.clipboardPull() },
                        ]
                        SButton {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            icon: String.fromCodePoint(modelData.icon)
                            text: modelData.label
                            onClicked: modelData.act()
                        }
                    }
                }
            }
        }

        // ── медиа
        PhoneMedia {
            visible: Rexlink.online && !!Rexlink.media.active
            m: Rexlink.media
            source: Rexlink.kindName(page.me.kind)
            onCommand: (cmd, v) => Rexlink.mediaAction(cmd, "", v)
        }
        PhoneMedia {
            visible: !!Rexlink.pcMedia.active && page.st.pcMedia !== false && Rexlink.online
            m: Rexlink.pcMedia
            source: "Computer"
            seekable: false
            onCommand: (cmd, v) => Rexlink.pcMediaAction(cmd)
        }

        // ── как подключить
        Rectangle {
            visible: Rexlink.devices.length === 0
            Layout.fillWidth: true
            implicitHeight: howto.implicitHeight + 36
            radius: 12
            color: Theme.surface

            ColumnLayout {
                id: howto
                x: 20
                y: 18
                width: parent.width - 40
                spacing: 10

                Text {
                    text: I18n.tr("How to connect")
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
                Repeater {
                    model: [
                        I18n.tr("Install the Rexlink app on the phone, tablet or watch (the APK is below) and open it. Any number of devices works."),
                        I18n.tr("The device and the computer must be on the same network (Wi-Fi or hotspot)."),
                        `${I18n.tr("Pick")} «${page.st.name ?? ""}» ${I18n.tr("in the list or enter the address")}: ${(page.st.ips ?? []).join(", ")}`,
                        I18n.tr("Check the six-digit code on both screens and press Pair."),
                    ]
                    RowLayout {
                        id: stepRow
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 22
                            implicitHeight: 22
                            radius: 11
                            color: Theme.surfaceHi2
                            Text {
                                anchors.centerIn: parent
                                text: stepRow.index + 1
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 3
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: stepRow.modelData
                            wrapMode: Text.Wrap
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }
                    }
                }
            }
        }

        SCard {
            visible: Rexlink.devices.length === 0
            icon: String.fromCodePoint(0xF0032)
            title: "App for the device"
            desc: Rexlink.apk.versionName ? `rexlink.apk   ·   ${I18n.tr("version")} ${Rexlink.apk.versionName}   ·   ${I18n.tr("send it to the phone or install with adb install")}`
                : "rexlink.apk not found next to the service"

            SButton {
                visible: !!Rexlink.apk.versionName
                text: "Show file"
                icon: Icons.folder
                onClicked: Quickshell.execDetached(["sh", "-c", 'xdg-open "$(dirname "$(readlink -f "$HOME/.local/bin/rexlink")")/../../../rexlink"'])
            }
        }

        // ── устройства
        SSection {
            visible: Rexlink.devices.length > 0
            text: I18n.tr("Devices")
        }

        Repeater {
            model: Rexlink.devices

            Rectangle {
                id: d
                required property var modelData
                property bool editing: false

                Layout.fillWidth: true
                implicitHeight: 64
                radius: 10
                color: Theme.surface
                border.width: modelData.current ? 1 : 0
                border.color: Theme.accent

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
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
                        visible: !d.editing
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: d.modelData.name + (d.modelData.current ? `   ·   ${I18n.tr("current")}` : "")
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            font.bold: d.modelData.current
                        }
                        Text {
                            Layout.fillWidth: true
                            text: [I18n.tr(Rexlink.kindName(d.modelData.kind)), d.modelData.model,
                                   I18n.tr(d.modelData.online ? "online" : "offline"),
                                   d.modelData.battery >= 0 ? `${d.modelData.battery}%${d.modelData.charging ? " ⚡" : ""}` : "",
                                   d.modelData.appVersion ? `Rexlink ${d.modelData.appVersion}` : ""].filter(x => x).join("  ·  ")
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }

                    SField {
                        id: nameField
                        visible: d.editing
                        onAccepted: { Rexlink.rename(d.modelData.id, text); d.editing = false; }
                        input.Keys.onEscapePressed: d.editing = false
                    }

                    SButton {
                        visible: !d.editing && !!d.modelData.update && d.modelData.online
                        text: d.modelData.updating ? "Updating…" : `${I18n.tr("Update to")} ${d.modelData.update}`
                        enabled: !d.modelData.updating
                        onClicked: Rexlink.updateDevice(d.modelData.id)
                    }
                    SButton {
                        visible: !d.editing && !d.modelData.current
                        text: "Make current"
                        onClicked: Rexlink.select(d.modelData.id)
                    }
                    SButton {
                        visible: !d.editing && d.modelData.online
                        icon: String.fromCodePoint(0xF08D3)
                        onClicked: Rexlink.ring(d.modelData.id)
                    }
                    SButton {
                        icon: String.fromCodePoint(d.editing ? 0xF012C : 0xF03EB)
                        primary: d.editing
                        onClicked: {
                            if (d.editing) Rexlink.rename(d.modelData.id, nameField.text);
                            else {
                                nameField.text = d.modelData.name;
                                nameField.focusInput();
                            }
                            d.editing = !d.editing;
                        }
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

        // ── разделы
        SSection { text: I18n.tr("Features") }

        Repeater {
            model: page.sections
            SCard {
                required property var modelData
                icon: String.fromCodePoint(modelData.icon)
                title: modelData.label
                desc: modelData.desc
                clickable: true
                onClicked: page.openTab(modelData.key)
            }
        }
    }

    // ═════════════════════════ подстраницы
    PhoneNotifsTab { visible: page.tab === "notifications" }
    PhoneMessagesTab { visible: page.tab === "messages"; active: visible; Layout.preferredHeight: page.fillHeight }
    PhoneCallsTab { visible: page.tab === "calls" }
    PhoneFilesTab { id: filesTab; visible: page.tab === "files"; onPick: page.pickFiles() }
    PhoneClipboardTab { visible: page.tab === "clipboard" }
    PhoneCameraTab { visible: page.tab === "camera"; active: visible }
    PhoneScreenTab { visible: page.tab === "screen"; active: visible; Layout.preferredHeight: page.fillHeight }
    PhoneOptionsTab { visible: page.tab === "options" }

    // ── выбор файлов: yazi в терминале (Enter / Space — выбрать, затем Enter)
    function pickFiles() {
        if (!Rexlink.online || picker.running) return;
        picker.running = true;
    }
    Process {
        id: picker
        command: ["sh", "-c", 'f=$(mktemp); foot --app-id=rexlink-pick --title="Rexlink" yazi --chooser-file="$f" "$HOME" >/dev/null 2>&1; cat "$f"; rm -f "$f"']
        stdout: StdioCollector {
            onStreamFinished: {
                const paths = text.split("\n").filter(x => x.trim());
                if (paths.length) {
                    Rexlink.sendFiles(paths);
                    page.openTab("files");
                }
            }
        }
    }

    // файлы можно бросить на страницу
    DropArea {
        parent: page
        anchors.fill: parent
        z: 5
        enabled: Rexlink.online && page.tab !== "screen"
        onDropped: drop => {
            if (!drop.hasUrls) return;
            Rexlink.sendFiles(drop.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))));
            page.openTab("files");
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 16
            visible: parent.containsDrag
            radius: 14
            color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.85)
            border.width: 2
            border.color: Theme.accent

            Column {
                anchors.centerIn: parent
                spacing: 10
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: String.fromCodePoint(0xF0552)
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 48
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: `${I18n.tr("Drop to send to")} ${page.me.name ?? ""}`
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 2
                }
            }
        }
    }
}
