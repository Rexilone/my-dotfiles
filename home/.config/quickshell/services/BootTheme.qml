pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Загрузка и вход в стиле шелла: готовит тему для меню Limine и экрана входа LightDM.
// Шелл только пишет файлы в ~/.local/state/rexilone/boot/ (цвета, обои под экран, размытые обои),
// применяет их системная служба rexilone-boot (root): при выключении — сама, «Применить» — сразу.
// Состояние (найденные системы, итог) — /var/lib/rexilone/boot-status.json.
Singleton {
    id: root

    readonly property string tool: "/usr/local/lib/rexilone/rexilone-boot"
    readonly property string dir: `${Quickshell.env("HOME")}/.local/state/rexilone/boot`
    property bool installed: false
    property bool outdated: false        // в дотфайлах новее, чем установлено
    property string dots: ""             // папка дотфайлов (по ссылке ~/.config/quickshell)
    property var status: ({})
    readonly property var systems: status.systems ?? []
    property bool busy: false
    property string lastWallpaper: ""

    // экран, под который готовим обои (основной монитор)
    readonly property var scr: Settings.screenByName(Settings.primary)
    readonly property int pw: Math.round((scr?.width ?? 1920) * (scr?.devicePixelRatio ?? 1))
    readonly property int ph: Math.round((scr?.height ?? 1080) * (scr?.devicePixelRatio ?? 1))

    function hex(c) {
        const h = x => Math.round(x * 255).toString(16).padStart(2, "0");
        return `#${h(c.r)}${h(c.g)}${h(c.b)}`;
    }

    readonly property string themeJson: JSON.stringify({
        colors: {
            bg: hex(Theme.bg), panel: hex(Theme.bg), surface: hex(Theme.surface), surfaceHi: hex(Theme.surfaceHi),
            surfaceHi2: hex(Theme.surfaceHi2), fg: hex(Theme.fg), muted: hex(Theme.muted), dim: hex(Theme.dim),
            accent: hex(Theme.accent), urgent: hex(Theme.urgent), warn: hex(Theme.warn),
        },
        dark: !Theme.isLight,
        font: Settings.font || "JetBrainsMono Nerd Font",
        timeout: Settings.bootTimeout < 0 ? "no" : Settings.bootTimeout,
        remember: Settings.bootRemember,
        wallpaper: Settings.bootWallpaper,
        otherSystems: Settings.bootOtherSystems,
        greeterBlur: Settings.greeterBlur,
        greeterClock: Settings.greeterClock,
        greeterUserImage: Settings.greeterUserImage,
    }, null, 1)

    // тема или обои поменялись — переписать файлы (с задержкой: цвета меняются плавно)
    onThemeJsonChanged: stageTimer.restart()
    Connections {
        target: Wallpapers
        function onCurrentChanged() { stageTimer.restart(); }
    }
    Timer {
        id: stageTimer
        interval: 3000
        onTriggered: root.stage()
    }

    function stage() {
        themeProc.command = ["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" > "$1/theme.json.tmp" && mv "$1/theme.json.tmp" "$1/theme.json"', "sh", dir, themeJson];
        themeProc.running = true;
        const wp = Wallpapers.current;
        const key = `${wp}|${pw}x${ph}`;
        if (wp && key !== lastWallpaper && !wallProc.running) {
            lastWallpaper = key;
            wallProc.command = ["sh", "-c", `
                mkdir -p "$1" && cd "$1" || exit 1
                command -v magick >/dev/null || exit 0
                magick "$2" -auto-orient -resize "$3x$4^" -gravity center -extent "$3x$4" -strip -quality 88 jpg:wallpaper.jpg.tmp &&
                mv wallpaper.jpg.tmp wallpaper.jpg &&
                magick wallpaper.jpg -resize 25% -blur 0x10 -resize "$3x$4!" -fill black -colorize 18% -strip -quality 85 jpg:greeter.jpg.tmp &&
                mv greeter.jpg.tmp greeter.jpg`, "sh", dir, wp, String(pw), String(ph)];
            wallProc.running = true;
        }
    }

    Process { id: themeProc }
    Process {
        id: wallProc
        onExited: (code) => {
            if (code !== 0) root.lastWallpaper = "";
            if (root.pending.length) root.start();
        }
    }

    // ── системная часть
    property var pending: []
    function run(args) {
        if (busy || !installed) return;
        busy = true;
        pending = args;
        stage();
        // обои ещё готовятся — запустим, когда будут готовы
        if (!wallProc.running) startLater.restart();
    }
    Timer {
        id: startLater
        interval: 300
        onTriggered: root.start()
    }
    function start() {
        if (!pending.length) return;
        runProc.command = ["pkexec", tool].concat(pending);
        pending = [];
        runProc.running = true;
    }
    function applyNow() { run(["all"]); }
    function scanNow() { run(["scan"]); }
    function hide(id) { run(["hide", id]); }
    function show(id) { run(["show", id]); }
    function forget(id) { run(["forget", id]); }

    Process {
        id: runProc
        onExited: (code) => {
            root.busy = false;
            statusFile.reload();
        }
    }

    FileView {
        id: statusFile
        path: "/var/lib/rexilone/boot-status.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.status = JSON.parse(text());
            } catch (e) {}
        }
    }

    function check() { checkProc.running = true; }
    Process {
        id: checkProc
        running: true
        command: ["sh", "-c", `d=$(readlink -f "$HOME/.config/quickshell"); dots=\${d%/home/.config/quickshell}
            echo "dots=$dots"
            [ -x "${root.tool}" ] && echo installed
            [ -f "$dots/boot/rexilone-boot" ] && ! cmp -s "$dots/boot/rexilone-boot" "${root.tool}" && echo outdated`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.installed = text.includes("installed");
                root.outdated = text.includes("outdated");
                root.dots = (text.match(/^dots=(.*)$/m) ?? [])[1] ?? "";
            }
        }
    }

    // поставить или обновить системную часть (спросит пароль)
    function setup() {
        if (busy || !dots) return;
        busy = true;
        stage();
        setupProc.command = ["pkexec", "sh", `${dots}/boot/install-boot.sh`, dots, Quickshell.env("USER")];
        setupProc.running = true;
    }
    Process {
        id: setupProc
        onExited: {
            root.busy = false;
            root.check();
            statusFile.reload();
        }
    }

    Component.onCompleted: stageTimer.restart()
}
