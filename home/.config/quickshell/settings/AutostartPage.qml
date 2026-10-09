import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// Автозапуск: строки spawn-at-startup из конфига niri + свои из Настроек
Page {
    id: page

    title: "Startup apps"
    subtitle: "Apps and commands that start when you log in"

    readonly property string cfgPath: `${Quickshell.env("HOME")}/.config/niri/config.kdl`
    property var entries: []      // из config.kdl: [{ line, enabled, command, text }]

    // разбор аргументов KDL: "a" "b c" -> a "b c"
    function pretty(args) {
        const parts = [];
        const re = /"((?:[^"\\]|\\.)*)"/g;
        let m;
        while ((m = re.exec(args)) !== null) parts.push(m[1].replace(/\\"/g, '"'));
        return parts.map(p => /\s/.test(p) ? `"${p}"` : p).join(" ");
    }

    function parse() {
        const lines = cfg.text().split("\n");
        const out = [];
        lines.forEach((l, i) => {
            const m = l.match(/^(\s*)(\/-)?(spawn(?:-sh)?-at-startup)\s+(.+)$/);
            if (m) out.push({ line: i, enabled: !m[2], command: page.pretty(m[4]), raw: m[4] });
        });
        entries = out;
    }

    function toggle(e, on) {
        const lines = cfg.text().split("\n");
        const l = lines[e.line];
        lines[e.line] = on ? l.replace(/^(\s*)\/-/, "$1") : l.replace(/^(\s*)(spawn)/, "$1/-$2");
        cfg.setText(lines.join("\n"));
    }

    function isShell(e) {
        return /^qs( |$)|^quickshell( |$)/.test(e.command);
    }

    FileView {
        id: cfg
        path: page.cfgPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: page.parse()
        onSaved: page.parse()
    }

    function addCommand(cmd) {
        cmd = cmd.trim();
        if (!cmd) return;
        Settings.autostart = (Settings.autostart ?? []).concat([{ command: cmd, enabled: true }]);
    }

    function setManaged(i, key, value) {
        const a = JSON.parse(JSON.stringify(Settings.autostart ?? []));
        if (value === undefined) a.splice(i, 1);
        else a[i][key] = value;
        Settings.autostart = a;
    }

    // ── из конфига niri
    SSection { text: I18n.tr("From niri config") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: page.entries

            SCard {
                id: e
                required property var modelData

                icon: String.fromCodePoint(0xF0412)
                title: modelData.command.split(" ")[0]
                desc: page.isShell(modelData) ? "This shell — can't be turned off here" : modelData.command

                SButton {
                    text: I18n.tr("Run")
                    visible: !page.isShell(e.modelData)
                    onClicked: Quickshell.execDetached(["sh", "-c", e.modelData.command])
                }
                SSwitch {
                    checked: e.modelData.enabled
                    enabled: !page.isShell(e.modelData)
                    opacity: enabled ? 1 : 0.4
                    onToggled: v => page.toggle(e.modelData, v)
                }
            }
        }
    }

    // ── свои
    SSection { text: I18n.tr("Added here") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Text {
            visible: (Settings.autostart ?? []).length === 0
            Layout.bottomMargin: 4
            text: I18n.tr("Nothing yet — add an app or a command below")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }

        Repeater {
            model: Settings.autostart ?? []

            SCard {
                id: m
                required property var modelData
                required property int index

                icon: String.fromCodePoint(0xF0412)
                title: modelData.command.split(" ")[0]
                desc: modelData.command

                SButton {
                    text: I18n.tr("Run")
                    onClicked: Quickshell.execDetached(["sh", "-c", m.modelData.command])
                }
                SButton {
                    icon: Icons.trash
                    danger: true
                    onClicked: page.setManaged(m.index)
                }
                SSwitch {
                    checked: m.modelData.enabled
                    onToggled: v => page.setManaged(m.index, "enabled", v)
                }
            }
        }

        SCard {
            Layout.topMargin: 6
            icon: "+"
            title: "Add an app"

            SDropdown {
                minWidth: 260
                options: [{ value: "", label: "Choose an app…" }].concat(
                    DesktopEntries.applications.values.filter(d => !d.noDisplay)
                        .sort((a, b) => a.name.localeCompare(b.name))
                        .map(d => ({ value: d.command.join(" "), label: d.name })))
                current: ""
                onPicked: v => page.addCommand(v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF018D)
            title: "Add a command"
            desc: "Any shell command, e.g. telegram-desktop -startintray"

            Rectangle {
                width: 260
                height: 34
                radius: 8
                color: Theme.surfaceHi
                border.width: 1
                border.color: cmdInput.activeFocus ? Theme.line : Theme.surfaceHi2

                TextInput {
                    id: cmdInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    clip: true
                    Keys.onReturnPressed: {
                        page.addCommand(text);
                        text = "";
                    }
                }
            }
            SButton {
                text: I18n.tr("Add")
                primary: true
                enabled: cmdInput.text.trim() !== ""
                onClicked: {
                    page.addCommand(cmdInput.text);
                    cmdInput.text = "";
                }
            }
        }
    }

    Text {
        Layout.topMargin: 8
        text: I18n.tr("Changes apply at the next login. Use «Run» to start something now.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }
}
