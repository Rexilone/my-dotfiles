import QtQuick
import QtQuick.Layouts
import qs.services

// Дисплей: расположение мониторов, разрешение, частота, масштаб, поворот, VRR
Page {
    id: page

    title: "Display"
    subtitle: "Arrange monitors, resolution, refresh rate, scale and rotation"

    property var pending: ({})
    property string selectedName: ""
    readonly property var sel: pending[selectedName] ?? null
    readonly property bool dirty: JSON.stringify(pending) !== JSON.stringify(NiriSettings.current())

    function reset() {
        pending = JSON.parse(JSON.stringify(NiriSettings.current()));
        if (!pending[selectedName]) selectedName = Object.keys(pending).find(n => n === Settings.primary) ?? Object.keys(pending)[0] ?? "";
    }

    function set(key, value) {
        const p = JSON.parse(JSON.stringify(pending));
        p[selectedName][key] = value;
        pending = p;
    }

    function parseMode(mode) {
        const m = (mode ?? "").match(/^(\d+)x(\d+)@([\d.]+)$/);
        return m ? { w: Number(m[1]), h: Number(m[2]), hz: Number(m[3]) } : { w: 1920, h: 1080, hz: 60 };
    }

    function rotated(t) {
        return /90|270/.test(t ?? "");
    }

    // логический размер (с учётом масштаба и поворота)
    function logical(name) {
        const o = pending[name];
        const m = parseMode(o.mode);
        const r = rotated(o.transform);
        return { w: (r ? m.h : m.w) / o.scale, h: (r ? m.w : m.h) / o.scale };
    }

    // примагничивание к ближайшему краю другого монитора, затем сдвиг к (0,0)
    function snap(name, x, y) {
        const a = logical(name);
        let best = { x, y }, bestD = Infinity;
        for (const other in pending) {
            if (other === name || pending[other].off) continue;
            const o = pending[other], b = logical(other);
            const clampY = v => Math.max(o.y - a.h + 50, Math.min(o.y + b.h - 50, v));
            const clampX = v => Math.max(o.x - a.w + 50, Math.min(o.x + b.w - 50, v));
            const alignY = v => Math.abs(v - o.y) < 80 ? o.y : Math.abs(v + a.h - (o.y + b.h)) < 80 ? o.y + b.h - a.h : v;
            const alignX = v => Math.abs(v - o.x) < 80 ? o.x : Math.abs(v + a.w - (o.x + b.w)) < 80 ? o.x + b.w - a.w : v;
            const cands = [
                { x: o.x + b.w, y: alignY(clampY(y)) },
                { x: o.x - a.w, y: alignY(clampY(y)) },
                { x: alignX(clampX(x)), y: o.y + b.h },
                { x: alignX(clampX(x)), y: o.y - a.h },
            ];
            for (const c of cands) {
                const d = Math.hypot(c.x - x, c.y - y);
                if (d < bestD) {
                    bestD = d;
                    best = c;
                }
            }
        }
        const p = JSON.parse(JSON.stringify(pending));
        p[name].x = Math.round(best.x);
        p[name].y = Math.round(best.y);
        const minX = Math.min(...Object.values(p).map(o => o.x));
        const minY = Math.min(...Object.values(p).map(o => o.y));
        for (const n in p) {
            p[n].x -= minX;
            p[n].y -= minY;
        }
        pending = p;
    }

    Component.onCompleted: {
        NiriSettings.refresh();
        reset();
    }

    Connections {
        target: NiriSettings
        function onLiveChanged() {
            if (!page.dirty || Object.keys(page.pending).length === 0) {
                page.reset();
                return;
            }
            // есть несохранённые правки: добавляем подключённые мониторы, убираем отключённые
            const cur = NiriSettings.current();
            const p = {};
            for (const n in cur) p[n] = page.pending[n] ?? JSON.parse(JSON.stringify(cur[n]));
            if (JSON.stringify(Object.keys(p).sort()) !== JSON.stringify(Object.keys(page.pending).sort())) {
                page.pending = p;
                if (!p[page.selectedName]) page.selectedName = Object.keys(p)[0] ?? "";
            }
        }
    }

    // пока страница открыта — следим за мониторами (подключили, отключили, сменили режим)
    Timer {
        interval: 3000
        repeat: true
        running: page.visible && NiriSettings.confirmLeft === 0
        onTriggered: NiriSettings.refresh()
    }

    // ── подтверждение после применения
    Rectangle {
        Layout.fillWidth: true
        visible: NiriSettings.confirmLeft > 0
        implicitHeight: 64
        radius: 10
        color: Theme.surfaceHi
        border.width: 1
        border.color: Theme.warn

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 12

            Text {
                text: String.fromCodePoint(0xF0026)  // alert
                color: Theme.warn
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 3
            }
            Text {
                Layout.fillWidth: true
                text: `Keep these display settings? Reverting in ${NiriSettings.confirmLeft} s`
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
            SButton {
                text: I18n.tr("Revert")
                onClicked: NiriSettings.revert()
            }
            SButton {
                text: I18n.tr("Keep changes")
                primary: true
                onClicked: NiriSettings.confirm()
            }
        }
    }

    // ── схема расположения
    Rectangle {
        id: arrange

        Layout.fillWidth: true
        implicitHeight: 250
        radius: 10
        color: Theme.surface

        readonly property var names: Object.keys(page.pending).filter(n => !page.pending[n].off)
        readonly property var bounds: {
            let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
            for (const n of names) {
                const o = page.pending[n], s = page.logical(n);
                x0 = Math.min(x0, o.x); y0 = Math.min(y0, o.y);
                x1 = Math.max(x1, o.x + s.w); y1 = Math.max(y1, o.y + s.h);
            }
            return names.length ? { x0, y0, w: x1 - x0, h: y1 - y0 } : { x0: 0, y0: 0, w: 1, h: 1 };
        }
        readonly property real k: Math.min((width - 80) / bounds.w, (height - 60) / bounds.h)
        readonly property real ox: (width - bounds.w * k) / 2
        readonly property real oy: (height - bounds.h * k) / 2

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 12
            text: I18n.tr("Drag monitors to arrange them")
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }

        Repeater {
            model: arrange.names

            Rectangle {
                id: mon

                required property string modelData
                required property int index
                readonly property var o: page.pending[modelData]
                readonly property var size: page.logical(modelData)
                readonly property bool selected: page.selectedName === modelData

                function bindPos() {
                    x = Qt.binding(() => arrange.ox + (o.x - arrange.bounds.x0) * arrange.k);
                    y = Qt.binding(() => arrange.oy + (o.y - arrange.bounds.y0) * arrange.k);
                }

                Component.onCompleted: bindPos()
                width: size.w * arrange.k - 4
                height: size.h * arrange.k - 4
                radius: 8
                color: selected ? Theme.surfaceHi2 : Theme.surfaceHi
                border.width: selected ? 2 : 1
                border.color: selected ? Theme.accent : Theme.line
                z: dragArea.drag.active ? 10 : 1

                Behavior on x { enabled: !dragArea.drag.active; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !dragArea.drag.active; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                Column {
                    anchors.centerIn: parent
                    spacing: 3

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: mon.index + 1
                        color: mon.selected ? Theme.fg : Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 10
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: mon.modelData
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            const m = page.parseMode(mon.o.mode);
                            return `${m.w}×${m.h} · ${Math.round(m.hz)} Hz`;
                        }
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }

                MouseArea {
                    id: dragArea
                    property bool moved: false
                    anchors.fill: parent
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    drag.target: mon
                    drag.threshold: 4
                    onPressed: {
                        moved = false;
                        page.selectedName = mon.modelData;
                    }
                    onPositionChanged: if (drag.active) moved = true
                    onReleased: {
                        if (moved) {
                            const lx = (mon.x - arrange.ox) / arrange.k + arrange.bounds.x0;
                            const ly = (mon.y - arrange.oy) / arrange.k + arrange.bounds.y0;
                            page.snap(mon.modelData, lx, ly);
                        }
                        mon.bindPos();
                    }
                }
            }
        }
    }

    // ── главный монитор
    SCard {
        icon: String.fromCodePoint(0xF0379)
        title: "Main display"
        desc: "Gets focus at login, shows notifications and desktop widgets by default. Menus open where your cursor is."

        SDropdown {
            minWidth: 170
            options: Object.keys(NiriSettings.live).map(n => ({ value: n, label: `${n}  ·  ${NiriSettings.live[n].model ?? ""}` }))
            current: Settings.primary
            onPicked: v => Settings.primaryOutput = v
        }
    }

    // ── настройки выбранного монитора
    SSection {
        text: page.selectedName ? `${page.selectedName}  ·  ${NiriSettings.live[page.selectedName]?.make ?? ""} ${NiriSettings.live[page.selectedName]?.model ?? ""}` : ""
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        visible: !!page.sel

        SCard {
            icon: String.fromCodePoint(0xF0379)
            title: "Display resolution"
            desc: "Pick the resolution; the highest refresh rate is chosen automatically"

            SDropdown {
                readonly property var list: {
                    const seen = {};
                    return NiriSettings.modes(page.selectedName).filter(m => {
                        const k = `${m.width}x${m.height}`;
                        return seen[k] ? false : (seen[k] = true);
                    });
                }
                options: list.map(m => ({ value: `${m.width}x${m.height}`, label: `${m.width} × ${m.height}` + (m.preferred ? "  (recommended)" : "") }))
                current: page.sel ? page.sel.mode.split("@")[0] : ""
                onPicked: v => {
                    const best = NiriSettings.modes(page.selectedName).filter(m => `${m.width}x${m.height}` === v).sort((a, b) => b.hz - a.hz)[0];
                    if (best) page.set("mode", best.key);
                }
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF051B)
            title: "Refresh rate"
            desc: "Higher is smoother"

            SDropdown {
                minWidth: 140
                options: page.sel
                    ? NiriSettings.modes(page.selectedName).filter(m => `${m.width}x${m.height}` === page.sel.mode.split("@")[0])
                        .map(m => ({ value: m.key, label: `${m.hz.toFixed(m.hz % 1 > 0.05 && m.hz % 1 < 0.95 ? 2 : 0)} Hz` }))
                    : []
                current: page.sel?.mode ?? ""
                onPicked: v => page.set("mode", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF1392)  // magnify-expand
            title: "Scale"
            desc: "Size of text and apps"

            SDropdown {
                minWidth: 140
                options: [0.75, 1, 1.25, 1.5, 1.75, 2].map(v => ({ value: v, label: `${Math.round(v * 100)}%` + (v === 1 ? "  (default)" : "") }))
                current: page.sel ? Number(page.sel.scale) : 1
                onPicked: v => page.set("scale", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0467)  // rotate
            title: "Rotation"

            SChoice {
                options: [
                    { value: "normal", label: "0°" },
                    { value: "90", label: "90°" },
                    { value: "180", label: "180°" },
                    { value: "270", label: "270°" },
                ]
                current: page.sel?.transform ?? "normal"
                onPicked: v => page.set("transform", v)
            }
        }

        SCard {
            visible: NiriSettings.live[page.selectedName]?.vrr_supported ?? false
            icon: String.fromCodePoint(0xF1A0E)  // sync
            title: "Variable refresh rate"
            desc: "FreeSync / VRR — smoother games, less tearing"

            SSwitch {
                checked: page.sel?.vrr ?? false
                onToggled: v => page.set("vrr", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0425)
            title: "Use this display"
            desc: "Turn the monitor off without unplugging it"

            SSwitch {
                checked: !(page.sel?.off ?? false)
                enabled: page.sel?.off || arrange.names.length > 1
                opacity: enabled ? 1 : 0.4
                onToggled: v => page.set("off", !v)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 12
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: page.dirty ? "You have unapplied changes" : ""
            color: Theme.warn
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
        SButton {
            text: I18n.tr("Reset")
            enabled: page.dirty
            onClicked: page.reset()
        }
        SButton {
            text: I18n.tr("Apply")
            primary: true
            enabled: page.dirty && NiriSettings.confirmLeft === 0
            onClicked: NiriSettings.applyOutputs(page.pending)
        }
    }

    // ── ночной свет
    SSection { text: I18n.tr("Night light") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF0335)
            title: "Night light"
            desc: NightLight.installed ? "Warmer colors that are easier on the eyes at night" : "Needs wlsunset — install it first"

            SButton {
                visible: !NightLight.installed
                text: I18n.tr("Install")
                primary: true
                onClicked: NightLight.install()
            }
            SSwitch {
                visible: NightLight.installed
                checked: NightLight.on
                onToggled: v => Settings.setNight("enabled", v)
            }
        }

        SCard {
            visible: NightLight.installed
            icon: String.fromCodePoint(0xF0590)
            title: "Schedule"
            desc: Weather.configured ? `Sunset to sunrise uses your weather city (${Weather.city})` : "Set a weather city to use sunset to sunrise"

            SChoice {
                options: [{ value: false, label: "Always" }, { value: true, label: "Sunset → sunrise" }]
                current: Settings.nightLight.auto ?? false
                onPicked: v => Settings.setNight("auto", v && Weather.configured)
            }
        }

        SCard {
            visible: NightLight.installed
            icon: String.fromCodePoint(0xF050F)
            title: "Warmth"
            desc: "Lower is warmer"

            SSlider {
                from: 2500
                to: 6000
                step: 100
                value: Settings.nightLight.temp ?? 4500
                suffix: " K"
                onMoved: v => Settings.setNight("temp", Math.round(v))
            }
        }
    }
}
