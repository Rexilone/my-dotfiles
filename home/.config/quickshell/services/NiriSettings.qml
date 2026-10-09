pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// генерирует ~/.config/niri/qs-settings.kdl (ввод + мониторы); niri перечитывает его сам
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("HOME")}/.config/niri/qs-settings.kdl`

    property var live: ({})        // текущие мониторы из `niri msg -j outputs`
    property var backup: null      // для отката смены мониторов
    property int confirmLeft: 0    // сколько секунд осталось подтвердить

    function refresh() {
        query.running = true;
    }

    // режимы монитора, уникальные «ШxВ@Гц», по убыванию
    function modes(name) {
        const o = live[name];
        if (!o) return [];
        const seen = {};
        return o.modes.map((m, i) => ({
            index: i,
            width: m.width,
            height: m.height,
            hz: m.refresh_rate / 1000,
            preferred: m.is_preferred,
            key: `${m.width}x${m.height}@${(m.refresh_rate / 1000).toFixed(3)}`,
        })).filter(m => seen[m.key] ? false : (seen[m.key] = true))
          .sort((a, b) => b.width * b.height - a.width * a.height || b.hz - a.hz);
    }

    // «производитель модель серийник» — так niri тоже умеет называть монитор;
    // по нему настройки находят монитор, даже если его переткнули в другой порт
    function idOf(o) {
        return o ? `${o.make ?? "Unknown"} ${o.model ?? "Unknown"} ${o.serial ?? "Unknown"}` : "";
    }

    // настройки одного монитора из текущего состояния niri
    function fromLiveOne(name) {
        const o = live[name];
        const m = o.modes[o.current_mode ?? 0];
        const l = o.logical ?? {};
        return {
            id: idOf(o),
            mode: m ? `${m.width}x${m.height}@${(m.refresh_rate / 1000).toFixed(3)}` : "",
            scale: l.scale ?? 1,
            transform: String(l.transform ?? "normal").toLowerCase(),
            x: l.x ?? 0,
            y: l.y ?? 0,
            vrr: !!o.vrr_enabled,
            off: o.current_mode === null,
        };
    }

    function fromLive() {
        const out = {};
        for (const name in live) out[name] = fromLiveOne(name);
        return out;
    }

    // сохранённые настройки для подключённого монитора: по порту, а если там другой
    // монитор (или ничего) — по id; возвращает [ключ в Settings.outputs, настройки]
    function savedFor(name) {
        const saved = Settings.outputs, id = idOf(live[name]);
        const s = saved[name];
        if (s && (!s.id || s.id === id)) return [name, s];
        for (const k in saved)
            if (saved[k].id === id && !live[k]) return [k, saved[k]];
        return [null, null];
    }

    // подключённые мониторы: сохранённые настройки поверх текущего состояния
    function current() {
        if (Object.keys(live).length === 0) return Settings.outputs;
        const out = {};
        for (const name in live) {
            const [, s] = savedFor(name);
            out[name] = Object.assign({}, s ?? fromLiveOne(name), { id: idOf(live[name]) });
        }
        return out;
    }

    // сохранённые настройки мониторов, которые сейчас не подключены (вернутся при подключении)
    function disconnected() {
        if (Object.keys(live).length === 0) return {};
        const used = {};
        for (const name in live) {
            const [k] = savedFor(name);
            if (k) used[k] = true;
        }
        const out = {};
        for (const k in Settings.outputs) if (!used[k]) out[k] = Settings.outputs[k];
        return out;
    }

    // матрица калибровки планшета: поворот (0/90/180/270, «левша» = 180) и обрезка рабочей
    // области под пропорции монитора, чтобы круг на планшете рисовался кругом.
    // libinput: [x', y'] = [a b c; d e f] · [x y 1] в нормализованных координатах
    function tabletMatrix(tb) {
        const rot = Number(tb.rotation ?? 0);
        const R = {
            0: [[1, 0, 0], [0, 1, 0]],
            90: [[0, -1, 1], [1, 0, 0]],
            180: [[-1, 0, 1], [0, -1, 1]],
            270: [[0, 1, 0], [-1, 0, 1]],
        }[rot] ?? [[1, 0, 0], [0, 1, 0]];
        let sx = 1, sy = 1, ox = 0, oy = 0;
        if (tb.keepAspect && tb.widthMm > 0 && tb.heightMm > 0) {
            const side = rot === 90 || rot === 270;
            const ta = side ? tb.heightMm / tb.widthMm : tb.widthMm / tb.heightMm;
            const oa = outputAspect(tb.mapTo);
            if (oa > 0 && Math.abs(ta - oa) > 0.001) {
                if (ta > oa) {          // планшет шире экрана: используем середину по ширине
                    const f = oa / ta;
                    sx = 1 / f; ox = -(1 - f) / (2 * f);
                } else {                // планшет выше: середину по высоте
                    const f = ta / oa;
                    sy = 1 / f; oy = -(1 - f) / (2 * f);
                }
            }
        }
        if (rot === 0 && sx === 1 && sy === 1) return null;
        return [sx * R[0][0], sx * R[0][1], sx * R[0][2] + ox,
                sy * R[1][0], sy * R[1][1], sy * R[1][2] + oy];
    }

    // пропорции монитора (с учётом поворота) или всех мониторов вместе
    function outputAspect(name) {
        const outs = name && live[name] ? [live[name]] : Object.values(live);
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const o of outs) {
            const l = o.logical;
            if (!l) continue;
            x0 = Math.min(x0, l.x); y0 = Math.min(y0, l.y);
            x1 = Math.max(x1, l.x + l.width); y1 = Math.max(y1, l.y + l.height);
        }
        return x1 > x0 && y1 > y0 ? (x1 - x0) / (y1 - y0) : 0;
    }

    function kdl() {
        const i = Settings.input;
        const m = i.mouse ?? {};
        const t = i.touchpad ?? {};
        const L = [];
        L.push("// генерируется Quickshell (Настройки, Super+I) — правки вручную перезапишутся");
        L.push("input {");
        L.push("    keyboard {");
        L.push("        xkb {");
        L.push(`            layout "${(i.layouts ?? ["us"]).join(",")}"`);
        if (i.switchKey) L.push(`            options "${i.switchKey}"`);
        L.push("        }");
        L.push(`        repeat-delay ${i.repeatDelay ?? 600}`);
        L.push(`        repeat-rate ${i.repeatRate ?? 25}`);
        if (i.numlock) L.push("        numlock");
        L.push("    }");
        L.push("    touchpad {");
        if (t.off) L.push("        off");
        if (t.tap ?? true) L.push("        tap");
        if (t.naturalScroll ?? true) L.push("        natural-scroll");
        if (t.dwt ?? true) L.push("        dwt");
        if (t.disabledOnExternalMouse) L.push("        disabled-on-external-mouse");
        if (t.accelSpeed) L.push(`        accel-speed ${Number(t.accelSpeed).toFixed(2)}`);
        if (t.clickMethod) L.push(`        click-method "${t.clickMethod}"`);
        if (t.scrollFactor && t.scrollFactor !== 1) L.push(`        scroll-factor ${Number(t.scrollFactor).toFixed(2)}`);
        L.push("    }");
        L.push("    mouse {");
        L.push(`        accel-speed ${Number(m.accelSpeed ?? 0).toFixed(2)}`);
        L.push(`        accel-profile "${m.accelProfile ?? "adaptive"}"`);
        if (m.naturalScroll) L.push("        natural-scroll");
        if (m.leftHanded) L.push("        left-handed");
        if (m.middleEmulation) L.push("        middle-emulation");
        if (m.scrollFactor && m.scrollFactor !== 1) L.push(`        scroll-factor ${Number(m.scrollFactor).toFixed(2)}`);
        L.push("    }");
        // графический планшет: монитор, поворот, сохранение пропорций (через calibration-matrix)
        const tb = i.tablet ?? {};
        L.push("    tablet {");
        if (tb.off) L.push("        off");
        // планшетом управляет OpenTabletDriver: экран, область и поворот задаёт он,
        // niri ничего не пересчитывает (иначе отображение применится дважды)
        if (tb.otd) {
        } else if (tb.mapTo && live[tb.mapTo]) L.push(`        map-to-output "${tb.mapTo}"`);
        if (tb.otd) {
        } else if (tb.direct) {
            // планшет-экран: поворот и пропорции матрицей калибровки
            const cm = tabletMatrix(tb);
            if (cm) L.push(`        calibration-matrix ${cm.map(v => Number(v).toFixed(4)).join(" ")}`);
        } else if (Number(tb.rotation ?? 0) === 180) {
            // обычный планшет: libinput умеет только «левшу» — поворот на 180°
            L.push("        left-handed");
        }
        L.push("    }");
        if (i.focusFollowsMouse) L.push('    focus-follows-mouse max-scroll-amount="0%"');
        L.push("}");

        // прозрачный терминал: размытие всего окна (панели шелла размывают себя сами)
        if (Settings.transparency && Settings.blur && Settings.terminalOpacity < 1) {
            L.push("");
            L.push("window-rule {");
            L.push('    match app-id="^foot$"');
            L.push("    background-effect {");
            L.push("        blur true");
            L.push("    }");
            L.push("}");
        }

        // телефон (Rexlink) на демонстрации экрана: зрители видят на месте звонка/уведомлений пустоту
        const hidden = [];
        if (Settings.moduleOn("phoneCastHideCalls", true)) hidden.push("quickshell-call");
        if (Settings.moduleOn("phoneCastHideNotifs", true)) hidden.push("quickshell-notifications-phone", "quickshell-popup-phone");
        if (hidden.length) {
            L.push("");
            L.push("layer-rule {");
            for (const n of hidden) L.push(`    match namespace="^${n}$"`);
            L.push('    block-out-from "screencast"');
            L.push("}");
        }

        // Qt-приложения берут цвета из GTK-темы (она следует схеме шелла)
        L.push("");
        L.push("environment {");
        L.push('    QT_QPA_PLATFORMTHEME "gtk3"');
        L.push("}");

        // свои и изменённые бинды
        const binds = (Settings.binds ?? []).filter(b => b.enabled !== false && b.key && b.action);
        if (binds.length) {
            L.push("");
            L.push("binds {");
            for (const b of binds) L.push(`    ${b.key}${b.props ? " " + b.props : ""} { ${b.action} }`);
            L.push("}");
        }

        // автозапуск из Настроек
        for (const a of Settings.autostart ?? []) {
            if (!a.enabled || !a.command) continue;
            L.push("");
            L.push(`spawn-sh-at-startup "${a.command.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`);
        }

        // подключённые — по порту; отключённые — по id (если известен), чтобы
        // применились в любом порту
        const outs = current();
        const away = disconnected();
        for (const k in away) {
            const n = away[k].id || k;
            if (!Object.values(outs).some(o => o.id === n) && !(n in outs)) outs[n] = away[k];
        }
        for (const name in outs) {
            const o = outs[name];
            L.push("");
            L.push(`output "${name.replace(/"/g, '\\"')}" {`);
            if (o.off) L.push("    off");
            if (o.mode) L.push(`    mode "${o.mode}"`);
            L.push(`    scale ${Number(o.scale).toFixed(2)}`);
            L.push(`    transform "${o.transform}"`);
            L.push(`    position x=${Math.round(o.x)} y=${Math.round(o.y)}`);
            if (o.vrr) L.push("    variable-refresh-rate");
            if (name === Settings.primary) L.push("    focus-at-startup");
            L.push("}");
        }
        return L.join("\n") + "\n";
    }

    property bool pendingWrite: false
    readonly property bool ready: Object.keys(Settings.outputs).length > 0 || Object.keys(live).length > 0

    // без данных о мониторах не пишем: иначе из файла пропадут их настройки
    function write() {
        if (!ready) {
            pendingWrite = true;
            refresh();
            return;
        }
        writeTimer.restart();
    }

    function writeNow() {
        writeTimer.stop();
        if (!ready) {
            pendingWrite = true;
            refresh();
            return;
        }
        file.setText(kdl());
    }

    property string liveKey: ""

    onLiveChanged: {
        // первый запуск: запоминаем текущие мониторы как настройки
        if (Object.keys(Settings.outputs).length === 0 && Object.keys(live).length > 0)
            Settings.outputs = fromLive();
        // набор мониторов поменялся (подключили/отключили/переткнули) — переписываем конфиг:
        // знакомый монитор получит свои сохранённые настройки в новом порту
        const key = Object.keys(live).map(n => n + "=" + idOf(live[n])).sort().join("|");
        const changed = liveKey !== "" && key !== liveKey;
        liveKey = key;
        if ((pendingWrite || changed) && ready) {
            pendingWrite = false;
            writeTimer.restart();
        }
    }

    // монитор подключили или отключили
    Connections {
        target: Quickshell
        function onScreensChanged() { refreshLater.restart(); }
    }

    // слайдеры дёргают запись часто — niri перечитает конфиг один раз
    Timer {
        id: writeTimer
        interval: 350
        onTriggered: if (root.ready) file.setText(root.kdl())
    }

    // применить мониторы с откатом через 15 с, если не подтвердить
    function applyOutputs(next) {
        backup = JSON.parse(JSON.stringify(Settings.outputs));
        // подключённые — новые значения, отключённые остаются как были
        Settings.outputs = Object.assign({}, disconnected(), next);
        writeNow();
        confirmLeft = 15;
        countdown.restart();
    }

    function confirm() {
        countdown.stop();
        confirmLeft = 0;
        backup = null;
        refresh();
    }

    function revert() {
        countdown.stop();
        confirmLeft = 0;
        if (backup) {
            Settings.outputs = backup;
            writeNow();
        }
        backup = null;
        refreshLater.restart();
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.confirmLeft--;
            if (root.confirmLeft <= 0) root.revert();
        }
    }

    Timer {
        id: refreshLater
        interval: 800
        onTriggered: root.refresh()
    }

    FileView {
        id: file
        path: root.path
        printErrors: false
    }

    Process {
        id: query
        command: ["niri", "msg", "-j", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.live = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: refresh()

    // qs ipc call niriconf write — пересобрать qs-settings.kdl
    IpcHandler {
        target: "niriconf"
        function write(): void { root.writeNow(); }
    }

    // эти настройки тоже пишутся в niri
    Connections {
        target: Settings
        function onTransparencyChanged() { root.write(); }
        function onBlurChanged() { root.write(); }
        function onTerminalOpacityChanged() { root.write(); }
        function onAutostartChanged() { root.write(); }
        function onBindsChanged() { root.write(); }
        function onPrimaryOutputChanged() { root.write(); }
        function onBarModulesChanged() { root.write(); }
    }
}
