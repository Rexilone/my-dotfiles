import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// боковая панель как в Nautilus: шапка с главным меню; недавние, избранное, папки, корзина;
// закладки; устройства — телефон и планшет (Rexlink), диски и флешки (с извлечением), компьютер
Rectangle {
    id: sb

    required property var br

    color: FStyle.sidebar

    component Divider: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.bottomMargin: 6
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        implicitHeight: 1
        color: FStyle.sep
    }

    // строка места: значок, подпись, справа — «…» или кнопка извлечения
    component Place: Rectangle {
        id: pl
        property int glyph: 0xF0256
        property string label: ""
        property string target: ""       // куда бросать файлы
        property bool here: false
        property bool busy: false
        property bool ejectable: false
        property string tip: ""
        signal activated
        signal middle
        signal menu(real x, real y)
        signal eject

        Layout.fillWidth: true
        implicitHeight: 38
        radius: 7
        color: here ? FStyle.active : area.pressed ? FStyle.press : area.containsMouse || drop.containsDrag ? FStyle.hover : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: pl.ejectable ? 4 : 12
            spacing: 12

            Text {
                Layout.preferredWidth: FStyle.icon + 2
                horizontalAlignment: Text.AlignHCenter
                text: String.fromCodePoint(pl.glyph)
                color: Theme.fg
                opacity: 0.85
                font.family: FStyle.glyphs
                font.pixelSize: FStyle.icon + 1
            }
            Text {
                Layout.fillWidth: true
                text: pl.label
                elide: Text.ElideRight
                color: Theme.fg
                font.family: FStyle.ui
                font.pixelSize: FStyle.fs
            }
            Text {
                visible: pl.busy
                text: "…"
                color: Theme.dim
                font.family: FStyle.ui
                font.pixelSize: FStyle.fs
            }
            FButton {
                visible: pl.ejectable && !pl.busy
                implicitWidth: 30
                implicitHeight: 30
                glyph: 0xF0B91
                tip: I18n.tr("Eject")
                onClicked: pl.eject()
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            anchors.rightMargin: pl.ejectable ? 36 : 0
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    const p = mapToItem(sb.br, mouse.x, mouse.y);
                    pl.menu(p.x, p.y);
                } else if (mouse.button === Qt.MiddleButton) pl.middle();
                else pl.activated();
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


    // меню места: открыть, в новом окне, терминал
    function placeMenu(x, y, p, extra) {
        br.popupMenu(x, y, [
            { text: I18n.tr("Open"), act: () => br.go(p) },
            { text: I18n.tr("Open in New Window"), act: () => br.newWindowRequested(p) },
            { text: I18n.tr("Open in Terminal"), act: () => br.openTerminal(p) },
        ].concat(extra ?? []));
    }

    // ── шапка: главное меню
    Item {
        id: head
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 46

        FButton {
            id: menuBtn
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            glyph: 0xF035C
            tip: I18n.tr("Main Menu")
            checked: sb.br.menuOwner === menuBtn
            onClicked: {
                const p = menuBtn.mapToItem(sb.br, menuBtn.width, menuBtn.height + 4);
                sb.br.mainMenu(p.x, p.y, menuBtn);
            }
        }
    }

    Flickable {
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: col.implicitHeight + 12
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: 6
            width: parent.width - 12
            spacing: 2

            Place {
                glyph: 0xF0150
                label: I18n.tr("Recent")
                here: sb.br.mode === "recent"
                onActivated: sb.br.openSpecial("recent")
            }
            Place {
                glyph: 0xF04D2
                label: I18n.tr("Starred")
                here: sb.br.mode === "starred"
                onActivated: sb.br.openSpecial("starred")
            }
            Repeater {
                model: sb.br.places.dirs ?? []
                Place {
                    required property var modelData
                    glyph: ({ home: 0xF06A1, desktop: 0xF0379, documents: 0xF09EE, download: 0xF0B8F,
                              music: 0xF0F74, pictures: 0xF0976, videos: 0xF0BDC })[modelData.icon] ?? 0xF0256
                    label: modelData.icon === "home" ? I18n.tr("Home Folder") : I18n.tr(modelData.name)
                    target: modelData.path
                    here: sb.br.mode === "dir" && sb.br.path === modelData.path
                    onActivated: sb.br.go(modelData.path)
                    onMiddle: sb.br.newWindowRequested(modelData.path)
                    onMenu: (x, y) => sb.placeMenu(x, y, modelData.path)
                }
            }
            Place {
                glyph: 0xF0A7A
                label: I18n.tr("Trash")
                here: sb.br.mode === "trash"
                onActivated: sb.br.openTrash()
                onMenu: (x, y) => sb.br.popupMenu(x, y, [
                    { text: I18n.tr("Open"), act: () => sb.br.openTrash() },
                    { sep: true },
                    { text: I18n.tr("Empty Trash…"), off: !(sb.br.places.trash ?? 0), danger: true, act: () => sb.br.askEmptyTrash() },
                ])
            }

            // ── закладки (GTK — их видят и окна выбора файлов)
            Divider { visible: (sb.br.places.bookmarks ?? []).length > 0 }
            Repeater {
                model: sb.br.places.bookmarks ?? []
                Place {
                    required property var modelData
                    glyph: 0xF0256
                    label: modelData.name
                    target: modelData.path
                    here: sb.br.mode === "dir" && sb.br.path === modelData.path
                    onActivated: sb.br.go(modelData.path)
                    onMiddle: sb.br.newWindowRequested(modelData.path)
                    onMenu: (x, y) => sb.placeMenu(x, y, modelData.path, [
                        { sep: true },
                        { text: I18n.tr("Remove from Bookmarks"), act: () => sb.br.unbookmark(modelData.path) },
                    ])
                }
            }

            // ── устройства: телефон и планшет через Rexlink, диски и флешки, корень
            Divider {}
            Repeater {
                model: Rexlink.connected ? Rexlink.devices : []
                Place {
                    required property var modelData
                    readonly property string p: sb.br.phonePath(modelData)
                    glyph: modelData.kind === "tablet" ? 0xF04F6 : 0xF011C
                    label: modelData.name
                    target: p
                    busy: sb.br.waitPhone === modelData.id
                    here: !!p && sb.br.path.startsWith(p)
                    opacity: modelData.online ? 1 : 0.5
                    onActivated: {
                        if (!modelData.online) sb.br.say(`${modelData.name}: ${I18n.tr("offline")}`);
                        else sb.br.openPhone(modelData);
                    }
                }
            }
            // диски и флешки (services/Drives.qml): не подключённые — подключить по щелчку
            Repeater {
                model: Drives.drives
                Place {
                    required property var modelData
                    readonly property var d: modelData
                    glyph: d.removable ? 0xF129F : 0xF02CA
                    label: d.name
                    target: d.mount
                    busy: sb.br.waitDrive === d.dev
                    ejectable: !!d.mount && d.removable
                    here: !!d.mount && sb.br.mode === "dir" && (sb.br.path === d.mount || sb.br.path.startsWith(d.mount + "/"))
                    onActivated: sb.br.openDrive(d)
                    onMiddle: if (d.mount) sb.br.newWindowRequested(d.mount)
                    onEject: sb.br.ejectDrive(d)
                    onMenu: (x, y) => sb.br.popupMenu(x, y, d.mount ? [
                        { text: I18n.tr("Open"), act: () => sb.br.go(d.mount) },
                        { text: I18n.tr("Open in New Window"), act: () => sb.br.newWindowRequested(d.mount) },
                        { text: I18n.tr("Open in Terminal"), act: () => sb.br.openTerminal(d.mount) },
                        { sep: true },
                        { text: I18n.tr("Unmount"), act: () => sb.br.unmountDrive(d) },
                    ].concat(d.removable ? [{ text: I18n.tr("Eject"), act: () => sb.br.ejectDrive(d) }] : [])
                    : [{ text: I18n.tr("Mount"), act: () => sb.br.openDrive(d) }])
                }
            }
            Place {
                glyph: 0xF07C0
                label: I18n.tr("Computer")
                target: "/"
                here: sb.br.mode === "dir" && sb.br.path === "/"
                onActivated: sb.br.go("/")
                onMiddle: sb.br.newWindowRequested("/")
                onMenu: (x, y) => sb.placeMenu(x, y, "/")
            }
        }
    }
}
