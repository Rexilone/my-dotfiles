import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.screenshot

// верх проводника: назад/вперёд/вверх, путь (крошки; Ctrl+L — ввести), поиск, вид, сортировка, меню
Item {
    id: tb

    required property var br

    implicitHeight: 58
    Component.onCompleted: br.topBarItem = tb

    property bool editing: false

    function editPath() {
        editing = true;
        pathField.text = br.path;
        pathField.forceActiveFocus();
        pathField.selectAll();
    }
    function focusSearch() {
        search.forceActiveFocus();
        search.selectAll();
    }
    function clearSearch() {
        search.text = "";
        if (br.mode === "search") br.go(br.path, true);
        br.filter = "";
        br.forceViewFocus();
    }

    // части пути для крошек; домашняя папка — «Домашняя»
    readonly property var crumbs: {
        const p = br.path;
        if (br.mode === "trash") return [{ name: I18n.tr("Trash"), path: "" }];
        const out = [];
        let base = "", rest = p;
        if (p === br.home || p.startsWith(br.home + "/")) {
            out.push({ name: I18n.tr("Home"), path: br.home });
            base = br.home;
            rest = p.slice(br.home.length);
        } else {
            out.push({ name: "/", path: "/" });
        }
        for (const part of rest.split("/").filter(x => x)) {
            base = (base === "/" ? "" : base) + "/" + part;
            out.push({ name: part.startsWith("dav:host=") ? I18n.tr("Phone") : part, path: base });
        }
        if (br.mode === "search") out.push({ name: `${I18n.tr("Search")}: ${br.filter}`, path: "" });
        return out;
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 4

        ToolButton { icon: 0xF004D; tip: "Back"; key: "Alt+←"; off: !tb.br.back.length; onClicked: tb.br.goBack() }
        ToolButton { icon: 0xF0054; tip: "Forward"; key: "Alt+→"; off: !tb.br.fwd.length; onClicked: tb.br.goFwd() }
        ToolButton { icon: 0xF005D; tip: "Up"; key: "Backspace"; off: tb.br.path === "/" && tb.br.mode === "dir"; onClicked: tb.br.up() }

        // путь
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            implicitHeight: 36
            radius: 10
            color: Theme.surfaceHi
            border.width: 1
            border.color: pathField.activeFocus ? Theme.accent : Theme.surfaceHi2

            // пустое место справа от крошек — ввести путь
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onClicked: tb.editPath()
            }

            Flickable {
                id: crumbFlick
                visible: !tb.editing
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                contentWidth: crumbRow.implicitWidth
                clip: true
                interactive: false
                // последние части пути видны всегда
                contentX: Math.max(0, contentWidth - width)

                Row {
                    id: crumbRow
                    height: parent.height
                    spacing: 0
                    Repeater {
                        model: tb.crumbs
                        Row {
                            required property var modelData
                            required property int index
                            height: crumbRow.height
                            Text {
                                visible: parent.index > 0 && parent.index !== 1 || (parent.index === 1 && tb.crumbs[0].path !== "/")
                                anchors.verticalCenter: parent.verticalCenter
                                text: " › "
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 1
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: crumbText.implicitWidth + 14
                                height: 26
                                radius: 7
                                color: crumbArea.containsMouse ? Theme.surfaceHi2 : "transparent"
                                Text {
                                    id: crumbText
                                    anchors.centerIn: parent
                                    text: parent.parent.modelData.name
                                    color: parent.parent.index === tb.crumbs.length - 1 ? Theme.fg : Theme.muted
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 1
                                    font.bold: parent.parent.index === tb.crumbs.length - 1
                                }
                                MouseArea {
                                    id: crumbArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (parent.parent.modelData.path) tb.br.go(parent.parent.modelData.path)
                                }
                                // бросить файлы на часть пути — переместить туда
                                DropArea {
                                    anchors.fill: parent
                                    enabled: !!parent.parent.modelData.path
                                    onDropped: d => {
                                        const paths = (d.urls ?? []).map(u => String(u)).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.slice(7)));
                                        if (paths.length) tb.br.transfer((d.modifiers & Qt.ControlModifier) ? "copy" : "move", paths, parent.parent.modelData.path);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            TextInput {
                id: pathField
                visible: tb.editing
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                selectionColor: Theme.accent
                selectedTextColor: Theme.bg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                clip: true
                onActiveFocusChanged: if (!activeFocus) tb.editing = false
                Keys.onEscapePressed: { tb.editing = false; tb.br.forceViewFocus(); }
                onAccepted: {
                    let p = text.trim();
                    if (p.startsWith("~")) p = tb.br.home + p.slice(1);
                    if (p.startsWith("file://")) p = decodeURIComponent(p.slice(7));
                    tb.editing = false;
                    if (p) tb.br.go(p);
                    tb.br.forceViewFocus();
                }
            }
        }

        // поиск: сразу фильтрует папку, Enter — искать во вложенных
        Rectangle {
            Layout.preferredWidth: search.activeFocus || search.text ? 260 : 170
            implicitHeight: 36
            radius: 10
            color: Theme.surfaceHi
            border.width: 1
            border.color: search.activeFocus ? Theme.accent : Theme.surfaceHi2
            Behavior on Layout.preferredWidth { NumberAnimation { duration: Theme.animFast } }

            Text {
                x: 11
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF0349)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.iconSize - 1
            }
            Text {
                visible: !search.text
                x: 33
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Search")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            TextInput {
                id: search
                anchors.fill: parent
                anchors.leftMargin: 33
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                selectionColor: Theme.accent
                selectedTextColor: Theme.bg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                clip: true
                onTextChanged: if (tb.br.mode !== "search") tb.br.filter = text
                onAccepted: { tb.br.filter = text; tb.br.runSearch(); tb.br.forceViewFocus(); }
                Keys.onEscapePressed: tb.clearSearch()
                Keys.onDownPressed: tb.br.forceViewFocus()
            }
        }

        ToolButton {
            icon: (tb.br.cfg.view ?? "grid") === "grid" ? 0xF0279 : 0xF0570
            tip: (tb.br.cfg.view ?? "grid") === "grid" ? "List" : "Grid"
            key: (tb.br.cfg.view ?? "grid") === "grid" ? "Ctrl+2" : "Ctrl+1"
            onClicked: Settings.setFiles("view", (tb.br.cfg.view ?? "grid") === "grid" ? "list" : "grid")
        }
        ToolButton {
            id: sortBtn
            icon: 0xF04BA
            tip: "Sort"
            onClicked: {
                const s = tb.br.cfg.sort ?? "name", r = tb.br.cfg.reverse ?? false;
                const opt = (k, t) => ({ text: t, check: s === k, act: () => Settings.setFiles("sort", k) });
                const p = sortBtn.mapToItem(tb.br, 0, sortBtn.height + 4);
                tb.br.popupMenu(p.x, p.y, [
                    opt("name", "By name"), opt("time", "By date"), opt("size", "By size"), opt("type", "By type"),
                    { sep: true },
                    { text: "Reverse order", check: r, act: () => Settings.setFiles("reverse", !r) },
                    { text: "Hidden files", key: "Ctrl+H", check: tb.br.cfg.hidden ?? false, act: () => Settings.setFiles("hidden", !(tb.br.cfg.hidden ?? false)) },
                ]);
            }
        }
        ToolButton {
            id: moreBtn
            icon: 0xF01D9
            tip: "Menu"
            onClicked: {
                const p = moreBtn.mapToItem(tb.br, 0, moreBtn.height + 4);
                tb.br.popupMenu(p.x, p.y, [
                    { icon: 0xF0257, text: "New folder", key: "Ctrl+Shift+N", off: tb.br.mode !== "dir", act: () => tb.br.newFolder() },
                    { icon: 0xF018D, text: "Open terminal here", act: () => tb.br.openTerminal(tb.br.path) },
                    { icon: 0xF0C5A, text: "Add to bookmarks", off: tb.br.mode !== "dir", act: () => tb.br.bookmark(tb.br.path) },
                    { icon: 0xF0450, text: "Refresh", key: "F5", act: () => tb.br.refresh() },
                    { sep: true },
                    { icon: 0xF0590, text: "Sidebar", check: tb.br.cfg.sidebar ?? true, act: () => Settings.setFiles("sidebar", !(tb.br.cfg.sidebar ?? true)) },
                    { icon: 0xF024B, text: "Use as the default file manager", act: () => tb.br.makeDefault() },
                ]);
            }
        }
    }
}
