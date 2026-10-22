pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// синхронный текст текущей песни (lrclib.net, scripts/lyrics.py): line — строка, которая звучит сейчас
// ищет, только пока кто-то показывает текст (need)
Singleton {
    id: root

    property var consumers: ({})
    readonly property bool active: Object.keys(consumers).length > 0

    function need(id, on) {
        const c = Object.assign({}, consumers);
        if (on) c[id] = true;
        else delete c[id];
        consumers = c;
    }

    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) ?? ps[0] ?? null;
    }
    readonly property string track: player && player.trackTitle ? `${player.trackArtist ?? ""}\n${player.trackTitle}` : ""

    property var lines: []          // [[секунды, строка], …]
    property bool loading: false
    property real position: 0
    property var cache: ({})

    readonly property int index: {
        let i = -1;
        for (let k = 0; k < lines.length && lines[k][0] <= position + 0.25; k++) i = k;
        return i;
    }
    readonly property string line: index >= 0 ? lines[index][1] : ""
    readonly property string next: index + 1 < lines.length ? lines[index + 1][1] : ""

    function load() {
        if (!active || !track) {
            lines = [];
            return;
        }
        if (cache[track] !== undefined) {
            lines = cache[track];
            return;
        }
        lines = [];
        loading = true;
        // идёт поиск прошлой песни — эта подхватится, когда он закончится
        if (fetch.running) return;
        fetch.key = track;
        fetch.command = ["python3", Quickshell.shellDir + "/scripts/lyrics.py", player.trackArtist ?? "", player.trackTitle,
                         player.lengthSupported ? String(Math.round(player.length)) : ""];
        fetch.running = true;
    }

    onTrackChanged: load()
    onActiveChanged: load()

    Process {
        id: fetch
        property string key: ""
        onExited: if (key !== root.track) root.load()
        stdout: StdioCollector {
            onStreamFinished: {
                let l = [];
                try { l = JSON.parse(text); } catch (e) {}
                root.cache = Object.assign({}, root.cache, { [fetch.key]: l });
                root.loading = false;
                if (fetch.key === root.track) root.lines = l;
            }
        }
    }

    // позиция в MPRIS не обновляется сама — опрашиваем, пока играет
    Timer {
        running: root.active && root.lines.length > 0 && (root.player?.isPlaying ?? false)
        interval: 200
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.player.positionChanged();
            root.position = root.player.position;
        }
    }
}
