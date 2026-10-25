import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// Телефон → главная: переключатель устройств, большая карточка устройства (состояние и быстрые действия),
// плееры, функции плитками, список устройств
ColumnLayout {
    id: home

    required property var page
    readonly property var me: page.me
    readonly property var s: page.s
    readonly property bool online: Rexlink.online

    spacing: 14

    // цвет функции: свой оттенок у каждой, яркость — под тему
    function hue(h) {
        return Qt.hsla(h, 0.6, Theme.isLight ? 0.45 : 0.68, 1);
    }
    function soft(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // ── устройства: «пилюли», если их несколько
    Flow {
        Layout.fillWidth: true
        visible: Rexlink.devices.length > 1
        spacing: 8

        Repeater {
            model: Rexlink.devices
            Rectangle {
                id: chip
                required property var modelData
                readonly property bool cur: !!modelData.current
                width: chipRow.implicitWidth + 28
                height: 38
                radius: 19
                color: cur ? home.soft(Theme.accent, 0.18) : chipArea.containsMouse ? Theme.surfaceHi : Theme.surface
                border.width: cur ? 1 : 0
                border.color: home.soft(Theme.accent, 0.6)
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Rexlink.kindIcon(chip.modelData.kind)
                        color: chip.cur ? Theme.accent : Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.iconSize
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.name
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: chip.cur
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: 7
                        radius: 4
                        color: chip.modelData.online ? "#7fc98a" : Theme.faint
                    }
                }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!chip.cur) Rexlink.select(chip.modelData.id)
                }
            }
        }
    }

    // ── обновление приложения на устройстве
    Rectangle {
        visible: home.online && !!home.me.update
        Layout.fillWidth: true
        implicitHeight: 58
        radius: 16
        color: home.soft(Theme.accent, 0.14)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 12
            spacing: 14
            Text {
                text: String.fromCodePoint(0xF01DA)
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 4
            }
            Text {
                Layout.fillWidth: true
                text: `${I18n.tr("New app version for the device")}: ${home.me.update ?? ""}   ·   ${I18n.tr("On the device")}: ${home.me.appVersion || I18n.tr("old version")}`
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            SButton {
                text: home.me.updating ? "Updating…" : "Update"
                primary: true
                enabled: !home.me.updating
                onClicked: Rexlink.updateDevice(home.me.id)
            }
        }
    }

    // ── карточка устройства
    Rectangle {
        visible: home.page.has
        Layout.fillWidth: true
        implicitHeight: heroCol.implicitHeight + 48
        radius: 22
        color: Theme.surface
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.tint(Theme.surface, home.soft(Theme.accent, home.online ? 0.16 : 0.04)) }
            GradientStop { position: 1; color: Theme.surface }
        }

        ColumnLayout {
            id: heroCol
            x: 24
            y: 24
            width: parent.width - 48
            spacing: 22

            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                // «устройство»
                Rectangle {
                    implicitWidth: 92
                    implicitHeight: 92
                    radius: 26
                    color: home.soft(Theme.accent, home.online ? 0.2 : 0.06)
                    Text {
                        anchors.centerIn: parent
                        text: Rexlink.kindIcon(home.me.kind)
                        color: home.online ? Theme.accent : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 46
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 6
                        width: 16
                        height: 16
                        radius: 8
                        color: home.online ? "#7fc98a" : Theme.faint
                        border.width: 3
                        border.color: Theme.surface
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: home.me.name ?? ""
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 11
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: home.online ? [home.me.model, home.me.address].filter(x => x).join("   ·   ")
                            : I18n.tr("Offline — connects by itself once it's on the same network")
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                    // состояние — «пилюли»
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: home.online
                        spacing: 8

                        component Pill: Rectangle {
                            id: pill
                            property string icon
                            property string text
                            property color tint: Theme.fg
                            property real progress: -1
                            property bool clickable: false
                            signal clicked
                            width: pillRow.implicitWidth + 24
                            height: 32
                            radius: 16
                            color: clickable && pillArea.containsMouse ? Theme.surfaceHi2 : Theme.surfaceHi
                            clip: true
                            Rectangle {
                                visible: pill.progress >= 0
                                width: parent.width * Math.max(0, Math.min(1, pill.progress))
                                height: parent.height
                                color: home.soft(pill.tint, 0.16)
                            }
                            Row {
                                id: pillRow
                                anchors.centerIn: parent
                                spacing: 7
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pill.icon
                                    color: pill.tint
                                    font.family: Theme.font
                                    font.pixelSize: Theme.iconSize - 1
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pill.text
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 2
                                }
                            }
                            MouseArea {
                                id: pillArea
                                anchors.fill: parent
                                enabled: pill.clickable
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pill.clicked()
                            }
                        }

                        Pill {
                            readonly property int lvl: home.s.battery ?? 0
                            icon: Rexlink.batteryIcon(lvl, home.s.charging)
                            text: `${lvl}%` + (home.s.charging ? `   ·   ${I18n.tr("charging")}` : home.s.temp ? `   ·   ${Number(home.s.temp).toFixed(0)}°C` : "")
                            tint: lvl <= 15 && !home.s.charging ? Theme.urgent : "#7fc98a"
                            progress: lvl / 100
                        }
                        Pill {
                            icon: home.s.net === "wifi" ? Rexlink.wifiIcon(home.s.wifi?.level) : home.s.net === "cell" ? Rexlink.cellIcon(home.s.cell?.level) : String.fromCodePoint(0xF092E)
                            text: home.s.net === "wifi" ? (home.s.wifi?.ssid || "Wi-Fi") : home.s.net === "cell" ? I18n.tr("Mobile data") : I18n.tr("No network")
                            tint: home.hue(0.58)
                        }
                        Pill {
                            visible: !!home.s.cell?.operator
                            icon: Rexlink.cellIcon(home.s.cell?.level)
                            text: `${home.s.cell?.operator ?? ""}${home.s.cell?.gen ? "   ·   " + home.s.cell.gen : ""}`
                            tint: home.hue(0.48)
                        }
                        Pill {
                            icon: String.fromCodePoint(0xF0565)
                            text: I18n.tr("secure connection")
                            tint: home.hue(0.33)
                        }
                    }
                }

                // найти и меню устройства
                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    spacing: 8
                    SButton {
                        visible: home.online
                        text: "Find"
                        icon: String.fromCodePoint(0xF08D3)
                        onClicked: Rexlink.ring(home.me.id)
                    }
                }
            }

            // быстрые действия — круглые кнопки с подписями
            RowLayout {
                visible: home.online
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [
                        { icon: 0xF0552, label: "Send files", h: 0.58, on: false, act: () => home.page.pickFiles() },
                        { icon: 0xF0379, label: "Show screen", h: 0.66, on: Rexlink.screen.running, act: () => { home.page.openTab("screen"); if (!Rexlink.screen.running) Rexlink.screenStart(); } },
                        { icon: 0xF05A0, label: Rexlink.camera.running ? "Stop webcam" : "Webcam", h: 0.0, on: Rexlink.camera.running, act: () => Rexlink.cameraToggle() },
                        { icon: 0xF014D, label: "Get clipboard", h: 0.76, on: false, act: () => Rexlink.clipboardPull() },
                        { icon: 0xF04F6, label: Rexlink.screen.display?.running ? "Stop monitor" : "Monitor", h: 0.12, on: !!Rexlink.screen.display?.running, act: () => Rexlink.displayToggle() },
                        { icon: 0xF0369, label: "Messages", h: 0.38, on: false, act: () => home.page.openTab("messages") },
                    ]
                    Item {
                        id: act
                        required property var modelData
                        readonly property color tint: home.hue(modelData.h)
                        Layout.fillWidth: true
                        implicitHeight: 92

                        Rectangle {
                            id: circle
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 56
                            height: 56
                            radius: 28
                            color: act.modelData.on ? act.tint : actArea.pressed ? home.soft(act.tint, 0.32) : actArea.containsMouse ? home.soft(act.tint, 0.26) : home.soft(act.tint, 0.16)
                            scale: actArea.pressed ? 0.94 : 1
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on scale { NumberAnimation { duration: Theme.animFast } }
                            Text {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(act.modelData.icon)
                                color: act.modelData.on ? Theme.bg : act.tint
                                font.family: Theme.font
                                font.pixelSize: Theme.iconSize + 6
                            }
                        }
                        Text {
                            anchors.top: circle.bottom
                            anchors.topMargin: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr(act.modelData.label)
                            elide: Text.ElideRight
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                        MouseArea {
                            id: actArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: act.modelData.act()
                        }
                    }
                }
            }
        }
    }

    // ── плееры: телефона и компьютера
    PhoneMedia {
        visible: home.online && !!Rexlink.media.active
        m: Rexlink.media
        source: Rexlink.kindName(home.me.kind)
        onCommand: (cmd, v) => Rexlink.mediaAction(cmd, "", v)
    }
    PhoneMedia {
        visible: !!Rexlink.pcMedia.active && home.page.st.pcMedia !== false && home.online
        m: Rexlink.pcMedia
        source: "Computer"
        seekable: false
        onCommand: (cmd, v) => Rexlink.pcMediaAction(cmd)
    }

    // ── функции — плитками
    Text {
        Layout.topMargin: 8
        text: I18n.tr("Features")
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize + 2
        font.bold: true
    }
    GridLayout {
        Layout.fillWidth: true
        columns: width > 760 ? 4 : width > 520 ? 3 : 2
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: home.page.sections
            Rectangle {
                id: ft
                required property var modelData
                readonly property real h: ({ notifications: 0.08, messages: 0.38, calls: 0.48, files: 0.58, clipboard: 0.76,
                                             camera: 0.0, screen: 0.66, options: -1 })[modelData.key] ?? -1
                readonly property color tint: h < 0 ? Theme.muted : home.hue(h)
                readonly property int badge: modelData.key === "notifications" ? Rexlink.notifs.length : 0
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 118
                radius: 18
                color: ftArea.pressed ? Theme.surfaceHi2 : ftArea.containsMouse ? Theme.surfaceHi : Theme.surface
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Rectangle {
                    x: 16
                    y: 16
                    width: 42
                    height: 42
                    radius: 14
                    color: home.soft(ft.tint, 0.16)
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(ft.modelData.icon)
                        color: ft.tint
                        font.family: Theme.font
                        font.pixelSize: Theme.iconSize + 4
                    }
                }
                Rectangle {
                    visible: ft.badge > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    width: Math.max(24, badgeText.implicitWidth + 14)
                    height: 24
                    radius: 12
                    color: ft.tint
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: ft.badge > 99 ? "99+" : String(ft.badge)
                        color: Theme.bg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: true
                    }
                }
                Column {
                    x: 16
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    width: parent.width - 32
                    spacing: 2
                    Text {
                        width: parent.width
                        text: I18n.tr(ft.modelData.label)
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr(ft.modelData.desc)
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
                MouseArea {
                    id: ftArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: home.page.openTab(ft.modelData.key)
                }
            }
        }
    }

    // ── устройства: одной группой
    Text {
        visible: Rexlink.devices.length > 0
        Layout.topMargin: 8
        text: I18n.tr("Devices")
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize + 2
        font.bold: true
    }
    Rectangle {
        visible: Rexlink.devices.length > 0
        Layout.fillWidth: true
        implicitHeight: devCol.implicitHeight
        radius: 18
        color: Theme.surface
        clip: true

        ColumnLayout {
            id: devCol
            width: parent.width
            spacing: 0

            Repeater {
                model: Rexlink.devices

                Item {
                    id: d
                    required property var modelData
                    required property int index
                    property bool editing: false
                    Layout.fillWidth: true
                    implicitHeight: 70

                    Rectangle {
                        visible: d.index > 0
                        x: 20
                        width: parent.width - 40
                        height: 1
                        color: Theme.surfaceHi
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 14
                        spacing: 14

                        Rectangle {
                            implicitWidth: 42
                            implicitHeight: 42
                            radius: 14
                            color: home.soft(d.modelData.online ? Theme.accent : Theme.dim, 0.14)
                            Text {
                                anchors.centerIn: parent
                                text: Rexlink.kindIcon(d.modelData.kind)
                                color: d.modelData.online ? Theme.accent : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.iconSize + 4
                            }
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
                                text: [I18n.tr(d.modelData.online ? "online" : "offline"), d.modelData.model,
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
        }
    }
}
