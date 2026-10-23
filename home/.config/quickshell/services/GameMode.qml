pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// игровой режим: включается сам, когда открыта игра (Steam/Proton, Wine, gamescope), или вручную.
// Что делает — Настройки → Игры: без уведомлений, профиль «Производительность» и gamemode (частоты процессора),
// без анимаций niri, пауза живых обоев и визуализатора, скрыть виджеты рабочего стола.
Singleton {
    id: root

    readonly property var cfg: Settings.gameMode ?? {}
    property bool manual: false
    // окно игры: Steam/Proton (steam_app_N), gamescope, Wine (*.exe), Minecraft (Java)
    readonly property var game: Object.values(Niri.windows).find(w => /^steam_app_\d+$|^gamescope$|\.exe$/i.test(w.app_id ?? "")
        || /^Minecraft[* ]\s*\d/.test(w.title ?? "")) ?? null
    readonly property bool detected: !!game
    property bool suppressed: false   // выключили вручную при открытой игре — до её закрытия
    readonly property bool active: manual || ((cfg.auto ?? true) && detected && !suppressed)
    onDetectedChanged: if (!detected) suppressed = false

    readonly property bool quiet: active && (cfg.dnd ?? true)
    readonly property bool noAnimations: active && (cfg.noAnimations ?? true)
    readonly property bool pauseEffects: active && (cfg.pauseEffects ?? true)
    readonly property bool hideWidgets: active && (cfg.hideWidgets ?? false)

    property bool gamemodeInstalled: false
    property string savedProfile: ""

    function toggle() {
        if (active) {
            manual = false;
            suppressed = detected;
        } else {
            manual = true;
            suppressed = false;
        }
    }

    onActiveChanged: {
        NiriSettings.write();      // анимации (qs-settings.kdl)
        if (cfg.performance ?? true) {
            if (active) profileGet.running = true;
            else if (savedProfile) {
                Quickshell.execDetached(["powerprofilesctl", "set", savedProfile]);
                savedProfile = "";
            }
        }
        Quickshell.execDetached(["notify-send", "-a", I18n.tr("Game mode"), "-i", "input-gaming",
            I18n.tr(active ? "Game mode on" : "Game mode off"),
            active && game ? game.title : ""]);
    }

    // поменяли настройки при включённом режиме — анимации пересобрать
    Connections {
        target: Settings
        function onGameModeChanged() { if (root.active) NiriSettings.write(); }
    }

    // профиль питания: запомнить текущий и поставить «Производительность»
    Process {
        id: profileGet
        command: ["sh", "-c", "command -v powerprofilesctl >/dev/null && powerprofilesctl get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (!p || !root.active) return;
                if (p !== "performance") root.savedProfile = p;
                Quickshell.execDetached(["powerprofilesctl", "set", "performance"]);
            }
        }
    }

    // gamemode (Feral): держим «клиента», пока режим включён — частоты и планировщик под игру
    Process {
        running: root.active && (root.cfg.performance ?? true) && root.gamemodeInstalled
        // setpriv --pdeathsig: шелл упал — режим производительности снимается сам
        command: ["setpriv", "--pdeathsig", "TERM", "gamemoderun", "sleep", "infinity"]
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v gamemoderun"]
        stdout: StdioCollector {
            onStreamFinished: root.gamemodeInstalled = text.trim() !== ""
        }
    }

    IpcHandler {
        target: "gamemode"
        // qs ipc call gamemode toggle
        function toggle(): void { root.toggle(); }
    }
}
