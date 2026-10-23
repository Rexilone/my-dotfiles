import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.screenshot

// свойства (Ctrl+I): тип, размер с вложенными, сколько внутри, даты, права, владелец
Item {
    id: ic

    required property var br
    readonly property var i: br.info ?? {}

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        MouseArea { anchors.fill: parent; onClicked: ic.br.info = null }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 480
        height: col.implicitHeight + 40
        radius: 18
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
                spacing: 14
                IconImage {
                    implicitSize: 48
                    source: Quickshell.iconPath(ic.br.iconFor({ name: ic.i.name ?? "", dir: ic.i.dir ?? false, path: ic.i.path ?? "" }), "text-x-generic")
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: ic.i.name ?? ""
                        wrapMode: Text.WrapAnywhere
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 3
                        font.bold: true
                    }
                    Text {
                        text: ic.i.mime ?? ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 16
                rowSpacing: 8

                Repeater {
                    model: ic.i.loading ? [["Size", I18n.tr("Counting…")]] : [
                        ["Size", ic.br.human(ic.i.size) + (ic.i.size >= 1024 ? `  (${Number(ic.i.size).toLocaleString(Qt.locale(I18n.locale), "f", 0)} B)` : "")],
                        ["Inside", ic.i.dir ? String(ic.i.count ?? 0) : ""],
                        ["Location", (ic.i.path ?? "").substring(0, (ic.i.path ?? "").lastIndexOf("/")).replace(ic.br.home, "~")],
                        ["Link to", ic.i.link ?? ""],
                        ["Modified", ic.i.mtime ? ic.br.when(new Date(ic.i.mtime * 1000)) : ""],
                        ["Opened", ic.i.atime ? ic.br.when(new Date(ic.i.atime * 1000)) : ""],
                        ["Permissions", `${ic.i.mode ?? ""}   ·   ${ic.i.owner ?? ""}`],
                    ].filter(r => r[1])

                    Item {
                        required property var modelData
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        implicitHeight: row.implicitHeight
                        RowLayout {
                            id: row
                            width: parent.width
                            Text {
                                Layout.preferredWidth: 110
                                text: I18n.tr(parent.parent.modelData[0])
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 1
                            }
                            Text {
                                Layout.fillWidth: true
                                text: parent.parent.modelData[1]
                                wrapMode: Text.WrapAnywhere
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 1
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                ToolButton { icon: 0xF018F; label: "Copy path"; onClicked: { Quickshell.execDetached(["wl-copy", "--", ic.i.path]); ic.br.say(I18n.tr("Copied")); } }
                ToolButton { label: "Close"; active: true; onClicked: ic.br.info = null }
            }
        }
    }
}
