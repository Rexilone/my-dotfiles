import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services

// файлы сеткой или списком: выделение (клик, Ctrl, Shift, рамкой), перетаскивание наружу и на папки,
// бросить файлы из других программ — скопировать сюда, правый клик — меню
Item {
    id: fg

    required property var br

    readonly property bool grid: (br.cfg.view ?? "grid") === "grid"
    readonly property real zoom: br.cfg.zoom ?? 1
    readonly property int tile: Math.round(112 * zoom)
    readonly property int rowH: Math.round(34 * Math.max(0.8, zoom))
    readonly property int columns: grid ? Math.max(1, Math.floor(view.width / tile)) : 1
    readonly property bool remote: br.path.includes("/gvfs/")

    function forceFocus() {
        view.forceActiveFocus();
    }
    function positionAt(i) {
        view.positionViewAtIndex(i, GridView.Contain);
    }
    // ── перетаскивание наружу: системный drag со списком файлов
    Item {
        id: dragProxy
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
        Drag.proposedAction: Qt.CopyAction
        Drag.mimeData: ({ "text/uri-list": fg.br.fileUris(fg.br.selPaths).join("\r\n") + "\r\n" })
    }
    function startDrag() {
        if (!br.selPaths.length || br.mode === "trash") return;
        dragProxy.Drag.mimeData = { "text/uri-list": br.fileUris(br.selPaths).join("\r\n") + "\r\n" };
        dragProxy.Drag.active = true;
        dragProxy.Drag.startDrag();
        dragProxy.Drag.active = false;
    }

    // ── бросили файлы сюда (из другой программы или из этого окна): скопировать в текущую папку
    DropArea {
        anchors.fill: parent
        enabled: fg.br.mode === "dir"
        onDropped: d => {
            const paths = (d.urls ?? []).map(u => String(u)).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.slice(7)));
            const outside = paths.filter(p => p.substring(0, p.lastIndexOf("/")) !== fg.br.path);
            if (!outside.length) return;
            fg.br.transfer((d.modifiers & Qt.ShiftModifier) ? "move" : "copy", outside, fg.br.path);
            d.accept(Qt.CopyAction);
        }
    }

    GridView {
        id: view
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        clip: true
        focus: true
        model: fg.br.shown
        cellWidth: fg.grid ? width / fg.columns : width
        cellHeight: fg.grid ? fg.tile + 22 : fg.rowH
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: false
        currentIndex: -1
        cacheBuffer: 600

        Keys.onPressed: event => { if (fg.br.key(event)) event.accepted = true; }

        // список: шапка колонок
        header: Item {
            width: view.width
            height: fg.grid ? 6 : 30
            visible: !fg.grid
            RowLayout {
                visible: !fg.grid
                anchors.fill: parent
                anchors.leftMargin: 44
                anchors.rightMargin: 12
                Text { Layout.fillWidth: true; text: I18n.tr("Name"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSize - 3; font.bold: true }
                Text { Layout.preferredWidth: 90; text: I18n.tr("Size"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSize - 3; font.bold: true; horizontalAlignment: Text.AlignRight }
                Text { Layout.preferredWidth: 150; text: I18n.tr("Modified"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSize - 3; font.bold: true; horizontalAlignment: Text.AlignRight }
            }
        }

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool selected: !!fg.br.sel[modelData.path]
            readonly property bool renaming: fg.br.renaming === modelData.path
            readonly property bool image: !modelData.dir && fg.br.isImage(modelData.name)
            readonly property string thumbKind: modelData.dir || fg.remote ? "" : FileThumbs.kind(modelData.name)
            readonly property string thumbKey: thumbKind ? FileThumbs.key(modelData.path, String(modelData.mtime)) : ""
            readonly property string thumb: thumbKey ? (FileThumbs.ready[thumbKey] ?? "") : ""
            onThumbKeyChanged: if (thumbKey) Qt.callLater(() => FileThumbs.request(modelData.path, String(modelData.mtime)))
            Component.onCompleted: if (thumbKey) Qt.callLater(() => FileThumbs.request(modelData.path, String(modelData.mtime)))
            readonly property bool cut: fg.br.clip.mode === "move" && fg.br.clip.paths.includes(modelData.path)

            width: view.cellWidth
            height: view.cellHeight
            opacity: cut || modelData.name.startsWith(".") ? 0.55 : 1

            Rectangle {
                anchors.fill: parent
                anchors.margins: fg.grid ? 4 : 1
                radius: fg.grid ? 12 : 8
                color: cell.selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                    : cellArea.containsMouse || folderDrop.containsDrag ? Theme.surfaceHi : "transparent"
                border.width: fg.br.cur === cell.index && view.activeFocus ? 1 : 0
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
            }

            // значок или миниатюра
            Item {
                id: pic
                x: fg.grid ? (cell.width - width) / 2 : 12
                y: fg.grid ? 10 : (cell.height - height) / 2
                width: fg.grid ? fg.tile - 34 : 22
                height: width

                IconImage {
                    anchors.centerIn: parent
                    visible: thumbImg.status !== Image.Ready
                    implicitSize: parent.width
                    source: Quickshell.iconPath(fg.br.iconFor(cell.modelData), "text-x-generic")
                }
                Image {
                    id: thumbImg
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: !fg.grid && fg.zoom < 1.5 ? "" : cell.image && !fg.remote ? "file://" + cell.modelData.path : cell.thumb ? "file://" + cell.thumb : ""
                    sourceSize.width: 256
                    sourceSize.height: 256
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                }
                // ярлык
                Text {
                    visible: cell.thumbKind === "video" && thumbImg.status === Image.Ready && fg.grid
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF040A)
                    color: "white"
                    style: Text.Outline
                    styleColor: "#80000000"
                    font.family: Theme.font
                    font.pixelSize: parent.width / 4
                }
            }

            // имя (и где лежит — в поиске и корзине)
            Column {
                visible: fg.grid && !cell.renaming
                x: 6
                y: pic.y + pic.height + 6
                width: cell.width - 12
                Text {
                    width: parent.width
                    text: cell.modelData.name
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: cell.selected ? 4 : 2
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    visible: !!cell.modelData.sub
                    width: parent.width
                    text: cell.modelData.sub ?? ""
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 4
                }
            }
            RowLayout {
                visible: !fg.grid && !cell.renaming
                anchors.fill: parent
                anchors.leftMargin: 44
                anchors.rightMargin: 12
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    text: cell.modelData.name + (cell.modelData.sub ? `   ${cell.modelData.sub}` : "")
                    elide: Text.ElideMiddle
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                Text {
                    Layout.preferredWidth: 90
                    horizontalAlignment: Text.AlignRight
                    text: cell.modelData.dir ? "" : fg.br.human(cell.modelData.size)
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    Layout.preferredWidth: 150
                    horizontalAlignment: Text.AlignRight
                    text: fg.br.when(cell.modelData.mtime)
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            // переименование на месте
            Rectangle {
                visible: cell.renaming
                x: fg.grid ? 4 : 40
                y: fg.grid ? pic.y + pic.height + 2 : 3
                width: fg.grid ? cell.width - 8 : cell.width - 52
                height: fg.grid ? 28 : cell.height - 6
                radius: 7
                color: Theme.surfaceHi
                border.width: 1
                border.color: Theme.accent
                TextInput {
                    id: renameField
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: fg.grid ? TextInput.AlignHCenter : TextInput.AlignLeft
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                    clip: true
                    onVisibleChanged: if (visible) {
                        text = cell.modelData.name;
                        forceActiveFocus();
                        // имя без расширения
                        const dot = cell.modelData.dir ? -1 : text.lastIndexOf(".");
                        select(0, dot > 0 ? dot : text.length);
                    }
                    onAccepted: { fg.br.rename(cell.modelData, text); fg.forceFocus(); }
                    onActiveFocusChanged: if (!activeFocus && cell.renaming) fg.br.rename(cell.modelData, text)
                    Keys.onEscapePressed: { fg.br.renaming = ""; fg.forceFocus(); }
                }
            }

            MouseArea {
                id: cellArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                property point p0
                property bool dragging: false
                onPressed: mouse => {
                    fg.forceFocus();
                    p0 = Qt.point(mouse.x, mouse.y);
                    dragging = false;
                    if (mouse.button === Qt.RightButton) {
                        if (!cell.selected) fg.br.selectOnly(cell.index);
                    } else if (mouse.button === Qt.LeftButton && !cell.selected) {
                        fg.br.clickItem(cell.index, mouse.modifiers);
                    }
                }
                onPositionChanged: mouse => {
                    if (!pressed || dragging || !(pressedButtons & Qt.LeftButton)) return;
                    if (Math.abs(mouse.x - p0.x) + Math.abs(mouse.y - p0.y) > 10) {
                        dragging = true;
                        fg.startDrag();
                    }
                }
                onReleased: mouse => {
                    if (dragging) return;
                    if (mouse.button === Qt.LeftButton && cell.selected && !(mouse.modifiers & Qt.ShiftModifier))
                        fg.br.clickItem(cell.index, mouse.modifiers);
                }
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        const p = mapToItem(fg.br, mouse.x, mouse.y);
                        fg.br.itemMenu(p.x, p.y);
                    } else if (mouse.button === Qt.MiddleButton && cell.modelData.dir) {
                        fg.br.go(cell.modelData.path);
                    }
                }
                onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) fg.br.openItem(cell.modelData); }
            }

            // бросить на папку — переместить в неё (Ctrl — скопировать)
            DropArea {
                id: folderDrop
                anchors.fill: parent
                enabled: cell.modelData.dir && fg.br.mode !== "trash"
                onDropped: d => {
                    const paths = (d.urls ?? []).map(u => String(u)).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.slice(7)))
                        .filter(p => p !== cell.modelData.path);
                    if (!paths.length) return;
                    fg.br.transfer((d.modifiers & Qt.ControlModifier) ? "copy" : "move", paths, cell.modelData.path);
                    d.accept(Qt.MoveAction);
                }
            }
        }

        // пустое место: снять выделение, рамкой выделить, правый клик — меню папки
        MouseArea {
            id: empty
            z: -1
            width: view.width
            height: Math.max(view.height, view.contentHeight)
            y: view.originY
            parent: view.contentItem
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property point p0
            property bool band: false
            onPressed: mouse => {
                fg.forceFocus();
                fg.br.renaming = "";
                p0 = Qt.point(mouse.x, mouse.y);
                band = false;
                if (mouse.button === Qt.LeftButton && !(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) fg.br.clearSel();
            }
            onPositionChanged: mouse => {
                if (!(pressedButtons & Qt.LeftButton)) return;
                band = true;
                const r = Qt.rect(Math.min(p0.x, mouse.x), Math.min(p0.y, mouse.y), Math.abs(mouse.x - p0.x), Math.abs(mouse.y - p0.y));
                rubber.x = r.x; rubber.y = r.y; rubber.width = r.width; rubber.height = r.height;
                // элементы, задетые рамкой
                const s = {};
                for (let i = 0; i < fg.br.shown.length; i++) {
                    const it = view.itemAtIndex(i);
                    if (!it) continue;
                    if (it.x < r.x + r.width && it.x + it.width > r.x && it.y < r.y + r.height && it.y + it.height > r.y) s[fg.br.shown[i].path] = true;
                }
                fg.br.sel = s;
            }
            onReleased: band = false
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    fg.br.clearSel();
                    const p = mapToItem(fg.br, mouse.x, mouse.y);
                    fg.br.folderMenu(p.x, p.y);
                }
            }
        }
        Rectangle {
            id: rubber
            parent: view.contentItem
            visible: empty.band
            z: 10
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
            border.width: 1
            border.color: Theme.accent
            radius: 4
        }
    }

    // пусто
    Column {
        anchors.centerIn: parent
        visible: fg.br.shown.length === 0
        spacing: 10
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String.fromCodePoint(fg.br.mode === "search" ? 0xF0349 : fg.br.mode === "trash" ? 0xF0A7A : 0xF0256)
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 64
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr(fg.br.mode === "search" ? (fg.br.searching ? "Searching…" : "Nothing found")
                : fg.br.mode === "trash" ? "The trash is empty" : fg.br.filter ? "Nothing found" : "The folder is empty")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
    }
}
