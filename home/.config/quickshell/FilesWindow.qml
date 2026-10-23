import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.files

// проводник: qs ipc call files open [путь] (Super+E, rexilone-files, «Файлы» в меню приложений)
// окно создаётся при открытии и уничтожается при закрытии, как Настройки
Scope {
    id: ctl

    property bool open: false
    property string startPath: ""

    // путь или file:// URI → путь
    function clean(p) {
        p = (p ?? "").trim();
        if (p.startsWith("file://")) p = decodeURIComponent(p.slice(7));
        if (p.startsWith("~")) p = Quickshell.env("HOME") + p.slice(1);
        return p;
    }

    function show(path) {
        const p = clean(path);
        if (open && loader.item) {
            if (p) loader.item.browser.go(p);
            return;
        }
        startPath = p;
        open = true;
    }

    IpcHandler {
        target: "files"

        function open(path: string): void { ctl.show(path); }
        function toggle(): void { if (ctl.open) ctl.open = false; else ctl.show(""); }
        function hide(): void { ctl.open = false; }
    }

    LazyLoader {
        id: loader
        active: ctl.open

        FloatingWindow {
            id: win

            property alias browser: browser

            title: "Files"  // на заголовок завязано правило окна в niri — не переводить
            visible: true
            implicitWidth: 1180
            implicitHeight: 760
            minimumSize: Qt.size(640, 420)
            color: Theme.panel

            onVisibleChanged: if (!visible) ctl.open = false

            BackgroundEffect.blurRegion: Theme.blurOn ? blurReg : null
            Region {
                id: blurReg
                item: browser
            }

            Browser {
                id: browser
                anchors.fill: parent
                startPath: ctl.startPath
                onCloseRequested: win.visible = false
            }
        }
    }
}
