pragma Singleton
import QtQuick
import Quickshell

// цвета и размеры; схема выбирается в настройках (Персонализация)
Singleton {
    id: root

    readonly property var schemes: ({
        dark: {
            name: "Dark", bg: "#151515", surface: "#1b1b1b", surfaceHi: "#222222", surfaceHi2: "#2a2a2a", line: "#3a3a3a",
            fg: "#d4d4d4", fgHover: "#e6e6e6", fgPressed: "#bdbdbd", muted: "#a0a0a0", dim: "#6b6b6b", faint: "#333333",
            urgent: "#c96a6a", warn: "#d7a65f", accent: "#d4d4d4", rec: "#e05d5d",
        },
        light: {
            name: "Light", bg: "#f3f3f3", surface: "#e8e8e8", surfaceHi: "#dfdfdf", surfaceHi2: "#d4d4d4", line: "#c2c2c2",
            fg: "#1f1f1f", fgHover: "#3a3a3a", fgPressed: "#555555", muted: "#474747", dim: "#858585", faint: "#c6c6c6",
            urgent: "#c0463f", warn: "#b7791f", accent: "#1f1f1f", rec: "#d64545",
        },
        nord: {
            name: "Nord", bg: "#1e222a", surface: "#252a33", surfaceHi: "#2e3440", surfaceHi2: "#3b4252", line: "#4c566a",
            fg: "#d8dee9", fgHover: "#e5e9f0", fgPressed: "#b8c0cc", muted: "#a3adbd", dim: "#6c7689", faint: "#3b4252",
            urgent: "#bf616a", warn: "#ebcb8b", accent: "#88c0d0", rec: "#bf616a",
        },
        gruvbox: {
            name: "Gruvbox", bg: "#1d2021", surface: "#242627", surfaceHi: "#2c2e2f", surfaceHi2: "#353230", line: "#504945",
            fg: "#ebdbb2", fgHover: "#fbf1c7", fgPressed: "#d5c4a1", muted: "#bdae93", dim: "#7c6f64", faint: "#3c3836",
            urgent: "#fb4934", warn: "#fabd2f", accent: "#fe8019", rec: "#fb4934",
        },
        rose: {
            name: "Rosé", bg: "#191724", surface: "#1f1d2e", surfaceHi: "#26233a", surfaceHi2: "#2d2a44", line: "#403d52",
            fg: "#e0def4", fgHover: "#eeecfb", fgPressed: "#c4c1da", muted: "#908caa", dim: "#6e6a86", faint: "#312e47",
            urgent: "#eb6f92", warn: "#f6c177", accent: "#c4a7e7", rec: "#eb6f92",
        },
    })

    readonly property var palette: Settings.scheme === "wallpaper" && WallColors.palette
        ? WallColors.palette
        : (schemes[Settings.scheme] ?? schemes.dark)

    readonly property bool isLight: Settings.scheme === "light"

    // плавная смена схемы
    property color bg: palette.bg
    property color surface: palette.surface
    property color surfaceHi: palette.surfaceHi
    property color surfaceHi2: palette.surfaceHi2
    property color line: palette.line
    property color fg: palette.fg
    property color fgHover: palette.fgHover
    property color fgPressed: palette.fgPressed
    property color muted: palette.muted
    property color dim: palette.dim
    property color faint: palette.faint
    property color urgent: palette.urgent
    property color warn: palette.warn
    property color accent: palette.accent
    property color rec: palette.rec

    Behavior on bg { ColorAnimation { duration: 400 } }
    Behavior on surface { ColorAnimation { duration: 400 } }
    Behavior on surfaceHi { ColorAnimation { duration: 400 } }
    Behavior on surfaceHi2 { ColorAnimation { duration: 400 } }
    Behavior on line { ColorAnimation { duration: 400 } }
    Behavior on fg { ColorAnimation { duration: 400 } }
    Behavior on fgHover { ColorAnimation { duration: 400 } }
    Behavior on fgPressed { ColorAnimation { duration: 400 } }
    Behavior on muted { ColorAnimation { duration: 400 } }
    Behavior on dim { ColorAnimation { duration: 400 } }
    Behavior on faint { ColorAnimation { duration: 400 } }
    Behavior on accent { ColorAnimation { duration: 400 } }

    readonly property string font: Settings.font || "JetBrainsMono Nerd Font"

    // прозрачность панелей (Персонализация → Прозрачность)
    // размытие под панелями: окно просит его само (протокол background-effect) и только под нужной областью
    readonly property bool blurOn: Settings.transparency && Settings.blur
    readonly property real panelAlpha: Settings.transparency ? Settings.opacity : 1
    readonly property color panel: Qt.rgba(bg.r, bg.g, bg.b, panelAlpha)
    readonly property color panelSurface: Qt.rgba(surface.r, surface.g, surface.b, Settings.transparency ? Math.min(1, Settings.opacity + 0.05) : 1)
    readonly property int fontSize: Math.round(13 * Settings.uiScale)
    readonly property int iconSize: Math.round(15 * Settings.uiScale)

    readonly property int barHeight: Settings.barHeight
    readonly property int padding: 12
    readonly property int spacing: 14

    readonly property int radius: 10
    readonly property int popupPadding: 14

    readonly property int animFast: 120
    readonly property int animSlow: 220
}
