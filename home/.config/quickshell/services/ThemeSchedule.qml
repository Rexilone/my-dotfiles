pragma Singleton
import QtQuick
import Quickshell

// расписание темы: днём одна схема, вечером другая; заодно обои и ночной свет.
// Settings.themeSchedule: { mode: off | sun | time, day, night, from, to, wallDay, wallNight, nightLight }
// «sun» — по восходу и закату для города из погоды. Тема меняется только при смене дня/ночи:
// выбранное вручную посреди дня остаётся до заката.
Singleton {
    id: root

    readonly property var cfg: Settings.themeSchedule ?? {}
    readonly property bool on: (cfg.mode ?? "off") !== "off"
    property bool night: false
    property string phase: ""          // последнее применённое: day | night
    property date nextSwitch: new Date()
    property date now: new Date()

    // восход и закат (упрощённый алгоритм NOAA), локальное время
    function sun(d, lat, lon) {
        const rad = Math.PI / 180;
        const start = new Date(d.getFullYear(), 0, 0);
        const n = Math.floor((d - start) / 86400000);
        const g = 2 * Math.PI / 365 * (n - 1);
        const eqt = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g) - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));
        const decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g)
            + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
        const cosH = (Math.cos(90.833 * rad) - Math.sin(lat * rad) * Math.sin(decl)) / (Math.cos(lat * rad) * Math.cos(decl));
        if (cosH > 1 || cosH < -1) return null;   // полярный день или ночь
        const ha = Math.acos(cosH) / rad;
        const utcMid = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const at = minutes => new Date(utcMid.getTime() + minutes * 60000);
        return { rise: at(720 - 4 * (lon + ha) - eqt), set: at(720 - 4 * (lon - ha) - eqt) };
    }

    function hm(s, def) {
        const m = /^(\d{1,2}):(\d{2})$/.exec(s ?? "") ?? /^(\d{1,2}):(\d{2})$/.exec(def);
        return [parseInt(m[1]), parseInt(m[2])];
    }

    // начало дня и вечера сегодня
    function bounds(d) {
        if (cfg.mode === "sun" && Weather.configured) {
            const s = sun(d, Weather.latitude, Weather.longitude);
            if (s) return s;
        }
        const [fh, fm] = hm(cfg.from, "07:00");
        const [th, tm] = hm(cfg.to, "20:00");
        return {
            rise: new Date(d.getFullYear(), d.getMonth(), d.getDate(), fh, fm),
            set: new Date(d.getFullYear(), d.getMonth(), d.getDate(), th, tm),
        };
    }

    function update(force) {
        now = new Date();
        if (!on) return;
        const b = bounds(now);
        night = now < b.rise || now >= b.set;
        nextSwitch = now < b.rise ? b.rise : now < b.set ? b.set : bounds(new Date(now.getTime() + 86400000)).rise;
        const p = night ? "night" : "day";
        if (p === phase && !force) return;
        phase = p;
        const scheme = night ? (cfg.night ?? "dark") : (cfg.day ?? "light");
        if (scheme && Settings.scheme !== scheme) Settings.scheme = scheme;
        const wall = night ? cfg.wallNight : cfg.wallDay;
        if (wall && Wallpapers.current !== wall) Wallpapers.apply(wall);
        if (cfg.nightLight) Settings.setNight("enabled", night);
    }

    Timer {
        running: true
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.update(false)
    }
    // поменяли расписание — применить сразу
    Connections {
        target: Settings
        function onThemeScheduleChanged() { root.update(true); }
    }
    Connections {
        target: Weather
        function onConfiguredChanged() { root.update(false); }
    }
}
