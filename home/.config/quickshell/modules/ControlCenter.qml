import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.services
import qs.settings

// центр управления (как в Windows 11): плитки, громкость, плеер, питание
ColumnLayout {
    id: root

    property bool active: false

    width: 380
    spacing: 12

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ── пользователь + кнопки
    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Rectangle {
            implicitWidth: 40
            implicitHeight: 40
            radius: 20
            color: Theme.accent

            Text {
                anchors.centerIn: parent
                text: I18n.tr((Quickshell.env("USER") ?? "?").charAt(0).toUpperCase())
                color: Theme.bg
                font.family: Theme.font
                font.pixelSize: 18
                font.bold: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            // fillWidth у текстов: иначе колонка не растягивается и кнопки не уходят вправо
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: I18n.tr(Quickshell.env("USER") ?? "")
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: Qt.locale(I18n.locale).toString(clock.date, "dddd, d MMMM")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }

        component RoundBtn: Rectangle {
            id: rb
            property string icon
            signal hit
            implicitWidth: 36
            implicitHeight: 36
            radius: 11
            color: rbArea.pressed ? Theme.surfaceHi2 : rbArea.containsMouse ? Theme.surfaceHi : Theme.surface

            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            Glyph {
                anchors.centerIn: parent
                text: rb.icon
                color: Theme.fg
            }
            MouseArea {
                id: rbArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: rb.hit()
            }
        }

        RoundBtn { icon: Icons.lock; onHit: Ui.afterClose(["qs", "ipc", "call", "idle", "lock"]) }
        RoundBtn { icon: String.fromCodePoint(0xF0493); onHit: Ui.openSettings("system") }
        RoundBtn { icon: String.fromCodePoint(0xF0425); onHit: Ui.afterClose(["qs", "ipc", "call", "power", "toggle"], 0.1) }
    }

    // ── плитки
    component Tile: Rectangle {
        id: tile
        property string icon
        property string label
        property string sub: ""
        property bool on: false
        signal hit

        Layout.fillWidth: true
        implicitHeight: 76
        radius: 14
        color: on ? Theme.accent : tileArea.pressed ? Theme.surfaceHi2 : tileArea.containsMouse ? Theme.surfaceHi : Theme.surface
        scale: tileArea.pressed ? 0.96 : 1

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 2

            Text {
                text: tile.icon
                color: tile.on ? Theme.bg : Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 3
            }
            Item { Layout.fillHeight: true }
            Text {
                Layout.fillWidth: true
                text: I18n.tr(tile.label)
                elide: Text.ElideRight
                color: tile.on ? Theme.bg : Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                visible: tile.sub !== ""
                text: I18n.tr(tile.sub)
                elide: Text.ElideRight
                color: tile.on ? Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.7) : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 4
            }
        }

        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.hit()
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 4
        columnSpacing: 8
        rowSpacing: 8

        Tile {
            icon: Notifs.dnd ? Icons.bellOff : Icons.bell
            label: "Focus"
            sub: Notifs.dnd ? "On" : "Off"
            on: Notifs.dnd
            onHit: Notifs.toggleDnd()
        }
        Tile {
            icon: String.fromCodePoint(0xF0176)
            label: "Awake"
            sub: Power.caffeine ? "On" : "Off"
            on: Power.caffeine
            onHit: Power.caffeine = !Power.caffeine
        }
        Tile {
            icon: String.fromCodePoint(0xF0594)
            label: "Dark"
            sub: Theme.palette.name
            on: Settings.scheme !== "light"
            onHit: Ui.toggleDark()
        }
        Tile {
            icon: String.fromCodePoint(0xF0335)
            label: "Night"
            sub: !NightLight.installed ? "Install" : NightLight.on ? `${Settings.nightLight.temp ?? 4500}K` : "Off"
            on: NightLight.on
            onHit: NightLight.installed ? NightLight.toggle() : NightLight.install()
        }
        Tile {
            icon: Icons.record
            label: "Record"
            sub: Recorder.recording ? Recorder.elapsedText : "Screen"
            on: Recorder.recording
            onHit: Recorder.recording ? Recorder.stop() : Ui.afterClose(["qs", "ipc", "call", "recorder", "toggle"], 0.1)
        }
        Tile {
            icon: String.fromCodePoint(0xF0104)
            label: "Snip"
            sub: "Region"
            onHit: Ui.afterClose(["niri", "msg", "action", "screenshot"])
        }
        Tile {
            icon: Icons.clipboard
            label: "Clipboard"
            sub: "History"
            onHit: Ui.afterClose(["qs", "ipc", "call", "clipboard", "toggle"], 0.1)
        }
        Tile {
            visible: Rexlink.connected && !!Rexlink.dev
            icon: Rexlink.kindIcon(Rexlink.dev?.kind)
            label: "Find phone"
            sub: Rexlink.online ? `${Rexlink.dev?.name ?? ""} · ${Rexlink.status.battery ?? "—"}%` : "Offline"
            on: Rexlink.dev?.ringing ?? false
            onHit: Rexlink.online ? Rexlink.ring() : Ui.openSettings("phone")
        }
        Tile {
            visible: !(Rexlink.connected && !!Rexlink.dev)
            icon: String.fromCodePoint(0xF0E09)
            label: "Wallpaper"
            sub: "Change"
            onHit: Ui.afterClose(["qs", "ipc", "call", "wallpaper", "toggle"], 0.1)
        }
    }

    // ── громкость и микрофон
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: volCol.implicitHeight + 20
        radius: 14
        color: Theme.surface

        ColumnLayout {
            id: volCol
            x: 14
            y: 10
            width: parent.width - 28
            spacing: 6

            VolumeRow {
                Layout.fillWidth: true
                node: Pipewire.defaultAudioSink
                meter: root.active
            }
            VolumeRow {
                Layout.fillWidth: true
                node: Pipewire.defaultAudioSource
                input: true
                meter: root.active
            }
        }
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }

    // ── плеер (если что-то играет)
    Rectangle {
        id: mediaCard
        visible: media.player !== null
        Layout.fillWidth: true
        implicitHeight: media.implicitHeight + 24
        radius: 14
        color: Theme.surface

        MediaWidget {
            id: media
            x: 12
            y: 12
            width: parent.width - 24
            artSize: 72
            active: root.active
        }
    }

    // ── сеть
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 44
        radius: 12
        color: netArea.containsMouse ? Theme.surfaceHi : Theme.surface

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10

            Text {
                text: I18n.tr(Net.type === "wifi" ? Icons.wifi : Net.type === "ethernet" ? Icons.ethernet : Icons.offline)
                color: Net.type === "none" ? Theme.urgent : Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.iconSize
            }
            Text {
                Layout.fillWidth: true
                text: Net.type === "none" ? "Disconnected" : `${Net.type === "wifi" ? "Wi-Fi" : "Ethernet"} · ${Net.iface}`
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                text: `${Icons.down} ${Net.formatSpeed(Net.rxSpeed)}   ${Icons.up} ${Net.formatSpeed(Net.txSpeed)}`
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }

        MouseArea {
            id: netArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Ui.openSettings("network")
        }
    }
}
