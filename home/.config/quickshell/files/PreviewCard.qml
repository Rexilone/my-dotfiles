import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.screenshot

// быстрый просмотр (пробел): картинка, первый кадр видео, первая страница PDF, начало текста; ←/→ — соседний файл
Item {
    id: pv

    required property var br

    readonly property var it: br.shown[br.cur] ?? br.selItems[0] ?? null
    readonly property bool image: !!it && !it.dir && br.isImage(it.name)
    readonly property string kind: it && !it.dir ? FileThumbs.kind(it.name) : ""
    readonly property string thumbKey: visible && kind ? FileThumbs.key(it.path, String(it.mtime)) : ""
    readonly property string thumb: thumbKey ? (FileThumbs.ready[thumbKey] ?? "") : ""
    onThumbKeyChanged: if (thumbKey) Qt.callLater(() => FileThumbs.request(it.path, String(it.mtime)))
    readonly property bool textLike: !!it && !it.dir && !image && !kind && (it.size ?? 0) < 5000000
    property string text: ""

    onItChanged: load()
    onVisibleChanged: load()
    function load() {
        text = "";
        if (!visible || !it) return;
        if (it.dir) {
            reader.command = ["sh", "-c", 'n=$(ls -A -- "$1" 2>/dev/null | wc -l); echo "$n"; ls -A -- "$1" 2>/dev/null | head -40', "sh", it.path];
            reader.running = true;
        } else if (textLike) {
            // только если это текст: file --mime
            reader.command = ["sh", "-c", 'case "$(file -b --mime-encoding -- "$1")" in binary) exit 0;; esac; head -c 60000 -- "$1"', "sh", it.path];
            reader.running = true;
        }
    }
    Process {
        id: reader
        stdout: StdioCollector { onStreamFinished: pv.text = text }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: pv.br.showPreview = false }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 980)
        height: Math.min(parent.height - 60, 700)
        radius: 18
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                IconImage {
                    implicitSize: 22
                    source: pv.it ? Quickshell.iconPath(pv.br.iconFor(pv.it), "text-x-generic") : ""
                }
                Text {
                    Layout.fillWidth: true
                    text: pv.it?.name ?? ""
                    elide: Text.ElideMiddle
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }
                Text {
                    text: pv.it ? [pv.it.dir ? "" : pv.br.human(pv.it.size), pv.br.when(pv.it.mtime)].filter(x => x).join("   ·   ") : ""
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                ToolButton { icon: 0xF0DCE; label: "Open"; active: true; onClicked: { pv.br.showPreview = false; pv.br.openItem(pv.it); } }
                ToolButton { icon: 0xF0156; tip: "Close"; key: "Space"; onClicked: pv.br.showPreview = false }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: Theme.bg
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: pv.image || pv.thumb !== ""
                    source: pv.image ? "file://" + pv.it.path : pv.thumb ? "file://" + pv.thumb : ""
                    sourceSize.width: 1600
                    sourceSize.height: 1200
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 14
                    visible: !pv.image && !pv.thumb && pv.text !== ""
                    contentHeight: txt.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Text {
                        id: txt
                        width: parent.width
                        text: pv.it?.dir ? `${I18n.tr("Inside")}: ${pv.text.split("\n")[0]}\n\n${pv.text.split("\n").slice(1).join("\n")}` : pv.text
                        wrapMode: Text.WrapAnywhere
                        color: Theme.fg
                        font.family: Settings.monoFont || Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        textFormat: Text.PlainText
                    }
                }
                Column {
                    anchors.centerIn: parent
                    visible: !pv.image && !pv.thumb && pv.text === ""
                    spacing: 10
                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitSize: 128
                        source: pv.it ? Quickshell.iconPath(pv.br.iconFor(pv.it), "text-x-generic") : ""
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr(pv.kind ? "Making a preview…" : "No preview — press Enter to open")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }
        }
    }
}
