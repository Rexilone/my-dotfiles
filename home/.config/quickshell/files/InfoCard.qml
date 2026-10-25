import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services

// свойства (Ctrl+I, Alt+Enter), как в Nautilus: значок, имя, тип; размер с вложенными, содержимое,
// расположение, даты, права и владелец
Dialog {
    id: ic

    required property var br
    readonly property var i: br.info ?? {}

    title: I18n.tr("Properties")
    maxWidth: 460
    onClosed: br.info = null

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        IconImage {
            Layout.alignment: Qt.AlignHCenter
            implicitSize: 96
            source: Quickshell.iconPath(ic.br.iconFor({ name: ic.i.name ?? "", dir: ic.i.dir ?? false, path: ic.i.path ?? "" }), "text-x-generic")
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            horizontalAlignment: Text.AlignHCenter
            text: ic.i.name ?? ""
            wrapMode: Text.WrapAnywhere
            color: Theme.fg
            font.family: FStyle.ui
            font.pixelSize: FStyle.fs + 5
            font.weight: Font.Bold
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: ic.i.loading ? I18n.tr("Counting…")
                : ic.i.dir ? `${I18n.plural(ic.i.count ?? 0, "item", "items", "объект", "объекта", "объектов")}: ${ic.i.count ?? 0}   ·   ${ic.br.human(ic.i.size)}`
                : `${ic.br.human(ic.i.size)}   ·   ${ic.i.mime ?? ""}`
            color: Theme.dim
            font.family: FStyle.ui
            font.pixelSize: FStyle.fs
        }
    }

    PrefGroup {
        Repeater {
            model: ic.i.loading ? [] : [
                ["Size", ic.br.human(ic.i.size) + (ic.i.size >= 1024 ? `  (${Number(ic.i.size).toLocaleString(Qt.locale(I18n.locale), "f", 0)} ${I18n.ru ? "байт" : "bytes"})` : "")],
                ["Contents", ic.i.dir ? `${ic.i.count ?? 0} ${I18n.plural(ic.i.count ?? 0, "item", "items", "объект", "объекта", "объектов")}` : ""],
                ["Type", ic.i.mime ?? ""],
                ["Parent Folder", (ic.i.path ?? "").substring(0, (ic.i.path ?? "").lastIndexOf("/")).replace(ic.br.home, "~") || "/"],
                ["Link to", ic.i.link ?? ""],
                ["Modified", ic.i.mtime ? Qt.locale(I18n.locale).toString(new Date(ic.i.mtime * 1000), "d MMMM yyyy, HH:mm") : ""],
                ["Accessed", ic.i.atime ? Qt.locale(I18n.locale).toString(new Date(ic.i.atime * 1000), "d MMMM yyyy, HH:mm") : ""],
                ["Permissions", `${ic.i.mode ?? ""}   ·   ${ic.i.owner ?? ""}`],
            ].filter(r => r[1])

            Item {
                id: prop
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: Math.max(46, val.implicitHeight + 20)
                Rectangle {
                    visible: prop.index > 0
                    width: parent.width
                    height: 1
                    color: FStyle.sep
                }
                Text {
                    id: key
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr(prop.modelData[0])
                    color: Theme.dim
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fs
                }
                Text {
                    id: val
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - key.implicitWidth - 44)
                    horizontalAlignment: Text.AlignRight
                    text: prop.modelData[1]
                    wrapMode: Text.WrapAnywhere
                    color: Theme.fg
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fs
                }
            }
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 10
        FButton {
            flat: false
            text: I18n.tr("Copy Location")
            onClicked: { Quickshell.execDetached(["wl-copy", "--", ic.i.path]); ic.br.say(I18n.tr("Copied")); }
        }
        FButton {
            visible: !ic.i.dir && !!ic.i.path
            flat: false
            text: I18n.tr("Open With…")
            onClicked: {
                const it = { name: ic.i.name, path: ic.i.path, dir: false };
                ic.br.info = null;
                ic.br.popupMenu(ic.br.width / 2 - 140, ic.br.height / 3, [{ text: I18n.tr("Open With…"), openWith: it.path }]);
            }
        }
    }
}
