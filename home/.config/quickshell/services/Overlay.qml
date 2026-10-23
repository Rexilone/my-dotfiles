pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// оверлей в играх (MangoHud): FPS, время кадра, загрузка и температуры CPU/GPU, память.
// Настройки → Игры. Конфиг ~/.config/MangoHud/MangoHud.conf собирается здесь, в цветах темы шелла;
// MANGOHUD=1 — только для Steam (свой ярлык steam.desktop): игры получают его от Steam, остальные программы —
// нет (раньше переменная была на весь сеанс и цепляла оверлей к шеллу, браузерам, Electron).
// Показать/спрятать в игре — Shift_R+F12.
Singleton {
    id: root

    readonly property var cfg: Settings.overlay ?? {}
    readonly property bool enabled: cfg.enabled === true
    property bool installed: false
    readonly property string toggleKey: "Shift_R+F12"

    function hex(c) {
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return h(c.r) + h(c.g) + h(c.b);
    }

    readonly property string conf: {
        const c = cfg;
        const L = ["# генерирует Quickshell (Настройки → Игры) — правки вручную перезапишутся",
                   "legacy_layout=false",
                   `position=${c.position ?? "top-left"}`,
                   `font_size=${Math.round(20 * (c.scale ?? 1))}`,
                   `background_alpha=${Number(c.opacity ?? 0.5).toFixed(2)}`,
                   "round_corners=10",
                   `toggle_hud=${toggleKey}`,
                   // не в играх: плееры и браузеры на Vulkan
                   "blacklist=mpv,chromium,chrome,firefox,zen,helium,brave,vivaldi,obs,steamwebhelper,qs,quickshell",
                   `text_color=${hex(Theme.fg)}`,
                   `background_color=${hex(Theme.bg)}`,
                   `gpu_color=${hex(Theme.accent)}`,
                   `cpu_color=${hex(Theme.accent)}`,
                   `vram_color=${hex(Theme.muted)}`,
                   `ram_color=${hex(Theme.muted)}`,
                   `engine_color=${hex(Theme.accent)}`,
                   `frametime_color=${hex(Theme.accent)}`];
        if (!(c.visible ?? true)) L.push("no_display");
        if (c.fps ?? true) L.push("fps");
        if (c.frametime ?? true) L.push("frame_timing=1");
        if (c.cpu ?? true) L.push("cpu_stats");
        if ((c.cpu ?? true) && (c.temps ?? true)) L.push("cpu_temp");
        if (c.gpu ?? true) L.push("gpu_stats");
        if ((c.gpu ?? true) && (c.temps ?? true)) L.push("gpu_temp");
        if (c.ram ?? true) L.push("ram");
        if (c.vram ?? true) L.push("vram");
        return L.join("\n") + "\n";
    }

    // конфиг пишется всегда (его читает и `mangohud игра` вручную); переменная — только если включено
    onConfChanged: writeLater.restart()
    onEnabledChanged: {
        NiriSettings.write();
        env.running = true;
    }
    Timer {
        id: writeLater
        interval: 500
        onTriggered: file.setText(root.conf)
    }
    FileView {
        id: file
        path: `${Quickshell.env("HOME")}/.config/MangoHud/MangoHud.conf`
        printErrors: false
    }
    Component.onCompleted: {
        writeLater.restart();
        env.running = true;
    }

    // ярлык Steam с MANGOHUD=1 (~/.local/share/applications перекрывает системный); выключили — убрать свой.
    // Заодно убрать старую глобальную переменную (environment.d, systemd) — она была на все программы.
    Process {
        id: env
        command: ["sh", "-c", `
            rm -f ~/.config/environment.d/90-rexilone-mangohud.conf
            systemctl --user unset-environment MANGOHUD
            f=~/.local/share/applications/steam.desktop
            if [ "$1" = 1 ] && [ -f /usr/share/applications/steam.desktop ]; then
                mkdir -p ~/.local/share/applications
                { echo "# RexOS: оверлей MangoHud в играх (Настройки → Игры)"
                  sed 's#^Exec=/usr/bin/steam#Exec=env MANGOHUD=1 /usr/bin/steam#' /usr/share/applications/steam.desktop; } > "$f"
            elif grep -q "^# RexOS: оверлей MangoHud" "$f" 2>/dev/null; then
                rm -f "$f"
            fi`, "sh", root.enabled ? "1" : "0"]
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v mangohud"]
        stdout: StdioCollector {
            onStreamFinished: root.installed = text.trim() !== ""
        }
    }

    function install() {
        Quickshell.execDetached(["pkexec", "pacman", "-S", "--needed", "--noconfirm", "mangohud", "lib32-mangohud"]);
    }
    // Steam перезапускается с новым окружением — оверлей появится в играх
    function restartSteam() {
        Quickshell.execDetached(["sh", "-c", 'steam -shutdown; for i in $(seq 30); do pgrep -x steam >/dev/null || break; sleep 1; done; '
            + (enabled ? "MANGOHUD=1 " : "env -u MANGOHUD ") + 'niri msg action spawn -- steam']);
    }
}
