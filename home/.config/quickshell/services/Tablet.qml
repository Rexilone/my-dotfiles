pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// графический планшет через OpenTabletDriver (otd): экран, рабочая область, поворот.
// Настройки — ~/.config/OpenTabletDriver/settings.json; после правки файл сохраняется
// и применяется к работающему драйверу (`otd loadsettings`). Поворот и область в мм,
// координаты X/Y — центр, как у самого OTD.
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("HOME")}/.config/OpenTabletDriver/settings.json`

    property bool installed: false
    property bool running: false
    property var data: null
    property var displays: []          // [{ index, name, w, h, x, y }] — x, y — левый верхний угол

    readonly property var profile: data?.Profiles?.[0] ?? null
    readonly property bool active: installed && !!profile
    readonly property string tabletName: profile?.Tablet ?? ""
    readonly property var area: profile?.AbsoluteModeSettings?.Tablet ?? null      // { Width, Height, X, Y, Rotation }
    readonly property var display: profile?.AbsoluteModeSettings?.Display ?? null  // { Width, Height, X, Y }

    // полный размер планшета в мм: запоминаем его, пока область — весь планшет (так OTD ставит по умолчанию)
    readonly property real maxW: Settings.input?.tablet?.otdMaxW || area?.Width || 216
    readonly property real maxH: Settings.input?.tablet?.otdMaxH || area?.Height || 135

    // выбранный экран: имя вывода или "" — все мониторы
    readonly property string screen: {
        if (!display) return "";
        const d = displays.find(d => d.index > 0 && Math.abs(d.x + d.w / 2 - display.X) < 2 && Math.abs(d.y + d.h / 2 - display.Y) < 2
            && Math.abs(d.w - display.Width) < 2 && Math.abs(d.h - display.Height) < 2);
        return d ? d.name : "";
    }

    // пропорции экрана с учётом поворота области
    function displayAspect() {
        if (!display) return 16 / 9;
        const r = Number(area?.Rotation ?? 0);
        const a = display.Width / display.Height;
        return r === 90 || r === 270 ? 1 / a : a;
    }

    function edit(fn) {
        if (!data) return;
        const d = JSON.parse(JSON.stringify(data));
        fn(d.Profiles[0].AbsoluteModeSettings);
        data = d;
        applyTimer.restart();
    }

    function setScreen(name) {
        const d = name ? displays.find(x => x.name === name) : displays.find(x => x.index === 0);
        if (!d) return;
        edit(s => {
            s.Display.Width = d.w;
            s.Display.Height = d.h;
            s.Display.X = d.x + d.w / 2;
            s.Display.Y = d.y + d.h / 2;
        });
    }

    // область: ширина/высота и центр в мм; не выходит за край планшета
    function setArea(w, h, cx, cy) {
        w = Math.max(10, Math.min(maxW, w));
        h = Math.max(10, Math.min(maxH, h));
        cx = Math.max(w / 2, Math.min(maxW - w / 2, cx));
        cy = Math.max(h / 2, Math.min(maxH - h / 2, cy));
        edit(s => {
            s.Tablet.Width = Math.round(w * 100) / 100;
            s.Tablet.Height = Math.round(h * 100) / 100;
            s.Tablet.X = Math.round(cx * 100) / 100;
            s.Tablet.Y = Math.round(cy * 100) / 100;
        });
    }

    function setRotation(deg) {
        edit(s => { s.Tablet.Rotation = deg; });
    }

    function setLock(on) {
        edit(s => { s.LockAspectRatio = on; });
    }

    // готовая область: доля планшета по центру; с «пропорциями» — под экран
    function preset(frac) {
        let w = maxW * frac, h = maxH * frac;
        if (profile?.AbsoluteModeSettings?.LockAspectRatio) {
            const a = displayAspect();
            if (w / h > a) w = h * a; else h = w / a;
        }
        setArea(w, h, maxW / 2, maxH / 2);
    }

    function refresh() {
        detect.running = true;
    }

    Timer {
        id: applyTimer
        interval: 350
        onTriggered: {
            file.setText(JSON.stringify(root.data, null, 2));
            load.running = true;
        }
    }

    // применить файл к работающему драйверу
    Process {
        id: load
        command: ["otd", "loadsettings", root.path]
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (JSON.stringify(d) !== JSON.stringify(root.data)) root.data = d;
            } catch (e) {}
        }
    }

    // установлен ли otd, запущен ли он, какие есть экраны
    Process {
        id: detect
        command: ["sh", "-c", "command -v otd >/dev/null && echo installed; systemctl --user is-active -q opentabletdriver.service && echo running; command -v otd >/dev/null && timeout 5 otd listdisplays 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                root.installed = lines.includes("installed");
                root.running = lines.includes("running");
                const ds = [];
                for (const l of lines) {
                    // «2: DP-1 Xiaomi … (1920x1080@<900  0>)»
                    const m = l.match(/^(\d+):\s+(\S+).*\((\d+)x(\d+)@<(-?\d+)\s+(-?\d+)>\)/);
                    if (m) ds.push({ index: +m[1], name: +m[1] === 0 ? "" : m[2], w: +m[3], h: +m[4], x: +m[5], y: +m[6] });
                }
                if (ds.length) root.displays = ds;
                root.sync();
            }
        }
    }

    // запомнить размер планшета; перенести старые настройки niri (монитор, «для левши») в OTD
    property bool syncing: false
    function sync() {
        if (!active || syncing) return;
        syncing = true;
        const tb = Settings.input?.tablet ?? {};
        if (!tb.otd) Settings.setInputIn("tablet", "otd", true);
        if (!tb.otdMaxW && area && Math.abs(area.X - area.Width / 2) < 0.5 && Math.abs(area.Y - area.Height / 2) < 0.5) {
            Settings.setInputIn("tablet", "otdMaxW", area.Width);
            Settings.setInputIn("tablet", "otdMaxH", area.Height);
        }
        if (!tb.otdMigrated && displays.length) {
            Settings.setInputIn("tablet", "otdMigrated", true);
            if (tb.mapTo) setScreen(tb.mapTo);
        }
        if (!tb.otdRotMigrated) {
            Settings.setInputIn("tablet", "otdRotMigrated", true);
            const r = Number(tb.rotation ?? 0);
            if (r && Number(area?.Rotation ?? 0) === 0) setRotation(r);
        }
        syncing = false;
    }

    onDataChanged: if (data && installed) sync()

    // экраны могли поменяться
    Connections {
        target: Quickshell
        function onScreensChanged() { refreshLater.restart(); }
    }
    Timer {
        id: refreshLater
        interval: 2000
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
