import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// Система: имя компьютера, железо, быстрые переходы
Page {
    id: page

    title: "System"
    signal openPage(int index)
    property int aboutIndex: 0

    property var info: ({})

    Component.onCompleted: sysinfo.running = true

    Process {
        id: sysinfo
        command: ["sh", "-c", `
            . /etc/os-release
            echo "os=$PRETTY_NAME"
            echo "kernel=$(uname -r)"
            echo "host=$(cat /etc/hostname 2>/dev/null || uname -n)"
            echo "user=$USER"
            echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
            echo "gpu=$(lspci 2>/dev/null | grep -m1 -E 'VGA|3D' | sed 's/.*: //; s/ (rev.*//')"
            echo "ram=$(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
            echo "disk=$(df -h / | awk 'NR==2{print $3" / "$2" used ("$5")"}')"
            echo "diskp=$(df / | awk 'NR==2{print $5}' | tr -d %)"
            echo "uptime=$(uptime -p | sed 's/^up //')"
            echo "shell=$(basename "$SHELL")"
            echo "wm=niri $(niri --version 2>/dev/null | awk '{print $2}')"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const l of text.split("\n")) {
                    const i = l.indexOf("=");
                    if (i > 0) o[l.slice(0, i)] = l.slice(i + 1);
                }
                page.info = o;
            }
        }
    }

    // ── «герой»: пользователь и компьютер
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 110
        radius: 12
        color: Theme.surface

        RowLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 18

            Rectangle {
                implicitWidth: 64
                implicitHeight: 64
                radius: 32
                color: Theme.accent

                Text {
                    anchors.centerIn: parent
                    text: (page.info.user ?? "?").charAt(0).toUpperCase()
                    color: Theme.bg
                    font.family: Theme.font
                    font.pixelSize: 28
                    font.bold: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    text: `${page.info.user ?? ""}@${page.info.host ?? ""}`
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 5
                    font.bold: true
                }
                Text {
                    text: `${page.info.os ?? ""}  ·  ${page.info.wm ?? ""}  ·  ${page.info.shell ?? ""}`
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                Text {
                    text: page.info.uptime ? `up ${page.info.uptime}` : ""
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }

    // ── быстрые переходы
    GridLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        columns: 3
        columnSpacing: 8
        rowSpacing: 8

        Repeater {
            model: [
                { page: 1, icon: 0xF0379, title: "Display", desc: Object.keys(NiriSettings.live).join(" · ") || "Monitors" },
                { page: 2, icon: 0xF057E, title: "Sound", desc: "Devices and apps" },
                { page: 3, icon: 0xF0200, title: "Network", desc: Net.type === "none" ? "Disconnected" : `${Net.type} · ${Net.iface}` },
                { page: 7, icon: 0xF03D8, title: "Personalization", desc: Theme.palette.name },
                { page: 10, icon: 0xF0FB0, title: "Peripherals", desc: Devices.list.length ? Devices.list.map(d => d.name).slice(0, 2).join(" · ") : "Keyboard, mouse, tablet, gamepads" },
                { page: 15, icon: 0xF009A, title: "Notifications", desc: Notifs.dnd ? "Do not disturb" : "On" },
            ]

            Rectangle {
                id: qt
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 74
                radius: 10
                color: qtArea.containsMouse ? Theme.surfaceHi : Theme.surface

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    Text {
                        text: String.fromCodePoint(qt.modelData.icon)
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.iconSize + 6
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: I18n.tr(qt.modelData.title)
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr(qt.modelData.desc)
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }

                MouseArea {
                    id: qtArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.openPage(qt.modelData.page)
                }
            }
        }
    }

    SCard {
        Layout.topMargin: 8
        icon: String.fromCodePoint(0xF02FD)
        title: "About this PC"
        desc: "Device name, account and specifications"
        clickable: true
        onClicked: page.openPage(page.aboutIndex)
    }

    SSection { text: I18n.tr("Shell") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF0450)
            title: "Restart shell"
            desc: "Reload the bar and all menus"
            clickable: true
            onClicked: Quickshell.execDetached(["sh", "-c", "pkill -x qs; sleep 0.3; setsid -f qs"])
        }
        SCard {
            icon: String.fromCodePoint(0xF0B85)
            title: "Open niri config"
            desc: "~/.config/niri/config.kdl"
            clickable: true
            onClicked: Quickshell.execDetached(["foot", "nvim", `${Quickshell.env("HOME")}/.config/niri/config.kdl`])
        }
    }
}
