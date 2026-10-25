pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// экранное время: сколько и в каких программах прошёл день. Считается окно в фокусе (niri), раз в 5 секунд,
// только пока за компьютером кто-то есть (2 минуты без мыши и клавиатуры — не считается; видео и игры,
// которые не дают экрану погаснуть, считаются). Всё хранится локально: ~/.local/state/quickshell/…/screentime.json,
// последние 60 дней. Настройки → Экранное время
Singleton {
    id: root

    readonly property bool enabled: Settings.screenTime?.enabled ?? true
    readonly property int step: 5

    // { "2026-10-25": { apps: { app_id: секунды }, hours: [24 × секунды] } }
    property var days: ({})
    property bool loaded: false
    property bool dirty: false

    function key(d) {
        return Qt.formatDate(d ?? new Date(), "yyyy-MM-dd");
    }
    function day(k) {
        return days[k] ?? { apps: {}, hours: new Array(24).fill(0) };
    }
    function total(k) {
        return Object.values(day(k).apps).reduce((a, s) => a + s, 0);
    }
    // программы дня: [{ id, sec }] по убыванию
    function apps(k) {
        return Object.entries(day(k).apps).map(([id, sec]) => ({ id, sec })).filter(a => a.sec >= 60).sort((a, b) => b.sec - a.sec);
    }
    // последние n дней, старые первыми: [{ key, date, sec }]
    function lastDays(n) {
        const out = [];
        for (let i = n - 1; i >= 0; i--) {
            const d = new Date();
            d.setDate(d.getDate() - i);
            const k = key(d);
            out.push({ key: k, date: d, sec: total(k) });
        }
        return out;
    }
    function fmt(sec) {
        const h = Math.floor(sec / 3600), m = Math.round(sec % 3600 / 60);
        if (I18n.ru) return h ? `${h} ч ${m} мин` : `${m} мин`;
        return h ? `${h} h ${m} min` : `${m} min`;
    }
    // имя и значок программы по app_id окна
    function app(id) {
        const e = DesktopEntries.heuristicLookup(id);
        return { name: e?.name || id, icon: e?.icon || id };
    }
    function clear() {
        days = {};
        dirty = true;
        save();
    }

    // кто-то за компьютером
    IdleMonitor {
        id: idle
        enabled: root.enabled
        timeout: 120
        respectInhibitors: true
    }

    Timer {
        running: root.enabled && root.loaded && !idle.isIdle
        interval: root.step * 1000
        repeat: true
        onTriggered: {
            const w = Niri.focusedWindow;
            if (!w || !w.app_id) return;
            const now = new Date(), k = root.key(now);
            const d = Object.assign({ apps: {}, hours: new Array(24).fill(0) }, root.days[k]);
            d.apps = Object.assign({}, d.apps, { [w.app_id]: (d.apps[w.app_id] ?? 0) + root.step });
            d.hours = d.hours.slice();
            d.hours[now.getHours()] += root.step;
            root.days = Object.assign({}, root.days, { [k]: d });
            root.dirty = true;
        }
    }

    // на диск — раз в минуту и при выходе; дни старше 60 — прочь
    function save() {
        if (!dirty) return;
        const keep = {};
        const min = new Date();
        min.setDate(min.getDate() - 60);
        const minKey = key(min);
        for (const k in days) if (k >= minKey) keep[k] = days[k];
        file.setText(JSON.stringify({ version: 1, days: keep }));
        dirty = false;
    }
    Timer {
        running: root.dirty
        interval: 60000
        repeat: true
        onTriggered: root.save()
    }
    Component.onDestruction: save()

    FileView {
        id: file
        path: Quickshell.statePath("screentime.json")
        printErrors: false
        onLoaded: {
            try { root.days = JSON.parse(text()).days ?? {}; } catch (e) { root.days = {}; }
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }
}
