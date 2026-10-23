pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// миниатюры видео и PDF для проводника: очередь, по одной за раз (scripts/files.py thumb), кэш по пути и дате
Singleton {
    id: root

    readonly property string dir: Quickshell.cachePath("thumbs")
    property var ready: ({})       // ключ → путь к png
    property var failed: ({})
    property var queue: []

    function kind(name) {
        const ext = name.split(".").pop().toLowerCase();
        if (["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg", "3gp"].includes(ext)) return "video";
        if (ext === "pdf") return "pdf";
        return "";
    }
    function key(path, mtime) {
        return Qt.md5(`${path}|${mtime}`);
    }
    // заказать миниатюру (из обработчиков, не из привязок); готовая появится в ready[key]
    function request(path, mtime) {
        const k = key(path, mtime);
        if (ready[k] || failed[k] || queue.some(q => q.k === k) || job.k === k) return;
        queue = queue.concat([{ k, path }]);
        if (!job.running) next.restart();
    }

    Timer {
        id: next
        interval: 30
        onTriggered: {
            if (!root.queue.length) return;
            const q = root.queue[0];
            root.queue = root.queue.slice(1);
            job.k = q.k;
            job.out = `${root.dir}/${q.k}.png`;
            job.command = ["sh", "-c", '[ -s "$2" ] && echo \'{"ok": true}\' || exec nice -n 15 python3 "$3" thumb "$1" "$2" 256',
                           "sh", q.path, job.out, Quickshell.shellDir + "/scripts/files.py"];
            job.running = true;
        }
    }
    Process {
        id: job
        property string k: ""
        property string out: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.includes('"ok": true')) root.ready = Object.assign({}, root.ready, { [job.k]: job.out });
                else root.failed = Object.assign({}, root.failed, { [job.k]: true });
            }
        }
        onExited: {
            job.k = "";
            if (root.queue.length) next.restart();
        }
    }
}
