pragma Singleton
import QtQuick
import Quickshell
import qs.services

// оформление проводника под Nautilus (Adwaita): шрифт интерфейса, панели, наведение и выделение.
// Цвета — из темы шелла, полупрозрачные слои поверх неё — как в Adwaita
Singleton {
    readonly property string ui: "Adwaita Sans"
    readonly property string glyphs: Theme.font          // значки-символы (Nerd Font)
    readonly property int fs: Math.round(14 * Settings.uiScale)
    readonly property int fsSmall: fs - 2
    readonly property int icon: Math.round(16 * Settings.uiScale)

    readonly property color fg: Theme.fg
    readonly property color dim: Theme.dim
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    readonly property color sidebar: Theme.panelSurface  // боковая панель светлее
    readonly property color view: Theme.panel            // папка и её шапка
    readonly property color card: Theme.surface          // диалоги
    readonly property color popover: Theme.surfaceHi     // меню
    readonly property color hover: alpha(Theme.fg, 0.07)
    readonly property color press: alpha(Theme.fg, 0.15)
    readonly property color active: alpha(Theme.fg, 0.11) // выбранное место в боковой панели
    readonly property color field: alpha(Theme.fg, 0.08)  // строка пути, кнопки с фоном
    readonly property color sep: alpha(Theme.fg, 0.1)
    readonly property color sel: alpha(Theme.accent, 0.3)
    readonly property color selHover: alpha(Theme.accent, 0.38)
    readonly property color shade: Qt.rgba(0, 0, 0, Theme.isLight ? 0.25 : 0.45)
}
