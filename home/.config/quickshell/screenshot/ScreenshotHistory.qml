import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// история скриншотов (Ctrl+Print): сохранённые снимки с поиском по тексту на них.
// Текст распознаётся в фоне после сохранения (scripts/shot-analyze.py text).
Scope {
    id: root

    required property var ctl

    property var items: []        // [{ path, time, text }], новые — первыми
    property string query: ""

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        return q ? items.filter(i => (i.text + " " + i.path.split("/").pop()).toLowerCase().includes(q)) : items;
    }

    function add(path) {
        items = [{ path, time: Date.now(), text: "" }].concat(items.filter(i => i.path !== path)).slice(0, 300);
        save();
        ocrQueue = ocrQueue.concat([path]);
        if (!ocr.running) ocrNext.restart();
    }

    function save() {
        store.setText(JSON.stringify({ items }));
    }

    // ── распознать текст сохранённых снимков по очереди
    property var ocrQueue: []
    Timer {
        id: ocrNext
        interval: 1200       // файл копируется в фоне — дать ему появиться
        onTriggered: {
            if (!root.ocrQueue.length) return;
            ocr.path = root.ocrQueue[0];
            root.ocrQueue = root.ocrQueue.slice(1);
            ocr.command = ["nice", "-n", "19", "python3", Quickshell.shellDir + "/scripts/shot-analyze.py", "text", ocr.path];
            ocr.running = true;
        }
    }
    Process {
        id: ocr
        property string path: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let words = [];
                try { words = JSON.parse(text); } catch (e) {}
                const t = words.map(w => w.text).join(" ");
                root.items = root.items.map(i => i.path === ocr.path ? Object.assign({}, i, { text: t }) : i);
                root.save();
            }
        }
        onExited: if (root.ocrQueue.length) ocrNext.restart()
    }

    FileView {
        id: store
        path: Quickshell.statePath("screenshot-history.json")
        printErrors: false
        onLoaded: {
            try { root.items = JSON.parse(text()).items ?? []; } catch (e) {}
        }
        // истории ещё нет — взять последние снимки из папки, текст распознается в фоне
        onLoadFailed: seed.running = true
    }

    Process {
        id: seed
        command: ["sh", "-c", 'ls -t "$1"/*.png 2>/dev/null | head -50 | while IFS= read -r f; do printf "%s\t%s\n" "$f" "$(stat -c %Y "$f")"; done',
                  "sh", root.ctl.shotsDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(l => l).map(l => {
                    const [path, t] = l.split("\t");
                    return { path, time: parseInt(t) * 1000, text: "" };
                });
                if (!list.length) return;
                root.items = list;
                root.save();
                root.ocrQueue = list.map(i => i.path);
                ocrNext.restart();
            }
        }
    }

    // при открытии — убрать удалённые файлы
    Process {
        id: prune
        stdout: StdioCollector {
            onStreamFinished: {
                const alive = new Set(text.split("\n").filter(x => x));
                const before = root.items.length;
                root.items = root.items.filter(i => alive.has(i.path));
                if (root.items.length !== before) root.save();
            }
        }
    }

    Connections {
        target: root.ctl
        function onHistoryOpenChanged() {
            if (!root.ctl.historyOpen) return;
            root.query = "";
            prune.command = ["sh", "-c", 'for f; do [ -e "$f" ] && printf "%s\\n" "$f"; done', "sh"].concat(root.items.map(i => i.path));
            prune.running = true;
        }
    }

    function copyItem(it) {
        Quickshell.execDetached(["sh", "-c", 'wl-copy -t image/png < "$1"', "sh", it.path]);
        ctl.notify(I18n.tr("Screenshot copied"), it.path.split("/").pop(), it.path);
        ctl.historyOpen = false;
    }

    function when(t) {
        const d = new Date(t);
        return Qt.locale(I18n.locale).toString(d, new Date().toDateString() === d.toDateString() ? "HH:mm" : "d MMM, HH:mm");
    }

    PanelWindow {
        id: win

        visible: root.ctl.historyOpen
        screen: Settings.activeScreen()
        color: "transparent"
        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-screenshot-history"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.45
            MouseArea {
                anchors.fill: parent
                onClicked: root.ctl.historyOpen = false
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 980)
            height: Math.min(parent.height - 80, 680)
            radius: 18
            color: Theme.surface
            border.width: 1
            border.color: Theme.line

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: I18n.tr("Screenshots")
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 6
                        font.bold: true
                    }
                    Text {
                        text: root.shown.length
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                    // поиск по тексту на снимках
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 9
                        color: Theme.surfaceHi
                        border.width: 1
                        border.color: search.activeFocus ? Theme.accent : Theme.surfaceHi2

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(0xF0349)
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize
                        }
                        Text {
                            visible: !search.text
                            anchors.left: parent.left
                            anchors.leftMargin: 36
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Search by text on screenshots")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }
                        TextInput {
                            id: search
                            anchors.fill: parent
                            anchors.leftMargin: 36
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            focus: win.visible
                            onTextChanged: root.query = text
                            Keys.onEscapePressed: root.ctl.historyOpen = false
                            Keys.onReturnPressed: if (root.shown.length) root.copyItem(root.shown[0])
                        }
                    }
                    ToolButton {
                        icon: 0xF024F
                        tip: "Open folder"
                        onClicked: {
                            Quickshell.execDetached(["xdg-open", root.ctl.shotsDir]);
                            root.ctl.historyOpen = false;
                        }
                    }
                    ToolButton {
                        icon: 0xF0156
                        tip: "Close"
                        key: "Esc"
                        onClicked: root.ctl.historyOpen = false
                    }
                }

                Text {
                    visible: !root.shown.length
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: I18n.tr(root.query ? "Nothing found" : "No screenshots yet")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }

                GridView {
                    id: grid
                    visible: root.shown.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 230)))
                    cellHeight: cellWidth * 0.62 + 44
                    model: root.shown

                    delegate: Item {
                        id: cell
                        required property var modelData
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 12
                            color: cellArea.containsMouse ? Theme.surfaceHi2 : Theme.surfaceHi

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 5

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 8
                                    color: Theme.bg
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: "file://" + cell.modelData.path
                                        sourceSize.width: 360
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: cell.modelData.text ? cell.modelData.text : "—"
                                        elide: Text.ElideRight
                                        color: Theme.muted
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 3
                                    }
                                    Text {
                                        text: root.when(cell.modelData.time)
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 3
                                    }
                                }
                            }
                        }
                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    Quickshell.execDetached(["xdg-open", cell.modelData.path]);
                                    root.ctl.historyOpen = false;
                                } else root.copyItem(cell.modelData);
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Click — copy   ·   right click — open   ·   Enter — copy the first one")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }
}
