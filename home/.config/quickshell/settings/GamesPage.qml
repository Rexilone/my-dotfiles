import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// Игры: игровой режим и оверлей MangoHud
Page {
    id: page

    title: "Games"
    subtitle: "Game mode and the in-game overlay"

    readonly property var g: Settings.gameMode ?? {}
    readonly property var o: Settings.overlay ?? {}

    // ═════════════════════════ игровой режим
    SSection { text: I18n.tr("Game mode") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF0297)
            title: GameMode.active ? "Game mode is on" : "Game mode"
            desc: GameMode.active ? (GameMode.game?.title ?? I18n.tr("Turned on by hand"))
                : "Turns on by itself while a game is open: Steam, Proton, Wine, gamescope"
            SSwitch {
                checked: GameMode.active
                onToggled: GameMode.toggle()
            }
        }
        SCard {
            icon: String.fromCodePoint(0xF0068)
            title: "Turn on by itself"
            desc: "When a game window opens; off again when it closes"
            SSwitch { checked: page.g.auto ?? true; onToggled: v => Settings.setGame("auto", v) }
        }
    }

    SSection { text: I18n.tr("While playing") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF009B)
            title: "Do not disturb"
            desc: "Notifications don't pop up, only urgent ones. They stay in the list"
            SSwitch { checked: page.g.dnd ?? true; onToggled: v => Settings.setGame("dnd", v) }
        }
        SCard {
            icon: String.fromCodePoint(0xF04C5)
            title: "Performance"
            desc: GameMode.gamemodeInstalled
                ? "«Performance» power profile and gamemode: CPU at full speed, game first in line"
                : "«Performance» power profile (install gamemode for CPU tuning too)"
            SSwitch { checked: page.g.performance ?? true; onToggled: v => Settings.setGame("performance", v) }
        }
        SCard {
            icon: String.fromCodePoint(0xF1592)
            title: "No animations"
            desc: "Windows and workspaces switch instantly (niri)"
            SSwitch { checked: page.g.noAnimations ?? true; onToggled: v => Settings.setGame("noAnimations", v) }
        }
        SCard {
            icon: String.fromCodePoint(0xF03E4)
            title: "Pause effects"
            desc: "Live wallpaper and the audio visualizer stop"
            SSwitch { checked: page.g.pauseEffects ?? true; onToggled: v => Settings.setGame("pauseEffects", v) }
        }
        SCard {
            icon: String.fromCodePoint(0xF0B92)
            title: "Hide desktop widgets"
            SSwitch { checked: page.g.hideWidgets ?? false; onToggled: v => Settings.setGame("hideWidgets", v) }
        }
    }

    // ═════════════════════════ оверлей
    SSection { text: I18n.tr("In-game overlay") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            visible: !Overlay.installed
            icon: String.fromCodePoint(0xF0026)
            title: "MangoHud is not installed"
            desc: "It draws the overlay inside games"
            SButton { text: I18n.tr("Install"); primary: true; onClicked: Overlay.install() }
        }
        SCard {
            icon: String.fromCodePoint(0xF0A07)
            title: "Overlay in games"
            desc: `${I18n.tr("FPS, CPU, GPU, temperatures and memory in Vulkan games (Proton, DXVK)")}   ·   ${Overlay.toggleKey} — ${I18n.tr("show / hide")}`
            SSwitch { checked: page.o.enabled ?? false; onToggled: v => Settings.setOverlay("enabled", v) }
        }
        SCard {
            visible: page.o.enabled ?? false
            icon: String.fromCodePoint(0xF0450)
            title: "Restart Steam"
            desc: "Steam passes the overlay to its games only after a restart. Prism Launcher: turn on MangoHud in the instance settings"
            SButton { text: I18n.tr("Restart"); onClicked: Overlay.restartSteam() }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: page.o.enabled ?? false
        spacing: 3

        SCard {
            title: "Shown when a game starts"
            desc: `${I18n.tr("Otherwise hidden until")} ${Overlay.toggleKey}`
            SSwitch { checked: page.o.visible ?? true; onToggled: v => Settings.setOverlay("visible", v) }
        }
        SCard {
            title: "Position"
            SChoice {
                options: [
                    { value: "top-left", label: "↖" }, { value: "top-center", label: "↑" }, { value: "top-right", label: "↗" },
                    { value: "bottom-left", label: "↙" }, { value: "bottom-right", label: "↘" },
                ]
                current: page.o.position ?? "top-left"
                onPicked: v => Settings.setOverlay("position", v)
            }
        }
        SCard {
            title: "Size"
            SChoice {
                options: [0.8, 1, 1.25, 1.5].map(v => ({ value: v, label: { 0.8: "S", 1: "M", 1.25: "L", 1.5: "XL" }[v] }))
                current: page.o.scale ?? 1
                onPicked: v => Settings.setOverlay("scale", v)
            }
        }
        SCard {
            title: "Background"
            SSlider {
                from: 0
                to: 1
                step: 0.05
                value: page.o.opacity ?? 0.5
                display: value * 100
                suffix: "%"
                onMoved: v => Settings.setOverlay("opacity", Math.round(v * 100) / 100)
            }
        }

        Repeater {
            model: [
                { key: "fps", title: "FPS" },
                { key: "frametime", title: "Frame time graph" },
                { key: "cpu", title: "CPU load" },
                { key: "gpu", title: "GPU load" },
                { key: "temps", title: "Temperatures" },
                { key: "ram", title: "RAM" },
                { key: "vram", title: "Video memory" },
            ]
            SCard {
                id: mc
                required property var modelData
                title: modelData.title
                SSwitch {
                    checked: page.o[mc.modelData.key] ?? true
                    onToggled: v => Settings.setOverlay(mc.modelData.key, v)
                }
            }
        }
    }
}
