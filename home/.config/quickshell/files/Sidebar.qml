import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services

// боковая панель проводника: места, телефон и планшет (Rexlink), диски, закладки, корзина
Flickable {
    id: sb

    required property var br

    contentHeight: col.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    component Caption: Text {
        Layout.topMargin: 14
        Layout.bottomMargin: 4
        Layout.leftMargin: 10
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 3
        font.bold: true
    }

    component Place: Rectangle {
        id: pl
        property string icon: ""         // значок темы
        property int glyph: 0            // или значок шрифта
        property string label: ""
        property string sub: ""
        property string target: ""
        property bool here: false
        property bool busy: false
        signal activated
        signal menu(real x, real y)

        Layout.fillWidth: true
        implicitHeight: sub ? 44 : 34
        radius: 9
        color: here ? Theme.surfaceHi2 : area.containsMouse || drop.containsDrag ? Theme.surfaceHi : "transparent"

        Rectangle {
            visible: pl.here
            x: 3
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 16
            radius: 2
            color: Theme.accent
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 10

            IconImage {
                visible: pl.icon !== ""
                implicitSize: 18
                source: pl.icon ? Quickshell.iconPath(pl.icon, "folder") : ""
            }
            Text {
                visible: pl.icon === ""
                text: pl.glyph ? String.fromCodePoint(pl.glyph) : ""
                color: pl.here ? Theme.accent : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 1
                Layout.preferredWidth: 18
                horizontalAlignment: Text.AlignHCenter
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: pl.label
                    elide: Text.ElideRight
                    color: pl.here ? Theme.fg : Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: pl.here
                }
                Text {
                    visible: pl.sub !== ""
                    Layout.fillWidth: true
                    text: pl.sub
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }
            Text {
                visible: pl.busy
                text: "…"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    const p = mapToItem(sb.br, mouse.x, mouse.y);
                    pl.menu(p.x, p.y);
                } else pl.activated();
            }
        }

        // перетащить файлы на место — переместить туда (Ctrl — скопировать)
        DropArea {
            id: drop
            anchors.fill: parent
            enabled: pl.target !== ""
            onDropped: d => {
                const paths = (d.urls ?? []).map(u => String(u)).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.slice(7)));
                if (!paths.length) return;
                sb.br.transfer((d.modifiers & Qt.ControlModifier) ? "copy" : "move", paths, pl.target);
                d.accept(Qt.CopyAction);
            }
        }
    }

    ColumnLayout {
        id: col
        x: 10
        y: 12
        width: sb.width - 20
        spacing: 1

        // ── места
        Repeater {
            model: sb.br.places.dirs ?? []
            Place {
                required property var modelData
                icon: ({ home: "user-home", desktop: "user-desktop", documents: "folder-documents", download: "folder-download",
                         music: "folder-music", pictures: "folder-pictures", videos: "folder-videos" })[modelData.icon] ?? "folder"
                label: I18n.tr(modelData.name)
                target: modelData.path
                here: sb.br.mode === "dir" && sb.br.path === modelData.path
                onActivated: sb.br.go(modelData.path)
            }
        }
        Place {
            icon: "user-trash"
            label: I18n.tr("Trash")
            sub: (sb.br.places.trash ?? 0) ? `${sb.br.places.trash}` : ""
            here: sb.br.mode === "trash"
            onActivated: sb.br.openTrash()
        }

        // ── устройства: телефон и планшет через Rexlink, диски
        Caption {
            visible: Rexlink.connected && Rexlink.devices.length > 0 || (sb.br.places.drives ?? []).length > 0
            text: I18n.tr("DEVICES")
        }
        Repeater {
            model: Rexlink.connected ? Rexlink.devices : []
            Place {
                id: ph
                required property var modelData
                readonly property string p: sb.br.phonePath(modelData)
                glyph: modelData.kind === "tablet" ? 0xF04F7 : modelData.kind === "watch" ? 0xF0954 : 0xF011C
                label: modelData.name
                sub: !modelData.online ? I18n.tr("Offline")
                    : p ? `${modelData.battery >= 0 ? modelData.battery + "%   ·   " : ""}${I18n.tr("Storage")}`
                    : modelData.files?.state === "permission" ? I18n.tr("Allow «All files» on the device")
                    : modelData.files?.state === "mounting" ? I18n.tr("Connecting…")
                    : I18n.tr("Click to open the storage")
                target: p
                busy: sb.br.waitPhone === modelData.id
                here: !!p && sb.br.path.startsWith(p)
                opacity: modelData.online ? 1 : 0.5
                onActivated: if (modelData.online) sb.br.openPhone(modelData)
            }
        }
        Repeater {
            model: sb.br.places.drives ?? []
            Place {
                required property var modelData
                glyph: 0xF02CA
                label: modelData.name
                sub: modelData.size ? `${modelData.size}${modelData["use%"] ? "   ·   " + modelData["use%"] : ""}` : ""
                target: modelData.path
                here: sb.br.path.startsWith(modelData.path)
                onActivated: sb.br.go(modelData.path)
                onMenu: (x, y) => sb.br.popupMenu(x, y, [
                    { icon: 0xF01A4, text: "Unmount", act: () => Quickshell.execDetached(["udisksctl", "unmount", "-b", modelData.source ?? "", "--no-user-interaction"]) },
                ])
            }
        }
        Place {
            glyph: 0xF0A0A
            label: I18n.tr("Computer")
            sub: "/"
            target: "/"
            here: sb.br.mode === "dir" && sb.br.path === "/"
            onActivated: sb.br.go("/")
        }

        // ── закладки
        Caption {
            visible: (sb.br.places.bookmarks ?? []).length > 0
            text: I18n.tr("BOOKMARKS")
        }
        Repeater {
            model: sb.br.places.bookmarks ?? []
            Place {
                required property var modelData
                icon: "folder"
                label: modelData.name
                target: modelData.path
                here: sb.br.mode === "dir" && sb.br.path === modelData.path
                onActivated: sb.br.go(modelData.path)
                onMenu: (x, y) => sb.br.popupMenu(x, y, [
                    { icon: 0xF0156, text: "Remove from bookmarks", act: () => sb.br.unbookmark(modelData.path) },
                ])
            }
        }
    }
}
