import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// шапка как в Nautilus: назад/вперёд, строка пути с меню папки (щелчок по пустому месту или Ctrl+L — ввести путь,
// в поиске — поле поиска), поиск, вид (сетка/список и меню сортировки), ход копирования, закрыть окно
Item {
    id: hb

    required property var br

    implicitHeight: 46
    Component.onCompleted: br.topBarItem = hb

    property bool editing: false

    function editPath() {
        br.closeSearch();
        editing = true;
        pathField.text = br.mode === "dir" ? br.path : br.home;
        pathField.forceActiveFocus();
        pathField.selectAll();
    }
    function focusSearch(text) {
        editing = false;
        br.searchOpen = true;
        searchField.forceActiveFocus();
        if (text !== undefined) {
            searchField.text = text;
            searchField.cursorPosition = text.length;
        } else searchField.selectAll();
    }
    function clearSearch() {
        searchField.text = "";
        br.closeSearch();
    }
    Connections {
        target: hb.br
        function onSearchOpenChanged() { if (!hb.br.searchOpen) searchField.text = ""; }
    }

    // части пути для крошек
    readonly property var crumbs: {
        const p = br.path;
        if (br.mode === "trash") return [{ name: I18n.tr("Trash"), glyph: 0xF0A7A, path: "" }];
        if (br.mode === "recent") return [{ name: I18n.tr("Recent"), glyph: 0xF0150, path: "" }];
        if (br.mode === "starred") return [{ name: I18n.tr("Starred"), glyph: 0xF04D2, path: "" }];
        const out = [];
        let base = "", rest = p;
        if (p === br.home || p.startsWith(br.home + "/")) {
            out.push({ name: I18n.tr("Home Folder"), glyph: 0xF06A1, path: br.home });
            base = br.home;
            rest = p.slice(br.home.length);
        } else {
            out.push({ name: "", glyph: 0xF07C0, path: "/" });
            base = "";
        }
        for (const part of rest.split("/").filter(x => x)) {
            base = base + "/" + part;
            out.push({ name: part.startsWith("dav:host=") ? I18n.tr("Phone") : part, glyph: 0, path: base });
        }
        return out;
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 8
        spacing: 4

        // боковая панель скрыта — её кнопка и главное меню здесь
        FButton {
            visible: !hb.br.sidebarOn
            glyph: 0xF06FD
            tip: I18n.tr("Show Sidebar")
            key: "F9"
            onClicked: Settings.setFiles("sidebar", true)
        }
        FButton {
            id: menuBtn
            visible: !hb.br.sidebarOn
            glyph: 0xF035C
            tip: I18n.tr("Main Menu")
            checked: hb.br.menuOwner === menuBtn
            onClicked: {
                const p = menuBtn.mapToItem(hb.br, 0, menuBtn.height + 4);
                hb.br.mainMenu(p.x, p.y, menuBtn, true);
            }
        }

        FButton {
            glyph: 0xF004D
            tip: I18n.tr("Back")
            key: "Alt+←"
            off: !hb.br.back.length
            onClicked: hb.br.goBack()
        }
        FButton {
            glyph: 0xF0054
            tip: I18n.tr("Forward")
            key: "Alt+→"
            off: !hb.br.fwd.length
            onClicked: hb.br.goFwd()
        }

        // ── строка пути / поиск
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            implicitHeight: 34
            radius: 8
            color: FStyle.field
            border.width: pathField.activeFocus || searchField.activeFocus ? 2 : 0
            border.color: FStyle.alpha(Theme.accent, 0.6)

            // пустое место справа от крошек — ввести путь
            MouseArea {
                anchors.fill: parent
                visible: !hb.editing && !hb.br.searchOpen
                cursorShape: Qt.IBeamCursor
                onClicked: hb.editPath()
            }

            Flickable {
                id: crumbFlick
                visible: !hb.editing && !hb.br.searchOpen
                anchors.left: parent.left
                anchors.right: folderBtn.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 3
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
                        model: hb.crumbs
                        Row {
                            id: crumb
                            required property var modelData
                            required property int index
                            readonly property bool last: index === hb.crumbs.length - 1
                            height: crumbRow.height
                            Text {
                                visible: crumb.index > 0 && !(crumb.index === 1 && hb.crumbs[0].path === "/")
                                anchors.verticalCenter: parent.verticalCenter
                                leftPadding: 1
                                rightPadding: 1
                                text: "/"
                                color: Theme.dim
                                font.family: FStyle.ui
                                font.pixelSize: FStyle.fs
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: crumbContent.implicitWidth + 16
                                height: 28
                                radius: 6
                                color: crumbArea.pressed ? FStyle.press : crumbArea.containsMouse && crumb.modelData.path ? FStyle.hover : "transparent"
                                Row {
                                    id: crumbContent
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        visible: crumb.modelData.glyph !== 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: crumb.modelData.glyph ? String.fromCodePoint(crumb.modelData.glyph) : ""
                                        color: Theme.fg
                                        font.family: FStyle.glyphs
                                        font.pixelSize: FStyle.icon
                                    }
                                    Text {
                                        visible: crumb.modelData.name !== ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: crumb.modelData.name
                                        color: Theme.fg
                                        font.family: FStyle.ui
                                        font.pixelSize: FStyle.fs
                                        font.weight: crumb.last ? Font.DemiBold : Font.Normal
                                    }
                                }
                                MouseArea {
                                    id: crumbArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    onClicked: mouse => {
                                        const p = crumb.modelData.path;
                                        if (!p) return;
                                        if (mouse.button === Qt.MiddleButton) hb.br.newWindowRequested(p);
                                        else hb.br.go(p);
                                    }
                                }
                                // бросить файлы на часть пути — переместить туда
                                DropArea {
                                    anchors.fill: parent
                                    enabled: !!crumb.modelData.path && !crumb.last
                                    onDropped: d => {
                                        const paths = (d.urls ?? []).map(u => String(u)).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.slice(7)));
                                        if (paths.length) hb.br.transfer((d.modifiers & Qt.ControlModifier) ? "copy" : "move", paths, crumb.modelData.path);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // меню папки
            FButton {
                id: folderBtn
                visible: !hb.editing && !hb.br.searchOpen
                anchors.right: parent.right
                anchors.rightMargin: 3
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 28
                implicitHeight: 28
                radius: 6
                glyph: 0xF01D9
                tip: I18n.tr("Folder Actions")
                checked: hb.br.menuOwner === folderBtn
                onClicked: {
                    const p = folderBtn.mapToItem(hb.br, folderBtn.width, folderBtn.height + 6);
                    hb.br.locationMenu(p.x, p.y, folderBtn);
                }
            }

            TextInput {
                id: pathField
                visible: hb.editing
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                selectionColor: Theme.accent
                selectedTextColor: Theme.bg
                font.family: FStyle.ui
                font.pixelSize: FStyle.fs
                clip: true
                onActiveFocusChanged: if (!activeFocus) hb.editing = false
                Keys.onEscapePressed: { hb.editing = false; hb.br.forceViewFocus(); }
                onAccepted: {
                    let p = text.trim();
                    if (p.startsWith("~")) p = hb.br.home + p.slice(1);
                    if (p.startsWith("file://")) p = decodeURIComponent(p.slice(7));
                    hb.editing = false;
                    if (p) hb.br.go(p);
                    hb.br.forceViewFocus();
                }
            }

            // поиск
            Item {
                visible: hb.br.searchOpen
                anchors.fill: parent
                Text {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xF0349)
                    color: Theme.dim
                    font.family: FStyle.glyphs
                    font.pixelSize: FStyle.icon
                }
                Text {
                    visible: !searchField.text
                    x: 38
                    anchors.verticalCenter: parent.verticalCenter
                    text: hb.br.searchRemote ? I18n.tr("Filter this folder") : `${I18n.tr("Search in")} «${hb.br.searchBaseName}»`
                    color: Theme.dim
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fs
                }
                TextInput {
                    id: searchField
                    anchors.fill: parent
                    anchors.leftMargin: 38
                    anchors.rightMargin: 34
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fs
                    clip: true
                    onTextChanged: hb.br.setQuery(text)
                    onAccepted: hb.br.forceViewFocus()
                    Keys.onEscapePressed: { hb.clearSearch(); hb.br.forceViewFocus(); }
                    Keys.onDownPressed: hb.br.forceViewFocus()
                }
                FButton {
                    visible: searchField.text !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 6
                    glyph: 0xF0156
                    glyphSize: FStyle.icon - 2
                    onClicked: { searchField.text = ""; searchField.forceActiveFocus(); }
                }
            }
        }

        FButton {
            glyph: 0xF0349
            tip: I18n.tr("Search")
            key: "Ctrl+F"
            checked: hb.br.searchOpen
            onClicked: {
                if (hb.br.searchOpen) { hb.clearSearch(); hb.br.forceViewFocus(); }
                else hb.focusSearch();
            }
        }

        // вид: сетка/список и меню (размер значков, сортировка)
        Row {
            spacing: 0
            FButton {
                id: viewBtn
                glyph: (hb.br.cfg.view ?? "grid") === "grid" ? 0xF0279 : 0xF11D9
                tip: I18n.tr((hb.br.cfg.view ?? "grid") === "grid" ? "List View" : "Grid View")
                key: (hb.br.cfg.view ?? "grid") === "grid" ? "Ctrl+2" : "Ctrl+1"
                topRightRadius: 0
                bottomRightRadius: 0
                onClicked: Settings.setFiles("view", (hb.br.cfg.view ?? "grid") === "grid" ? "list" : "grid")
            }
            FButton {
                id: viewMenuBtn
                implicitWidth: 24
                glyph: 0xF0140
                glyphSize: FStyle.icon - 2
                tip: I18n.tr("View Options")
                topLeftRadius: 0
                bottomLeftRadius: 0
                checked: hb.br.menuOwner === viewMenuBtn
                onClicked: {
                    const p = viewMenuBtn.mapToItem(hb.br, viewMenuBtn.width, viewMenuBtn.height + 6);
                    hb.br.viewMenu(p.x, p.y, viewMenuBtn);
                }
            }
        }

        // копирование идёт — круг хода, по щелчку подробности и отмена
        FButton {
            id: jobBtn
            visible: !!hb.br.job
            tip: hb.br.job?.title ?? ""
            checked: hb.br.menuOwner === jobBtn
            onClicked: {
                const p = jobBtn.mapToItem(hb.br, jobBtn.width, jobBtn.height + 6);
                hb.br.jobMenu(p.x, p.y, jobBtn);
            }
            Canvas {
                id: ring
                anchors.centerIn: parent
                width: 18
                height: 18
                readonly property real part: hb.br.job?.total ? Math.min(1, hb.br.job.done / hb.br.job.total) : 0
                onPartChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.lineWidth = 3;
                    ctx.strokeStyle = FStyle.alpha(Theme.fg, 0.2);
                    ctx.beginPath();
                    ctx.arc(9, 9, 7, 0, Math.PI * 2);
                    ctx.stroke();
                    ctx.strokeStyle = Theme.accent;
                    ctx.beginPath();
                    ctx.arc(9, 9, 7, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.03, part));
                    ctx.stroke();
                }
            }
        }

        FButton {
            Layout.leftMargin: 6
            circular: true
            implicitWidth: 26
            implicitHeight: 26
            flat: false
            glyph: 0xF0156
            glyphSize: FStyle.icon - 3
            tip: I18n.tr("Close")
            key: "Ctrl+W"
            onClicked: hb.br.closeRequested()
        }
    }
}
