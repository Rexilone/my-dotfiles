import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// история буфера обмена (cliphist): qs ipc call clipboard toggle
// Enter — скопировать, Delete — удалить запись, Ctrl+Delete — очистить всё, Esc — закрыть
PanelWindow {
    id: root

    property bool open: false
    property bool shown: false
    property string query: ""
    property var entries: []      // { id, type: "text"|"image", text, file }
    property bool confirmWipe: false

    readonly property string cacheDir: Quickshell.cachePath("clipboard")
    readonly property int rows: 7

    readonly property var results: {
        const q = query.trim().toLowerCase();
        if (!q) return entries;
        return entries.filter(e => e.text.toLowerCase().includes(q));
    }

    function refresh() {
        listProc.running = true;
    }

    function copy(e) {
        if (!e) return;
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\t\\n" "$1" | cliphist decode | wl-copy', "sh", e.id]);
        open = false;
    }

    function remove(e) {
        if (!e) return;
        const idx = list.currentIndex;
        entries = entries.filter(x => x.id !== e.id);
        list.currentIndex = Math.min(idx, results.length - 1);
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\t\\n" "$1" | cliphist delete; rm -f "$2"/"$1".*', "sh", e.id, cacheDir]);
    }

    function wipe() {
        if (!confirmWipe) {
            confirmWipe = true;
            return;
        }
        confirmWipe = false;
        entries = [];
        Quickshell.execDetached(["sh", "-c", 'cliphist wipe; wl-copy --clear; rm -rf "$1"', "sh", cacheDir]);
    }

    onOpenChanged: {
        if (open) {
            targetScreen = Settings.activeScreen();
            hideTimer.stop();
            query = "";
            input.text = "";
            confirmWipe = false;
            refresh();
            shown = true;
            input.forceActiveFocus();
        } else {
            hideTimer.restart();
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void { root.open = !root.open; }
        function open(): void { root.open = true; }
        function hide(): void { root.open = false; }
    }

    // список + миниатюры картинок в кэше
    Process {
        id: listProc
        command: ["sh", "-c", `
            dir="$1"; mkdir -p "$dir"
            cliphist list -preview-width 400 | head -n 300 | while IFS="$(printf '\\t')" read -r id rest; do
                case "$rest" in
                    "[[ binary data"*)
                        ext=$(printf '%s' "$rest" | grep -oE 'png|jpe?g|webp|bmp|gif' | head -n1)
                        f="$dir/$id.\${ext:-png}"
                        [ -s "$f" ] || printf '%s\\t\\n' "$id" | cliphist decode > "$f"
                        printf '%s\\timage\\t%s\\t%s\\n' "$id" "$f" "$rest" ;;
                    *)
                        printf '%s\\ttext\\t\\t%s\\n' "$id" "$rest" ;;
                esac
            done`, "sh", root.cacheDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").filter(l => l).map(l => {
                    const [id, type, file, ...rest] = l.split("\t");
                    return { id, type, file, text: rest.join("\t") };
                });
                list.currentIndex = 0;
            }
        }
    }

    Timer {
        id: hideTimer
        interval: Theme.animSlow
        onTriggered: root.shown = false
    }

    // открывается на мониторе, где сейчас курсор/фокус
    property var targetScreen: Settings.activeScreen()
    screen: targetScreen
    visible: shown
    color: "transparent"
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    // размытие только под карточкой (Персонализация → Прозрачность)
    BackgroundEffect.blurRegion: Theme.blurOn ? blurReg : null
    Region {
        id: blurReg
        item: card
        radius: card.radius
    }
    WlrLayershell.namespace: "quickshell-clipboard"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.open ? 0.35 : 0

        Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.18
        width: 600
        height: column.implicitHeight + 24
        radius: Theme.radius + 2
        color: Theme.panel
        border.width: 1
        border.color: Theme.faint

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.96
        transformOrigin: Item.Top

        Behavior on opacity { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: column

            x: 12
            y: 12
            width: parent.width - 24
            spacing: 8

            // поиск + очистка
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 4
                Layout.preferredHeight: 36
                spacing: 12

                Text {
                    text: Icons.clipboard
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize + 2
                }

                TextInput {
                    id: input

                    Layout.fillWidth: true
                    color: Theme.fg
                    selectionColor: Theme.faint
                    selectedTextColor: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 2
                    clip: true
                    focus: true

                    onTextChanged: {
                        root.query = text;
                        list.currentIndex = 0;
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !input.text
                        text: I18n.tr("Search clipboard…")
                        color: Theme.dim
                        font: input.font
                    }

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        const cur = root.results[list.currentIndex];
                        if (event.key === Qt.Key_Escape) root.open = false;
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.copy(cur);
                        else if (event.key === Qt.Key_Delete && ctrl) root.wipe();
                        else if (event.key === Qt.Key_Delete) root.remove(cur);
                        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && event.key === Qt.Key_J)) list.incrementCurrentIndex();
                        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && event.key === Qt.Key_K)) list.decrementCurrentIndex();
                        else return;
                        event.accepted = true;
                    }
                }

                Rectangle {
                    visible: root.entries.length > 0
                    implicitWidth: wipeLabel.implicitWidth + 20
                    implicitHeight: 26
                    radius: 6
                    color: root.confirmWipe ? Qt.rgba(Theme.urgent.r, Theme.urgent.g, Theme.urgent.b, 0.18)
                         : wipeArea.containsMouse ? Theme.faint : "transparent"
                    border.width: root.confirmWipe ? 1 : 0
                    border.color: Theme.urgent

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        id: wipeLabel
                        anchors.centerIn: parent
                        text: root.confirmWipe ? "Confirm clear?" : `${Icons.trash}  Clear all`
                        color: root.confirmWipe ? Theme.urgent : wipeArea.containsMouse ? Theme.fg : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }

                    MouseArea {
                        id: wipeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.wipe()
                        onExited: root.confirmWipe = false
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.faint
            }

            Text {
                visible: root.results.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: I18n.tr(root.entries.length ? "Nothing found" : "Clipboard is empty")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            ListView {
                id: list

                visible: count > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 480)
                clip: true
                spacing: 2
                model: root.results
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 120
                keyNavigationWraps: true

                highlight: Rectangle {
                    radius: 8
                    color: Theme.surfaceHi2
                }

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property bool isImage: modelData.type === "image"

                    width: list.width
                    height: isImage ? 96 : 40

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 12

                        Image {
                            visible: row.isImage
                            Layout.preferredHeight: 80
                            Layout.preferredWidth: 140
                            source: row.isImage ? "file://" + row.modelData.file : ""
                            sourceSize.height: 160
                            fillMode: Image.PreserveAspectFit
                            horizontalAlignment: Image.AlignLeft
                            asynchronous: true
                            cache: false
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.isImage
                                ? row.modelData.text.replace(/^\[\[ binary data /, "").replace(/ \]\]$/, "")
                                : row.modelData.text.trim()
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: row.isImage ? Theme.dim : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: row.isImage ? Theme.fontSize - 1 : Theme.fontSize
                        }

                        // удалить запись
                        Text {
                            text: Icons.close
                            opacity: rowArea.containsMouse || row.ListView.isCurrentItem ? 1 : 0
                            color: delArea.containsMouse ? Theme.urgent : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize

                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                            MouseArea {
                                id: delArea
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.remove(row.modelData)
                            }
                        }
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        anchors.rightMargin: 36
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: list.currentIndex = row.index
                        onClicked: root.copy(row.modelData)
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignRight
                Layout.rightMargin: 4
                text: I18n.tr("Enter — copy · Del — delete · Ctrl+Del — clear all")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }
}
