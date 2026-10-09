import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// Плагины (видно в режиме разработчика): список, включение, настройки плагинов, инструменты
Page {
    id: page

    title: "Plugins"
    subtitle: "Extend the shell with your own modules — see README.md in the plugins folder"

    property string ipcTargets: ""
    property string newName: ""

    Component.onCompleted: {
        Plugins.reload();
        ipc.running = true;
    }

    Process {
        id: ipc
        command: ["qs", "ipc", "show"]
        stdout: StdioCollector {
            onStreamFinished: page.ipcTargets = text.trim()
        }
    }

    // создать плагин из шаблона plugins/.template
    Process {
        id: scaffold
        onExited: Plugins.reload()
    }

    function create(name) {
        const id = name.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
        if (!id) return;
        scaffold.command = ["sh", "-c", `
            d="$1/$2"
            [ -e "$d" ] && exit 1
            cp -r "$1/.template" "$d"
            for f in "$d"/*; do
                sed -i -e "s|__ID__|$2|g" -e "s|__NAME__|$3|g" -e "s|__AUTHOR__|$4|g" "$f"
            done`, "sh", Plugins.dir, id, name.trim().replace(/[|\\\\&]/g, ""), Quickshell.env("USER") ?? ""];
        scaffold.running = true;
        newName = "";
    }

    // ── инструменты
    SSection { text: I18n.tr("Developer tools") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: "+"
            title: "Create a plugin"
            desc: "Copies a ready template with a bar module, a service and a settings page"

            Rectangle {
                width: 220
                height: 34
                radius: 8
                color: Theme.surfaceHi
                border.width: 1
                border.color: nameInput.activeFocus ? Theme.line : Theme.surfaceHi2

                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    clip: true
                    text: page.newName
                    onTextChanged: page.newName = text
                    Keys.onReturnPressed: page.create(text)

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !nameInput.text
                        text: I18n.tr("Plugin name")
                        color: Theme.dim
                        font: nameInput.font
                    }
                }
            }
            SButton {
                text: I18n.tr("Create")
                primary: true
                enabled: page.newName.trim() !== ""
                onClicked: page.create(page.newName)
            }
        }

        SCard {
            icon: Icons.folder
            title: "Plugins folder"
            desc: "Each plugin is a folder with plugin.json. See README.md there."

            SButton { text: I18n.tr("README"); onClicked: Quickshell.execDetached(["foot", "nvim", `${Plugins.dir}/README.md`]) }
            SButton { text: I18n.tr("Open"); onClicked: Quickshell.execDetached(["xdg-open", Plugins.dir]) }
        }

        SCard {
            icon: String.fromCodePoint(0xF0450)
            title: "Reload"
            desc: "Rescan plugins after adding one; restart the shell after changing plugin code"

            SButton { text: Plugins.scanning ? "…" : "Rescan"; onClicked: Plugins.reload() }
            SButton { text: I18n.tr("Restart shell"); onClicked: Quickshell.execDetached(["sh", "-c", "pkill -x qs; sleep 0.3; setsid -f qs"]) }
        }

        SCard {
            icon: String.fromCodePoint(0xF018D)
            title: "Shell log"
            desc: "Errors from plugins show up here (qs log)"
            clickable: true
            onClicked: Quickshell.execDetached(["foot", "-T", "Quickshell log", "sh", "-c", "qs log -f"])
        }

        SCard {
            icon: String.fromCodePoint(0xF0169)
            title: "IPC commands"
            desc: page.ipcTargets ? page.ipcTargets.split("\n").filter(l => l.startsWith("target")).map(l => l.replace("target ", "")).join(" · ") : "—"
        }
    }

    // ── список плагинов
    SSection { text: `Installed (${Plugins.list.length})` }

    Text {
        visible: Plugins.list.length === 0
        text: I18n.tr("No plugins yet — create one above")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    Repeater {
        model: Plugins.list

        Rectangle {
            id: card

            required property var modelData
            readonly property bool on: Settings.plugins[modelData.id] === true
            property bool expanded: false

            Layout.fillWidth: true
            implicitHeight: col.implicitHeight + 28
            radius: 12
            color: Theme.surface
            border.width: modelData.error ? 1 : 0
            border.color: Theme.urgent

            ColumnLayout {
                id: col
                x: 18
                y: 14
                width: parent.width - 36
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Rectangle {
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: 12
                        color: card.on ? Theme.accent : Theme.surfaceHi2

                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF0431)
                            color: card.on ? Theme.bg : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize + 3
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: `${card.modelData.name}  ${card.modelData.version ? "v" + card.modelData.version : ""}`
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.error || card.modelData.description
                            wrapMode: Text.Wrap
                            color: card.modelData.error ? Theme.urgent : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Row {
                            spacing: 6
                            Repeater {
                                model: [["bar", "Bar"], ["service", "Service"], ["settings", "Settings"]].filter(x => card.modelData[x[0]])
                                Rectangle {
                                    required property var modelData
                                    width: tagText.implicitWidth + 12
                                    height: 18
                                    radius: 5
                                    color: Theme.surfaceHi2
                                    Text {
                                        id: tagText
                                        anchors.centerIn: parent
                                        text: parent.modelData[1]
                                        color: Theme.muted
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 4
                                    }
                                }
                            }
                            Text {
                                text: card.modelData.author ? `by ${card.modelData.author}` : ""
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 3
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    SButton {
                        text: I18n.tr("Edit")
                        onClicked: Quickshell.execDetached(["foot", "-D", card.modelData.dir, "nvim", "."])
                    }
                    SButton {
                        icon: Icons.folder
                        onClicked: Quickshell.execDetached(["xdg-open", card.modelData.dir])
                    }
                    SButton {
                        visible: card.on && card.modelData.settings !== ""
                        text: card.expanded ? "Hide" : "Settings"
                        onClicked: card.expanded = !card.expanded
                    }
                    SSwitch {
                        checked: card.on
                        enabled: !card.modelData.error
                        opacity: enabled ? 1 : 0.4
                        onToggled: v => Settings.setPlugin(card.modelData.id, v)
                    }
                }

                // страница настроек плагина
                Loader {
                    Layout.fillWidth: true
                    active: card.on && card.expanded && card.modelData.settings !== ""
                    visible: active
                    source: active ? Plugins.url(card.modelData, card.modelData.settings) : ""
                    onLoaded: if ("plugin" in item) item.plugin = Plugins.api(card.modelData)
                }

                Text {
                    visible: card.expanded && card.on && parent.children[1].status === Loader.Error
                    text: I18n.tr("Couldn't load the settings page — check the shell log")
                    color: Theme.urgent
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }
}
