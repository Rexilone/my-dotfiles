import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// Бар: высота, часы, воркспейсы, модули
ColumnLayout {
    Layout.fillWidth: true
    spacing: 6

    SSection { text: I18n.tr("Style") }

    Flow {
        Layout.fillWidth: true
        spacing: 10

        Repeater {
            model: [
                { value: "flat", label: "Solid" },
                { value: "floating", label: "Floating" },
                { value: "pills", label: "Pills" },
            ]

            Rectangle {
                id: st
                required property var modelData
                readonly property bool selected: Settings.barStyle === modelData.value

                width: 200
                height: 96
                radius: 12
                color: Theme.surface
                border.width: selected ? 2 : 1
                border.color: selected ? Theme.accent : stArea.containsMouse ? Theme.line : Theme.surfaceHi2

                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                // мини-превью бара
                Rectangle {
                    x: 10
                    y: 10
                    width: parent.width - 20
                    height: 44
                    radius: 8
                    color: Theme.bg
                    clip: true

                    Rectangle {
                        visible: st.modelData.value === "flat"
                        width: parent.width
                        height: 10
                        color: Theme.surfaceHi2
                    }
                    Rectangle {
                        visible: st.modelData.value === "floating"
                        x: 6
                        y: 5
                        width: parent.width - 12
                        height: 10
                        radius: 4
                        color: Theme.surfaceHi2
                    }
                    Row {
                        visible: st.modelData.value === "pills"
                        x: 6
                        y: 5
                        spacing: 0
                        Rectangle { width: 36; height: 10; radius: 5; color: Theme.surfaceHi2 }
                        Item { width: 36; height: 1 }
                        Rectangle { width: 40; height: 10; radius: 5; color: Theme.surfaceHi2 }
                        Item { width: 22; height: 1 }
                        Rectangle { width: 30; height: 10; radius: 5; color: Theme.surfaceHi2 }
                    }
                }

                Text {
                    x: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 11
                    text: I18n.tr(st.modelData.label)
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: st.selected
                }

                MouseArea {
                    id: stArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Settings.barStyle = st.modelData.value
                }
            }
        }
    }

    SSection { text: I18n.tr("Show the bar on") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: Quickshell.screens

            SCard {
                id: sc
                required property ShellScreen modelData
                readonly property bool on: Settings.barOn.includes(modelData.name)

                icon: String.fromCodePoint(0xF0379)
                title: modelData.name + (modelData.name === Settings.primary ? "   ·   main display" : "")
                desc: `${modelData.width}×${modelData.height}`

                SSwitch {
                    checked: sc.on
                    // хотя бы один монитор с баром
                    enabled: !(sc.on && Settings.barOn.length === 1)
                    opacity: enabled ? 1 : 0.4
                    onToggled: v => {
                        const cur = Settings.barOn.slice();
                        Settings.barScreens = v ? cur.concat([sc.modelData.name]) : cur.filter(n => n !== sc.modelData.name);
                    }
                }
            }
        }
    }

    SSection { text: I18n.tr("Layout") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF0E14)  // arrow-expand-vertical
            title: "Height"

            SSlider {
                from: 26
                to: 44
                step: 1
                value: Settings.barHeight
                suffix: " px"
                onMoved: v => Settings.barHeight = Math.round(v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0954)
            title: "Clock format"
            desc: "Shown in the center of the bar"

            SDropdown {
                minWidth: 230
                options: [
                    { value: "dddd HH:mm", label: "Friday 15:00" },
                    { value: "HH:mm", label: "15:00" },
                    { value: "HH:mm:ss", label: "15:00:42" },
                    { value: "ddd d MMM  HH:mm", label: "Fri 3 Oct  15:00" },
                    { value: "dddd, d MMMM  HH:mm", label: "Friday, 3 October  15:00" },
                    { value: "h:mm AP", label: "3:00 PM" },
                ]
                current: Settings.clockFormat
                onPicked: v => Settings.clockFormat = v
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0570)  // view-dashboard-outline
            title: "Workspaces"
            desc: "How workspaces look on the left"

            SChoice {
                options: [{ value: "dots", label: "Dots" }, { value: "numbers", label: "Numbers" }]
                current: Settings.workspaceStyle
                onPicked: v => Settings.workspaceStyle = v
            }
        }

        SCard {
            visible: Settings.module("tray")
            icon: String.fromCodePoint(0xF003B)  // apps
            title: "Tray apps"
            desc: Settings.trayMode === "menu"
                ? "In a menu behind a button; pinned apps stay in the bar (pin them in the menu)"
                : "All app icons right in the bar"

            SChoice {
                options: [{ value: "inline", label: "In the bar" }, { value: "menu", label: "In a menu" }]
                current: Settings.trayMode
                onPicked: v => Settings.trayMode = v
            }
        }
    }

    SSection { text: I18n.tr("Modules") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: [
                { key: "launcher", def: true, icon: 0xF08C7, title: "App launcher", desc: "Button at the very left that opens the app menu (Super+D)" },
                { key: "control", def: true, icon: 0xF062E, title: "Control center", desc: "Quick toggles, volume, media and power in one menu" },
                { key: "window", def: false, icon: 0xF05AF, title: "Active window", desc: "Title and icon of the focused window" },
                { key: "media", def: false, icon: 0xF075A, title: "Now playing", desc: "Track and play/pause; click opens the player" },
                { key: "weather", def: false, icon: 0xF0595, title: "Weather", desc: "Temperature next to the clock" },
                { key: "stats", def: false, icon: 0xF061A, title: "CPU & RAM", desc: "Load at a glance; click opens system stats" },
                { key: "updates", def: false, icon: 0xF06B0, title: "System updates", desc: "Shows available pacman updates; click to update" },
                { key: "phone", def: true, icon: 0xF011C, title: "Phone (Rexlink)", desc: "Battery and notifications of your phone; click for the phone menu" },
                { key: "castHidden", def: true, icon: 0xF0209, title: "Hidden from screencast", desc: "Shown while apps are hidden with Super+G; click for the list" },
                { key: "tray", icon: 0xF0DCA, title: "System tray", desc: "App icons" },
                { key: "keyboard", icon: 0xF030C, title: "Keyboard layout", desc: "en / ru indicator" },
                { key: "volume", icon: 0xF057E, title: "Volume", desc: "Speaker and mixer" },
                { key: "mic", icon: 0xF036C, title: "Microphone", desc: "Mic level and mute" },
                { key: "network", icon: 0xF0200, title: "Network", desc: "Connection and speed" },
                { key: "notifications", icon: 0xF009A, title: "Notifications", desc: "Bell and notification list" },
            ]

            SCard {
                id: mc
                required property var modelData
                icon: String.fromCodePoint(modelData.icon)
                title: modelData.title
                desc: modelData.desc

                SButton {
                    visible: mc.modelData.key === "updates" && !Updates.installed
                    text: I18n.tr("Install")
                    onClicked: Updates.install()
                }
                SSwitch {
                    checked: Settings.moduleOn(mc.modelData.key, mc.modelData.def ?? true)
                    onToggled: v => Settings.setModule(mc.modelData.key, v)
                }
            }
        }
    }
}
