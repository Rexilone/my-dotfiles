//@ pragma Env QSG_USE_SIMPLE_ANIMATION_DRIVER=1
// ↑ анимации идут по реальной частоте экрана (180 Гц), а не по фиксированным 60
//@ pragma IconTheme Adwaita
// приложения, запущенные из шелла (лаунчер), берут цвета из GTK-темы
//@ pragma Env QT_QPA_PLATFORMTHEME=gtk3
//@ pragma Env QT_WAYLAND_DISABLED_INTERFACES=zwp_text_input_manager_v3
// ↑ протокол ввода для IME (text-input-v3) в qt6-wayland 6.12 роняет шелл (падение в обработке событий
// Wayland); раскладки и обычный ввод с клавиатуры идут без него

import QtQuick
import Quickshell
import qs.services

ShellRoot {
    // напоминания работают в фоне, даже если календарь не открывали
    readonly property var notes: Notes
    Variants {
        model: Quickshell.screens.filter(s => Settings.barOn.includes(s.name))

        Bar {}
    }

    Launcher {}
    PowerMenu {}
    PolkitDialog {}
    Clipboard {}
    RecorderMenu {}
    WallpaperSwitcher {}
    SettingsWindow {}
    // «Программы»: установка приложений (pacman + AUR), открывается из меню приложений
    StoreWindow {}
    DesktopWidgets {}
    PluginServices {}
    // входящий звонок с телефона (Rexlink)
    PhoneCall {}
    // быстрый ответ на уведомление телефона
    PhoneReply {}
    // нижний индикатор: громкость, микрофон, яркость, голосовой ввод
    Osd {}
    // лупа: Super+Shift+колесо (как в KDE)
    Zoom {}
    // цвета «под обои» считаются в фоне
    readonly property var wallColors: WallColors
    // настройки niri: сразу узнаём мониторы, чтобы запись конфига их не потеряла
    readonly property var niriSettings: NiriSettings
    // тема для foot, nvim, yazi и fzf
    readonly property var themeSync: ThemeSync
    // таймеры простоя (Электропитание)
    readonly property var power: Power
    readonly property var nightLight: NightLight
    readonly property var updates: Updates
    // скрытые с демонстрации приложения (Super+G): индикатор в баре
    readonly property var castHide: CastHide
    // графический планшет через OpenTabletDriver (если установлен)
    readonly property var tablet: Tablet
    // обновления окружения из git (Настройки → Updates)
    readonly property var dotfiles: Dotfiles
    // меню загрузки и экран входа в стиле шелла (тема для rexilone-boot)
    readonly property var bootTheme: BootTheme
}
