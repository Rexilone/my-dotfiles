pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// живые обои: видео (mpvpaper) или анимация в цветах темы (WallpaperLayer.qml, шейдеры в shaders/).
// Settings.liveWallpaper: { kind: off | video | shader, video, shader, speed, fps, pauseFullscreen, pauseGame, pauseBattery }
// Пока они включены, обычные обои (awww/swaybg) не запускаются: файл ~/.local/state/rexilone/live.
// Пауза: окно на весь экран, игровой режим, работа от батареи — картинка замирает, нагрузки нет.
Singleton {
    id: root

    readonly property var cfg: Settings.liveWallpaper ?? {}
    readonly property string kind: cfg.kind ?? "off"
    property bool mpvpaperInstalled: false
    readonly property bool video: kind === "video" && !!cfg.video && mpvpaperInstalled
    readonly property bool shader: kind === "shader"
    readonly property bool on: video || shader

    readonly property var shaders: [
        { id: "aurora", name: "Aurora" },
        { id: "waves", name: "Waves" },
        { id: "nebula", name: "Nebula" },
        { id: "gradient", name: "Gradient" },
    ]

    readonly property bool onBattery: UPower.onBattery
    readonly property bool pausedAll: ((cfg.pauseGame ?? true) && GameMode.pauseEffects) || ((cfg.pauseBattery ?? true) && onBattery)
    property var fullscreenOutputs: []
    function pausedOn(output) {
        return pausedAll || ((cfg.pauseFullscreen ?? true) && fullscreenOutputs.includes(output));
    }

    readonly property string flag: `${Quickshell.env("HOME")}/.local/state/rexilone/live`
    readonly property string sock: `${Quickshell.env("XDG_RUNTIME_DIR")}/rexilone-mpvpaper.sock`

    // обычные обои: убрать, пока живые на экране, и вернуть после
    onOnChanged: swap.restart()
    Component.onCompleted: swap.restart()
    Timer {
        id: swap
        interval: 1200     // живой слой успевает появиться — без чёрного кадра
        onTriggered: Quickshell.execDetached(["sh", "-c", root.on
            ? 'mkdir -p "$(dirname "$1")" && touch "$1" && "$HOME/.local/bin/rexilone-wallpaper" stop'
            : '[ -e "$1" ] || exit 0; rm -f "$1"; "$HOME/.local/bin/rexilone-wallpaper" start', "sh", root.flag])
    }

    // ── видео
    // mpvpaper от прошлого запуска шелла живёт сам по себе — убрать до своего
    property bool cleaned: false
    Process {
        running: true
        command: ["pkill", "-x", "mpvpaper"]
        onExited: root.cleaned = true
    }
    Process {
        id: mpv
        running: root.video && root.cleaned
        command: ["mpvpaper", "-p"].concat((root.cfg.pauseFullscreen ?? true) ? ["-a", "FULL"] : [])
            .concat(["-o", `no-audio loop panscan=1.0 hwdec=auto input-ipc-server=${root.sock}`, "ALL", root.cfg.video ?? ""])
        onCommandChanged: if (running) { running = false; restartMpv.restart(); }
    }
    Timer {
        id: restartMpv
        interval: 300
        onTriggered: mpv.running = root.video && root.cleaned
    }
    // пауза видео (игровой режим, батарея) — через mpv IPC
    onPausedAllChanged: if (video) Quickshell.execDetached(["python3", "-c",
        'import socket,sys,json\ns=socket.socket(socket.AF_UNIX)\ns.connect(sys.argv[1])\ns.send((json.dumps({"command":["set_property","pause",sys.argv[2]=="1"]})+"\\n").encode())',
        sock, pausedAll ? "1" : "0"])

    Process {
        running: true
        command: ["sh", "-c", "command -v mpvpaper"]
        stdout: StdioCollector {
            onStreamFinished: root.mpvpaperInstalled = text.trim() !== ""
        }
    }
    function installMpvpaper() {
        Quickshell.execDetached(["foot", "--title", "Install mpvpaper", "sh", "-c", "paru -S --needed mpvpaper || yay -S --needed mpvpaper; echo; read -p 'Enter — закрыть'"]);
    }

    // ── окна на весь экран: на каком мониторе анимацию поставить на паузу
    Timer {
        running: root.shader && (root.cfg.pauseFullscreen ?? true)
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: full.running = true
    }
    Process {
        id: full
        command: ["sh", "-c", "niri msg -j workspaces; echo; niri msg -j windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\n").filter(l => l.trim());
                if (parts.length < 2) return;
                let ws = [], wins = [];
                try { ws = JSON.parse(parts[0]); wins = JSON.parse(parts[1]); } catch (e) { return; }
                const active = {};
                for (const w of ws) if (w.is_active) active[w.id] = w.output;
                const outs = [];
                for (const w of wins) {
                    const out = active[w.workspace_id];
                    const sc = out && Quickshell.screens.find(s => s.name === out);
                    const sz = w.layout?.window_size;
                    if (sc && sz && sz[0] >= sc.width - 2 && sz[1] >= sc.height - 2 && !outs.includes(out)) outs.push(out);
                }
                if (JSON.stringify(outs) !== JSON.stringify(root.fullscreenOutputs)) root.fullscreenOutputs = outs;
            }
        }
    }
}
