import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// Телефон → Файлы: отправка, передачи с прогрессом, папка для принятых
ColumnLayout {
    id: tab

    signal pick

    Layout.fillWidth: true
    spacing: 6

    readonly property string dir: Rexlink.settings.downloadDirResolved ?? ""

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: I18n.tr("Drop files on this page or pick them. On the device: Share → Rexlink.")
            wrapMode: Text.Wrap
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
        SButton {
            text: "Folder"
            icon: Icons.folder
            onClicked: Quickshell.execDetached(["xdg-open", tab.dir || Quickshell.env("HOME")])
        }
        SButton {
            text: "Send"
            icon: String.fromCodePoint(0xF0552)
            primary: true
            enabled: Rexlink.online
            onClicked: tab.pick()
        }
    }

    PhoneEmpty {
        visible: Rexlink.transfers.length === 0
        icon: String.fromCodePoint(0xF0256)
        text: "No transfers yet"
        hint: `${I18n.tr("Received files are saved to")} ${tab.dir}`
    }

    Repeater {
        model: Rexlink.transfers

        Rectangle {
            id: tr
            required property var modelData
            readonly property bool active: modelData.state === "active"
            readonly property bool openable: modelData.state === "done" && modelData.dir === "in"

            Layout.fillWidth: true
            implicitHeight: 70
            radius: 10
            color: trArea.containsMouse && openable ? Theme.surfaceHi : Theme.surface

            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            MouseArea {
                id: trArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: tr.openable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (tr.openable) Quickshell.execDetached(["xdg-open", tr.modelData.path])
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 14
                spacing: 16

                Text {
                    text: String.fromCodePoint(tr.modelData.dir === "in" ? 0xF01DA : 0xF0552)
                    color: tr.modelData.state === "error" ? Theme.urgent : tr.active ? Theme.accent : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize + 5
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: tr.modelData.name
                            elide: Text.ElideMiddle
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            text: tr.active ? `${Rexlink.bytes(tr.modelData.done)} / ${Rexlink.bytes(tr.modelData.size)}   ·   ${Rexlink.bytes(tr.modelData.speed)}${I18n.ru ? "/с" : "/s"}`
                                : I18n.tr(({ done: tr.modelData.dir === "in" ? "Received" : "Sent", error: "Error", cancelled: "Cancelled" })[tr.modelData.state] ?? "")
                                  + (tr.modelData.state === "done" ? `   ·   ${Rexlink.bytes(tr.modelData.size)}` : "")
                            color: tr.modelData.state === "error" ? Theme.urgent : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: Theme.surfaceHi2
                        Rectangle {
                            width: parent.width * (tr.modelData.size ? Math.min(1, tr.modelData.done / tr.modelData.size) : (tr.modelData.state === "done" ? 1 : 0))
                            height: parent.height
                            radius: 2
                            color: tr.modelData.state === "error" ? Theme.urgent : Theme.accent
                            Behavior on width { NumberAnimation { duration: 250 } }
                        }
                    }
                }

                SButton {
                    visible: tr.active
                    icon: String.fromCodePoint(0xF0156)
                    onClicked: Rexlink.transferCancel(tr.modelData.fid)
                }
                SButton {
                    visible: tr.openable
                    icon: Icons.folder
                    onClicked: Quickshell.execDetached(["xdg-open", tr.modelData.path.substring(0, tr.modelData.path.lastIndexOf("/"))])
                }
            }
        }
    }

    SButton {
        visible: Rexlink.transfers.some(t => t.state !== "active")
        Layout.topMargin: 4
        text: "Clear the list"
        onClicked: Rexlink.transfersClear()
    }

    SSection { text: I18n.tr("Received files") }

    SCard {
        icon: Icons.folder
        title: "Save to"
        desc: tab.dir

        SField {
            id: dirField
            implicitWidth: 260
            Layout.fillWidth: false
            placeholder: "~/Downloads/Rexlink"
            onAccepted: {
                const p = text.trim().replace(/^~(?=\/|$)/, Quickshell.env("HOME"));
                if (p) Rexlink.setDownloadDir(p);
                text = "";
            }
        }
    }
}
