pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// все настройки шелла; хранятся в ~/.local/state/quickshell/.../settings.json
Singleton {
    id: root

    // ── внешний вид
    property alias scheme: cfg.scheme              // dark | light | nord | gruvbox | rose | wallpaper
    property alias uiScale: cfg.uiScale            // множитель размеров шрифта

    // ── шрифты
    property alias font: cfg.font                  // шрифт интерфейса шелла
    property alias monoFont: cfg.monoFont          // шрифт терминала
    property alias appFont: cfg.appFont            // шрифт GTK-приложений

    // ── прозрачность (Персонализация)
    property alias transparency: cfg.transparency  // вкл/выкл
    property alias opacity: cfg.opacity            // 0.5..1 непрозрачность панелей
    property alias blur: cfg.blur                  // размытие под панелями (niri)
    property alias terminalOpacity: cfg.terminalOpacity

    // ── время и язык
    property alias weekStartsMonday: cfg.weekStartsMonday

    // ── электропитание: минуты, 0 = никогда
    property alias power: cfg.power                // { lock, screenOff, suspend, lockOnSuspend }

    // ── автозапуск, которым управляет шелл: [{ command, enabled }]
    property alias autostart: cfg.autostart

    // ── режим разработчика и плагины: { id: true/false }
    property alias developerMode: cfg.developerMode
    property alias plugins: cfg.plugins

    function setPlugin(id, on) {
        plugins = Object.assign({}, plugins, { [id]: on });
    }

    // ── главный монитор и мониторы с баром
    property alias primaryOutput: cfg.primaryOutput
    property alias barScreens: cfg.barScreens     // [] — только на главном
    readonly property string primary: {
        const names = Quickshell.screens.map(s => s.name);
        if (cfg.primaryOutput && names.includes(cfg.primaryOutput)) return cfg.primaryOutput;
        // не задан — самый крупный монитор (по площади, затем по частоте)
        const area = s => s.width * s.height;
        const best = Quickshell.screens.slice().sort((a, b) => area(b) - area(a))[0];
        return best ? best.name : (names[0] ?? "");
    }
    readonly property var barOn: {
        const names = Quickshell.screens.map(s => s.name);
        const list = (cfg.barScreens ?? []).filter(n => names.includes(n));
        return list.length ? list : [primary];
    }

    function screenByName(name) {
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens.find(s => s.name === primary) ?? Quickshell.screens[0];
    }

    // экран для меню/оверлея: где сейчас фокус (курсор), иначе главный
    function activeScreen() {
        return screenByName(Niri.focusedOutput || primary);
    }

    // ── стиль бара: flat | floating | pills
    property alias barStyle: cfg.barStyle

    // ── ночной свет: { enabled, temp, auto }  (auto — от заката до рассвета по городу из погоды)
    property alias nightLight: cfg.nightLight

    function setNight(key, value) {
        nightLight = Object.assign({}, nightLight, { [key]: value });
    }

    // ── свои и изменённые бинды: [{ key, props, action, enabled }]
    property alias binds: cfg.binds

    // ── виджеты рабочего стола
    property alias widgets: cfg.widgets

    // виджеты телефона (Rexlink): экземпляры "phone-<n>" в widgets — { type: "phone", device, variant, … }
    readonly property var phoneWidgetIds: Object.keys(widgets).filter(k => k.startsWith("phone-")).sort()

    function addPhoneWidget(device, variant) {
        const w = JSON.parse(JSON.stringify(widgets));
        let n = 1;
        while (w[`phone-${n}`]) n++;
        w[`phone-${n}`] = { type: "phone", device: device ?? "", variant: variant ?? "full", enabled: true,
                            screen: primary, x: 120 + (n - 1) * 40, y: 140 + (n - 1) * 40, background: true, size: 1 };
        widgets = w;
    }

    function removeWidget(id) {
        const w = JSON.parse(JSON.stringify(widgets));
        delete w[id];
        widgets = w;
    }

    function setWidget(id, key, value) {
        const w = JSON.parse(JSON.stringify(widgets));
        w[id] = Object.assign({}, w[id] ?? {}, { [key]: value });
        widgets = w;
    }

    function setPower(key, value) {
        power = Object.assign({}, power, { [key]: value });
    }

    // ── бар
    property alias barHeight: cfg.barHeight
    property alias clockFormat: cfg.clockFormat
    property alias workspaceStyle: cfg.workspaceStyle   // dots | numbers
    property alias barModules: cfg.barModules      // { tray, keyboard, volume, mic, network, notifications }
    // трей: "inline" — все значки в баре, "menu" — кнопка с сеткой приложений
    // (закреплённые из trayPinned остаются в баре)
    // обновления окружения из git (services/Dotfiles.qml): репозиторий, ветка, автопроверка
    property alias updateRepo: cfg.updateRepo
    property alias updateBranch: cfg.updateBranch
    property alias updateAuto: cfg.updateAuto
    // загрузка и вход (Настройки → Загрузка и вход): меню Limine и экран входа LightDM
    property alias bootTimeout: cfg.bootTimeout
    property alias bootRemember: cfg.bootRemember
    property alias bootWallpaper: cfg.bootWallpaper
    property alias bootOtherSystems: cfg.bootOtherSystems
    property alias greeterBlur: cfg.greeterBlur
    property alias greeterClock: cfg.greeterClock
    property alias greeterUserImage: cfg.greeterUserImage
    property alias updateNotified: cfg.updateNotified
    // язык интерфейса Настроек: "en" | "ru" (services/I18n.qml)
    property alias language: cfg.language
    property alias trayMode: cfg.trayMode
    property alias trayPinned: cfg.trayPinned

    function trayIsPinned(id) {
        return (trayPinned ?? []).includes(id);
    }

    function setTrayPinned(id, on) {
        const l = (trayPinned ?? []).filter(x => x !== id);
        if (on) l.push(id);
        trayPinned = l;
    }

    // ── уведомления
    property alias popupTimeout: cfg.popupTimeout  // секунды по умолчанию

    // ── ввод (пишется в niri)
    property alias input: cfg.input

    // ── мониторы (пишутся в niri): { name: { mode, scale, transform, x, y, vrr, off } }
    property alias outputs: cfg.outputs

    readonly property bool loaded: file.loaded

    function module(name) {
        return barModules[name] !== false;
    }

    // модуль с заданным значением по умолчанию (новые модули по умолчанию выключены)
    function moduleOn(name, def) {
        const v = barModules[name];
        return v === undefined ? def : v;
    }

    function setModule(name, on) {
        const m = Object.assign({}, barModules);
        m[name] = on;
        barModules = m;
    }

    function setInput(key, value) {
        const i = JSON.parse(JSON.stringify(input));
        i[key] = value;
        input = i;
        NiriSettings.write();
    }

    function setMouse(key, value) {
        setInputIn("mouse", key, value);
    }

    // поле вложенного раздела ввода: mouse / touchpad / tablet
    function setInputIn(section, key, value) {
        const i = JSON.parse(JSON.stringify(input));
        i[section] = Object.assign({}, i[section], { [key]: value });
        input = i;
        NiriSettings.write();
    }

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: file.writeAdapter()
    }

    FileView {
        id: file
        path: Quickshell.statePath("settings.json")
        blockLoading: true
        printErrors: false
        // запись одним вызовом с задержкой: запись на каждое поле теряет значения
        onAdapterUpdated: saveTimer.restart()

        JsonAdapter {
            id: cfg

            property string scheme: "dark"
            property string font: "JetBrainsMono Nerd Font"
            property string monoFont: "JetBrainsMono Nerd Font"
            property string appFont: ""

            property bool transparency: false
            property real opacity: 0.85
            property bool blur: true
            property real terminalOpacity: 1

            property bool weekStartsMonday: true

            property var power: ({ lock: 0, screenOff: 0, suspend: 0, lockOnSuspend: true })
            property var autostart: ([])
            property var binds: ([])
            property string barStyle: "flat"
            property string primaryOutput: ""
            property bool developerMode: false
            property var plugins: ({})
            property var barScreens: ([])
            property var nightLight: ({ enabled: false, temp: 4500, auto: false })

            property var widgets: ({
                clock: { enabled: false, screen: "", x: 80, y: 90, background: false, font: "", size: 1, format: "HH:mm", showDate: true },
                perf: { enabled: false, screen: "", x: 80, y: 360, background: true, size: 1 },
                weather: { enabled: false, screen: "", x: 80, y: 560, background: true, size: 1 },
                media: { enabled: false, screen: "", x: 460, y: 560, background: true, size: 1 },
                calendar: { enabled: false, screen: "", x: 1500, y: 90, background: true, size: 1 },
                notes: { enabled: false, screen: "", x: 1500, y: 420, background: true, size: 1 },
                quote: { enabled: false, screen: "", x: 460, y: 360, background: false, size: 1 },
            })
            property real uiScale: 1

            property int barHeight: 32
            property string clockFormat: "dddd HH:mm"
            property string workspaceStyle: "dots"
            property var barModules: ({})
            property string language: "en"
            property string updateRepo: ""
            property string updateBranch: "main"
            property bool updateAuto: true
            property int bootTimeout: 5
            property bool bootRemember: true
            property bool bootWallpaper: true
            property bool bootOtherSystems: true
            property bool greeterBlur: true
            property bool greeterClock: true
            property bool greeterUserImage: false
            property string updateNotified: ""
            property string trayMode: "inline"
            property var trayPinned: ([])

            property int popupTimeout: 5

            property var input: ({
                layouts: ["us", "ru"],
                switchKey: "grp:caps_toggle",
                repeatDelay: 600,
                repeatRate: 25,
                numlock: true,
                focusFollowsMouse: true,
                mouse: { accelSpeed: 0, accelProfile: "adaptive", naturalScroll: false, leftHanded: false },
                touchpad: { tap: true, naturalScroll: true },
            })

            property var outputs: ({})
        }
    }

    // миграция старого виджета «Телефон» в экземпляр phone-1
    Component.onCompleted: {
        const old = cfg.widgets?.phone;
        if (old) {
            const w = JSON.parse(JSON.stringify(cfg.widgets));
            delete w.phone;
            if (old.enabled) w["phone-1"] = Object.assign({ type: "phone", device: "", variant: "full" }, old);
            cfg.widgets = w;
        }
    }
}
