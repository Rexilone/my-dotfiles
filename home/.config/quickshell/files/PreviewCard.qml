import QtQuick
import QtQuick.Layouts
import QtMultimedia
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
    readonly property bool audio: !!it && !it.dir && /\.(mp3|flac|ogg|opus|wav|m4a|aac|wma)$/i.test(it.name)
    // видео и музыку — играть прямо в просмотре (Настройки → Файлы)
    readonly property bool play: visible && (pv.br.cfg.previewPlay ?? true) && (kind === "video" || audio)
    readonly property bool textLike: !!it && !it.dir && !image && !kind && !audio && (it.size ?? 0) < 5000000
    property string text: ""

    function time(ms) {
        const t = Math.floor((ms ?? 0) / 1000);
        const h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), s = t % 60;
        const p = n => String(n).padStart(2, "0");
        return h ? `${h}:${p(m)}:${p(s)}` : `${m}:${p(s)}`;
    }

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

                // видео и музыка
                MediaPlayer {
                    id: player
                    source: pv.play && pv.it ? "file://" + pv.it.path : ""
                    videoOutput: video
                    audioOutput: AudioOutput {
                        id: sound
                        muted: pv.br.cfg.previewMuted ?? false
                        volume: 0.8
                    }
                    loops: (pv.br.cfg.previewLoop ?? true) ? MediaPlayer.Infinite : 1
                    onSourceChanged: if (source != "") play()
                }
                VideoOutput {
                    id: video
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.bottomMargin: pv.play ? 52 : 8
                    visible: pv.play && pv.kind === "video"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                    }
                }
                Column {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -26
                    visible: pv.play && pv.audio
                    spacing: 10
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String.fromCodePoint(0xF075A)
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 96
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: player.metaData.stringValue(MediaMetaData.Title) || (pv.it?.name ?? "")
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 2
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: player.metaData.stringValue(MediaMetaData.ContributingArtist) || player.metaData.stringValue(MediaMetaData.AlbumArtist) || ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                }
                // панель плеера
                RowLayout {
                    visible: pv.play
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    height: 36
                    spacing: 8
                    ToolButton {
                        icon: player.playbackState === MediaPlayer.PlayingState ? 0xF03E4 : 0xF040A
                        tip: player.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play"
                        onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                    }
                    Text {
                        text: pv.time(player.position)
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    // перемотка
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 20
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.surfaceHi2
                            Rectangle {
                                width: player.duration > 0 ? parent.width * player.position / player.duration : 0
                                height: parent.height
                                radius: 2
                                color: Theme.accent
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function seekTo(x) { if (player.duration > 0) player.position = Math.max(0, Math.min(1, x / width)) * player.duration; }
                            onPressed: mouse => seekTo(mouse.x)
                            onPositionChanged: mouse => { if (pressed) seekTo(mouse.x); }
                        }
                    }
                    Text {
                        text: pv.time(player.duration)
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    ToolButton {
                        icon: sound.muted ? 0xF0581 : 0xF057E
                        tip: sound.muted ? "Sound on" : "Mute"
                        onClicked: sound.muted = !sound.muted
                    }
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: !pv.play && (pv.image || pv.thumb !== "")
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
                    visible: !pv.play && !pv.image && !pv.thumb && pv.text === ""
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
