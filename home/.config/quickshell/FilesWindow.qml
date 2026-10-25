import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.files

// проводник «Файлы»: qs ipc call files open [путь] (Super+E, rexilone-files, «Файлы» в меню приложений).
// Как в Nautilus, каждое «открыть» — новое окно; окна создаются при открытии и уничтожаются при закрытии
Scope {
    id: ctl

    property var wins: []          // номера открытых окон
    property var starts: ({})      // номер → { path, reveal, prefs }
    property int nextId: 1

    // путь или file:// URI → путь
    function clean(p) {
        p = (p ?? "").trim();
        if (p.startsWith("file://")) p = decodeURIComponent(p.slice(7));
        if (p.startsWith("~")) p = Quickshell.env("HOME") + p.slice(1);
        return p;
    }

    function newWindow(path, reveal, prefs) {
        const id = nextId++;
        const s = Object.assign({}, starts);
        s[id] = { path: clean(path), reveal: clean(reveal ?? ""), prefs: !!prefs };
        starts = s;
        wins = wins.concat([id]);
    }
    function closeWindow(id) {
        wins = wins.filter(w => w !== id);
    }

    IpcHandler {
        target: "files"

        function open(path: string): void { ctl.newWindow(path); }
        // показать файл в его папке, выделенным («Показать в папке» из браузеров — rexilone-filemanager1)
        function reveal(path: string): void {
            const p = ctl.clean(path);
            ctl.newWindow(p.substring(0, p.lastIndexOf("/")) || "/", p);
        }
        // окно с открытыми параметрами проводника
        function prefs(): void { ctl.newWindow("", "", true); }
        function toggle(): void { if (ctl.wins.length) ctl.wins = []; else ctl.newWindow(""); }
        function hide(): void { ctl.wins = []; }
    }

    Variants {
        model: ctl.wins

        FloatingWindow {
            id: win

            required property var modelData
            readonly property var start: ctl.starts[modelData] ?? {}

            title: browser.title
            visible: true
            implicitWidth: 1180
            implicitHeight: 760
            minimumSize: Qt.size(560, 400)
            color: "transparent"

            onVisibleChanged: if (!visible) ctl.closeWindow(modelData)

            BackgroundEffect.blurRegion: Theme.blurOn ? blurReg : null
            Region {
                id: blurReg
                item: browser
            }

            Browser {
                id: browser
                anchors.fill: parent
                startPath: win.start.path ?? ""
                revealPath: win.start.reveal ?? ""
                startPrefs: win.start.prefs ?? false
                onCloseRequested: win.visible = false
                onNewWindowRequested: p => ctl.newWindow(p)
                onQuitRequested: ctl.wins = []
            }
        }
    }
}
