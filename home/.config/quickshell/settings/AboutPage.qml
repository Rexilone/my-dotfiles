import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// О системе: устройство, учётная запись, оболочка, характеристики
Page {
    id: page

    title: "About"

    readonly property string shellName: "Rexilone Shell"
    readonly property string version: Dotfiles.version
    readonly property string author: "Rexilone"

    property var info: ({})
    property bool renaming: false

    function refresh() {
        sysinfo.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: sysinfo
        command: ["sh", "-c", `
            . /etc/os-release
            echo "os=$PRETTY_NAME"
            echo "kernel=$(uname -r)"
            echo "arch=$(uname -m)"
            echo "host=$(hostnamectl hostname 2>/dev/null || cat /etc/hostname)"
            echo "model=$(cat /sys/devices/virtual/dmi/id/board_vendor 2>/dev/null) $(cat /sys/devices/virtual/dmi/id/board_name 2>/dev/null)"
            echo "user=$USER"
            echo "fullname=$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1)"
            echo "admin=$(id -nG | tr ' ' '\\n' | grep -qx wheel && echo yes || echo no)"
            echo "since=$(stat -c %w / 2>/dev/null | cut -d' ' -f1)"
            echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
            echo "cores=$(nproc)"
            echo "gpu=$(lspci 2>/dev/null | grep -m1 -E 'VGA|3D' | sed 's/.*: //; s/ (rev.*//')"
            echo "vram=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1 | awk '{printf "%.0f GB", $1/1073741824}')"
            echo "ram=$(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
            echo "disk=$(df -h / | awk 'NR==2{print $3" of "$2" used"}')"
            echo "diskp=$(df / | awk 'NR==2{print $5}' | tr -d %)"
            echo "uptime=$(uptime -p | sed 's/^up //')"
            echo "qs=$(qs --version 2>/dev/null | head -1 | awk '{print $2}')"
            echo "niri=$(niri --version 2>/dev/null | awk '{print $2}')"
            echo "shell=$(basename "$SHELL")"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const l of text.split("\n")) {
                    const i = l.indexOf("=");
                    if (i > 0) o[l.slice(0, i)] = l.slice(i + 1).trim();
                }
                page.info = o;
            }
        }
    }

    Process {
        id: rename
        onExited: {
            page.renaming = false;
            page.refresh();
        }
    }

    function specsText() {
        const i = info;
        return [`Device: ${i.host} (${i.model})`, `OS: ${i.os} ${i.arch}`, `Kernel: ${i.kernel}`,
            `CPU: ${i.cpu} (${i.cores} threads)`, `GPU: ${i.gpu} ${i.vram ? "· " + i.vram : ""}`, `RAM: ${i.ram}`,
            `Storage: ${i.disk}`, `Desktop: niri ${i.niri} + ${page.shellName} ${page.version} (Quickshell ${i.qs})`].join("\n");
    }

    // ── устройство
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 128
        radius: 12
        color: Theme.surface

        RowLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 20

            Rectangle {
                implicitWidth: 84
                implicitHeight: 64
                radius: 8
                color: "transparent"
                border.width: 3
                border.color: Theme.accent

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: 2
                    width: 30
                    height: 5
                    radius: 2
                    color: Theme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    spacing: 10

                    Text {
                        visible: !page.renaming
                        text: page.info.host ?? ""
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 8
                        font.bold: true
                    }

                    Rectangle {
                        visible: page.renaming
                        implicitWidth: 240
                        implicitHeight: 34
                        radius: 8
                        color: Theme.surfaceHi
                        border.width: 1
                        border.color: Theme.line

                        TextInput {
                            id: hostInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 2
                            validator: RegularExpressionValidator { regularExpression: /^[a-zA-Z0-9-]{0,63}$/ }
                            Keys.onReturnPressed: saveName.clicked()
                            Keys.onEscapePressed: page.renaming = false
                        }
                    }

                    SButton {
                        text: page.renaming ? "Save" : "Rename"
                        primary: page.renaming
                        id: saveName
                        onClicked: {
                            if (!page.renaming) {
                                hostInput.text = page.info.host ?? "";
                                page.renaming = true;
                                hostInput.forceActiveFocus();
                            } else if (hostInput.text) {
                                rename.command = ["hostnamectl", "set-hostname", hostInput.text];
                                rename.running = true;
                            }
                        }
                    }
                }

                Text {
                    text: page.info.model ?? ""
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }

    // ── учётная запись
    SSection { text: I18n.tr("Account") }

    SCard {
        icon: String.fromCodePoint(0xF0004)
        title: page.info.fullname ? `${page.info.fullname} (${page.info.user})` : (page.info.user ?? "")
        desc: [page.info.admin === "yes" ? "Administrator" : "Standard user", `shell: ${page.info.shell ?? ""}`,
               page.info.since ? `system installed ${page.info.since}` : ""].filter(s => s).join("   ·   ")
    }

    // ── оболочка
    SSection { text: I18n.tr("Shell") }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: shellRow.implicitHeight + 36
        radius: 12
        color: Theme.surface

        RowLayout {
            id: shellRow
            x: 22
            y: 18
            width: parent.width - 44
            spacing: 18

            Rectangle {
                implicitWidth: 52
                implicitHeight: 52
                radius: 14
                color: Theme.accent

                Text {
                    anchors.centerIn: parent
                    text: "R"
                    color: Theme.bg
                    font.family: Theme.font
                    font.pixelSize: 26
                    font.bold: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    text: `${page.shellName}  ${page.version}`
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 3
                    font.bold: true
                }
                Text {
                    text: `by ${page.author}`
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                Text {
                    text: `Built on Quickshell ${page.info.qs ?? ""} · niri ${page.info.niri ?? ""} · ${Theme.palette.name} theme`
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }

    // ── характеристики
    RowLayout {
        Layout.fillWidth: true

        SSection {
            Layout.fillWidth: true
            text: I18n.tr("Device specifications")
        }
        SButton {
            id: copyBtn
            Layout.topMargin: 12
            property bool copied: false
            text: copied ? "Copied" : "Copy"
            icon: String.fromCodePoint(0xF018F)
            onClicked: {
                Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", page.specsText()]);
                copied = true;
                copiedTimer.restart();
            }

            Timer {
                id: copiedTimer
                interval: 1500
                onTriggered: copyBtn.copied = false
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard { icon: String.fromCodePoint(0xF061A); title: "Processor"; desc: `${page.info.cpu ?? ""}  ·  ${page.info.cores ?? ""} threads` }
        SCard { icon: String.fromCodePoint(0xF08AE); title: "Graphics"; desc: `${page.info.gpu ?? ""}${page.info.vram ? "  ·  " + page.info.vram : ""}` }
        SCard { icon: String.fromCodePoint(0xF035B); title: "Memory"; desc: page.info.ram ?? "" }
        SCard {
            icon: String.fromCodePoint(0xF02CA)
            title: "Storage"
            desc: page.info.disk ?? ""

            Rectangle {
                width: 180
                height: 6
                radius: 3
                color: Theme.surfaceHi2
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: parent.width * Number(page.info.diskp ?? 0) / 100
                    height: parent.height
                    radius: 3
                    color: Number(page.info.diskp ?? 0) > 90 ? Theme.urgent : Theme.accent
                }
            }
        }
        SCard { icon: String.fromCodePoint(0xF08C7); title: "Operating system"; desc: `${page.info.os ?? ""} · ${page.info.arch ?? ""}` }
        SCard { icon: String.fromCodePoint(0xF033B); title: "Kernel"; desc: page.info.kernel ?? "" }
        SCard { icon: String.fromCodePoint(0xF051B); title: "Uptime"; desc: page.info.uptime ?? "" }
    }

    // ── для разработчиков
    SSection { text: I18n.tr("For developers") }

    SCard {
        icon: String.fromCodePoint(0xF0169)
        title: "Developer mode"
        desc: "Shows the Plugins page: install and write your own plugins for the shell"

        SSwitch {
            checked: Settings.developerMode
            onToggled: v => Settings.developerMode = v
        }
    }
}
