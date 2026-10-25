import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services

// файлы сеткой или списком, как в Nautilus: выделение (щелчок, Ctrl, Shift, рамкой), перетаскивание наружу
// и на папки, бросить файлы из других программ — скопировать сюда, правый щелчок — меню, в списке — звёздочки
Item {
    id: fg

    required property var br

    readonly property bool grid: (br.cfg.view ?? "grid") === "grid"
    readonly property real zoom: br.cfg.zoom ?? 1
    readonly property int iconSize: grid ? Math.round(80 * zoom) : Math.round(28 * zoom)
    readonly property int columns: grid ? Math.max(1, Math.floor(view.width / (iconSize + 52))) : 1
    readonly property int rowH: iconSize + 18
    readonly property bool remote: br.path.includes("/gvfs/")
    readonly property bool singleClick: br.cfg.singleClick ?? false
    // колонки списка
    readonly property int colSize: 96
    readonly property int colDate: 150
    readonly property int colStar: 44

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

    // ── бросили файлы сюда (из другой программы или другого окна): скопировать в текущую папку
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

    // заголовок колонки списка: щелчок — сортировать по ней, ещё раз — в обратную сторону
    component ColHead: Rectangle {
        id: ch
        property string label
        property string field
        property int align: Text.AlignLeft
        readonly property bool current: (fg.br.cfg.sort ?? "name") === field
        height: parent.height
        color: chArea.containsMouse ? FStyle.hover : "transparent"
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: ch.align === Text.AlignLeft ? parent.left : undefined
            anchors.right: ch.align === Text.AlignRight ? parent.right : undefined
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 4
            Text {
                text: ch.label
                color: ch.current ? Theme.fg : Theme.dim
                font.family: FStyle.ui
                font.pixelSize: FStyle.fsSmall
                font.weight: Font.DemiBold
            }
            Text {
                visible: ch.current
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint((fg.br.cfg.reverse ?? false) ? 0xF0143 : 0xF0140)
                color: Theme.fg
                font.family: FStyle.glyphs
                font.pixelSize: FStyle.fsSmall
            }
        }
        MouseArea {
            id: chArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (ch.current) Settings.setFiles("reverse", !(fg.br.cfg.reverse ?? false));
                else {
                    Settings.setFiles("sort", ch.field);
                    Settings.setFiles("reverse", false);
                }
            }
        }
    }

    // список: шапка колонок (над списком — остаётся на месте при прокрутке)
    Item {
        id: colHead
        visible: !fg.grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        height: fg.grid ? 0 : 34
        ColHead {
            x: 0
            width: parent.width - fg.colSize - fg.colDate - fg.colStar
            label: I18n.tr("Name")
            field: "name"
        }
        ColHead {
            x: parent.width - fg.colSize - fg.colDate - fg.colStar
            width: fg.colSize
            label: I18n.tr("Size")
            field: "size"
            align: Text.AlignRight
        }
        ColHead {
            x: parent.width - fg.colDate - fg.colStar
            width: fg.colDate
            label: I18n.tr("Modified")
            field: "time"
            align: Text.AlignRight
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: FStyle.sep
        }
    }

    GridView {
        id: view
        anchors.fill: parent
        anchors.topMargin: colHead.height
        anchors.leftMargin: fg.grid ? 12 : 8
        anchors.rightMargin: fg.grid ? 12 : 8
        clip: true
        focus: true
        model: fg.br.shown
        cellWidth: fg.grid ? width / fg.columns : width
        cellHeight: fg.grid ? fg.iconSize + 76 : fg.rowH
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: false
        currentIndex: -1
        cacheBuffer: 600

        Keys.onPressed: event => { if (fg.br.key(event)) event.accepted = true; }

        header: Item {
            width: view.width
            height: fg.grid ? 8 : 0
        }

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool selected: !!fg.br.sel[modelData.path]
            readonly property bool renaming: fg.br.renaming === modelData.path
            readonly property bool image: !modelData.dir && fg.br.isImage(modelData.name)
            readonly property bool thumbsOn: (fg.br.cfg.thumbs ?? true) && (!fg.remote || (fg.br.cfg.remoteThumbs ?? false))
            readonly property bool thumbWanted: thumbsOn && fg.iconSize >= 32
            readonly property string thumbKind: modelData.dir || !thumbWanted ? "" : FileThumbs.kind(modelData.name)
            readonly property string thumbKey: thumbKind ? FileThumbs.key(modelData.path, String(modelData.mtime)) : ""
            readonly property string thumb: thumbKey ? (FileThumbs.ready[thumbKey] ?? "") : ""
            onThumbKeyChanged: if (thumbKey) Qt.callLater(() => FileThumbs.request(modelData.path, String(modelData.mtime)))
            Component.onCompleted: if (thumbKey) Qt.callLater(() => FileThumbs.request(modelData.path, String(modelData.mtime)))
            readonly property bool cut: fg.br.clip.mode === "move" && fg.br.clip.paths.includes(modelData.path)
            readonly property bool starred: fg.br.isStarred(modelData.path)

            width: view.cellWidth
            height: view.cellHeight
            opacity: cut || modelData.name.startsWith(".") ? 0.55 : 1

            Rectangle {
                anchors.fill: parent
                anchors.margins: fg.grid ? 3 : 0
                anchors.topMargin: fg.grid ? 3 : 1
                anchors.bottomMargin: fg.grid ? 3 : 1
                radius: fg.grid ? 12 : 8
                color: cell.selected ? (cellArea.containsMouse ? FStyle.selHover : FStyle.sel)
                    : cellArea.containsMouse || folderDrop.containsDrag ? FStyle.hover : "transparent"
                border.width: fg.br.cur === cell.index && view.activeFocus && fg.br.keyboardUsed ? 2 : 0
                border.color: FStyle.alpha(Theme.accent, 0.7)
            }

            // значок или миниатюра
            Item {
                id: pic
                x: fg.grid ? (cell.width - width) / 2 : 12
                y: fg.grid ? 12 : (cell.height - height) / 2
                width: fg.iconSize
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
                    source: !cell.thumbWanted ? "" : cell.image ? "file://" + cell.modelData.path : cell.thumb ? "file://" + cell.thumb : ""
                    sourceSize.width: 256
                    sourceSize.height: 256
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                }
                // тонкая рамка вокруг миниатюры, как в Nautilus
                Rectangle {
                    visible: thumbImg.visible && fg.iconSize >= 48
                    anchors.centerIn: parent
                    width: thumbImg.paintedWidth + 2
                    height: thumbImg.paintedHeight + 2
                    color: "transparent"
                    radius: 3
                    border.width: 1
                    border.color: FStyle.sep
                }
                Text {
                    visible: cell.thumbKind === "video" && thumbImg.status === Image.Ready
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF040A)
                    color: "white"
                    style: Text.Outline
                    styleColor: "#80000000"
                    font.family: FStyle.glyphs
                    font.pixelSize: Math.max(14, parent.width / 4)
                }
                // звезда в углу значка (сетка)
                Text {
                    visible: fg.grid && cell.starred
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -4
                    text: String.fromCodePoint(0xF04CE)
                    color: Theme.warn
                    style: Text.Outline
                    styleColor: FStyle.view
                    font.family: FStyle.glyphs
                    font.pixelSize: Math.max(14, fg.iconSize / 5)
                }
            }

            // ── сетка: имя под значком (и где лежит — в поиске, корзине, недавних)
            Column {
                visible: fg.grid && !cell.renaming
                x: 8
                y: pic.y + pic.height + 8
                width: cell.width - 16
                spacing: 1
                Text {
                    width: parent.width
                    text: cell.modelData.name
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: cell.selected ? 4 : 2
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fs - 1
                }
                Text {
                    visible: !!cell.modelData.sub
                    width: parent.width
                    text: cell.modelData.sub ?? ""
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    color: Theme.dim
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fsSmall - 1
                }
            }

            // ── список: имя | размер | изменён | звезда
            Item {
                visible: !fg.grid && !cell.renaming
                anchors.fill: parent
                Column {
                    x: pic.x + pic.width + 12
                    width: parent.width - x - fg.colSize - fg.colDate - fg.colStar
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width
                        text: cell.modelData.name
                        elide: Text.ElideMiddle
                        color: Theme.fg
                        font.family: FStyle.ui
                        font.pixelSize: FStyle.fs
                    }
                    Text {
                        visible: !!cell.modelData.sub
                        width: parent.width
                        text: cell.modelData.sub ?? ""
                        elide: Text.ElideMiddle
                        color: Theme.dim
                        font.family: FStyle.ui
                        font.pixelSize: FStyle.fsSmall
                    }
                }
                Text {
                    x: parent.width - fg.colSize - fg.colDate - fg.colStar
                    width: fg.colSize - 10
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: cell.modelData.dir ? "" : fg.br.human(cell.modelData.size)
                    color: Theme.dim
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fs - 1
                }
                Text {
                    x: parent.width - fg.colDate - fg.colStar
                    width: fg.colDate - 10
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: fg.br.when(cell.modelData.mtime)
                    color: Theme.dim
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fs - 1
                }
                Text {
                    visible: cell.starred || cellArea.containsMouse || starArea.containsMouse
                    x: parent.width - fg.colStar
                    width: fg.colStar
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: String.fromCodePoint(cell.starred ? 0xF04CE : 0xF04D2)
                    color: cell.starred ? Theme.warn : starArea.containsMouse ? Theme.fg : Theme.dim
                    font.family: FStyle.glyphs
                    font.pixelSize: FStyle.icon + 1
                }
            }

            // переименование на месте
            Rectangle {
                visible: cell.renaming
                x: fg.grid ? 4 : pic.x + pic.width + 6
                y: fg.grid ? pic.y + pic.height + 4 : 4
                width: fg.grid ? cell.width - 8 : cell.width - x - fg.colSize - fg.colDate - fg.colStar
                height: fg.grid ? 32 : cell.height - 8
                radius: 8
                color: FStyle.view
                border.width: 2
                border.color: FStyle.alpha(Theme.accent, 0.8)
                TextInput {
                    id: renameField
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: fg.grid ? TextInput.AlignHCenter : TextInput.AlignLeft
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fs - 1
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
                cursorShape: fg.singleClick ? Qt.PointingHandCursor : Qt.ArrowCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                property point p0
                property bool dragging: false
                onPressed: mouse => {
                    fg.forceFocus();
                    fg.br.keyboardUsed = false;
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
                        fg.br.newWindowRequested(cell.modelData.path);
                    } else if (mouse.button === Qt.LeftButton && fg.singleClick && !dragging
                               && !(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) {
                        fg.br.openItem(cell.modelData);
                    }
                }
                onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton && !fg.singleClick) fg.br.openItem(cell.modelData); }
            }
            // звезда в списке
            MouseArea {
                id: starArea
                visible: !fg.grid && fg.br.mode !== "trash"
                x: parent.width - fg.colStar
                width: fg.colStar
                height: parent.height
                hoverEnabled: true
                onClicked: fg.br.toggleStar([cell.modelData.path])
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

        // пустое место: снять выделение, рамкой выделить, правый щелчок — меню папки
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
            color: FStyle.alpha(Theme.accent, 0.15)
            border.width: 1
            border.color: Theme.accent
            radius: 4
        }
    }

    // пусто — как страница состояния Adwaita
    Column {
        anchors.centerIn: parent
        visible: fg.br.shown.length === 0 && !fg.br.loading
        width: Math.min(parent.width - 48, 420)
        spacing: 12
        readonly property var page: fg.br.mode === "search" ? (fg.br.searching ? [0xF0349, "Searching…", ""] : [0xF0349, "No Results Found", "Try a different search"])
            : fg.br.mode === "trash" ? [0xF0A7A, "Trash is Empty", ""]
            : fg.br.mode === "recent" ? [0xF0150, "No Recent Files", "Files you open appear here"]
            : fg.br.mode === "starred" ? [0xF04D2, "No Starred Files", "Star files and folders to see them here"]
            : fg.br.filter ? [0xF0349, "No Results Found", ""]
            : [0xF0256, "Folder is Empty", ""]
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String.fromCodePoint(parent.page[0])
            color: FStyle.alpha(Theme.fg, 0.35)
            font.family: FStyle.glyphs
            font.pixelSize: 96
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr(parent.page[1])
            color: Theme.fg
            font.family: FStyle.ui
            font.pixelSize: FStyle.fs + 8
            font.weight: Font.Bold
        }
        Text {
            visible: text !== ""
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: I18n.tr(parent.page[2])
            color: Theme.dim
            font.family: FStyle.ui
            font.pixelSize: FStyle.fs
        }
    }
}
