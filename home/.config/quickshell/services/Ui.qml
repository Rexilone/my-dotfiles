pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// общие действия интерфейса: закрыть меню бара, открыть страницу настроек
Singleton {
    id: root

    signal closeMenus

    // вкладка страницы «Телефон», которую открыть (Rexlink.show): home | notifications | messages | …
    property string phoneTab: ""

    // разделы Настроек (порядок = номер страницы, на него ссылаются страницы и IPC).
    // group — подпись в боковой панели, hidden/go/tab — ссылка на вкладку другой страницы
    readonly property var settingsPages: [
        { name: "System", keys: "home overview", icon2: 0xF0493 },
        { name: "Display", keys: "monitor screen resolution refresh hz scale rotation position vrr", icon2: 0xF0379 },
        { name: "Sound", keys: "audio volume speaker microphone output input level", icon2: 0xF057E },
        { name: "Network & Internet", keys: "wifi ethernet vpn firewall ufw internet ip dns", icon2: 0xF0200 },
        { name: "Bluetooth", keys: "devices headphones pair", icon2: 0xF00AF },
        { name: "Phone", keys: "rexlink android phone tablet watch notifications calls sms messages files clipboard webcam camera screen mirror", icon2: 0xF011C },
        // теперь вкладка «Периферии»: в меню не показываем, но поиск и `page printers` ведут туда
        { name: "Printers & scanners", keys: "print cups scan sane", icon2: 0xF042A, hidden: true, go: 10, tab: "printers" },
        { name: "Personalization", keys: "theme colors dark light wallpaper scheme accent font transparency blur bar panel clock workspaces modules tray widgets desktop weather notes quote", icon2: 0xF03D8 },
        // теперь вкладки «Персонализации»: в меню не показываем, ссылки (`page bar`) ведут туда
        { name: "Widgets", keys: "desktop clock weather notes quote", icon2: 0xF0B92, hidden: true, go: 7, tab: "widgets" },
        { name: "Bar", keys: "panel clock workspaces modules tray", icon2: 0xF0570, hidden: true, go: 7, tab: "bar" },
        { name: "Peripherals", keys: "keyboard mouse input layout language repeat pointer speed acceleration scroll touchpad tablet wacom pen stylus gamepad controller joystick printer scanner devices", icon2: 0xF0FB0 },
        { name: "Keyboard shortcuts", keys: "binds hotkeys keys", icon2: 0xF0313 },
        { name: "Startup apps", keys: "autostart login", icon2: 0xF0412 },
        { name: "Time & language", keys: "timezone clock date ntp locale language", icon2: 0xF0954 },
        { name: "Power", keys: "sleep suspend idle lock screen off caffeine profile", icon2: 0xF0425 },
        { name: "Notifications", keys: "do not disturb popups dnd", icon2: 0xF009A },
        { name: "About", keys: "device name account specs version hostname developer", icon2: 0xF02FD },
        { name: "Plugins", keys: "plugins developer extensions", icon2: 0xF0431, dev: true },
        { name: "Updates", keys: "update upgrade version git github dotfiles packages pacman", icon2: 0xF06B0 },
        { name: "Boot & login", keys: "boot limine bootloader menu login lightdm greeter password screen windows dual other systems disk", icon2: 0xF0342 },
    ]

    // порядок в боковой панели Настроек — по группам
    readonly property var settingsNav: [
        { group: "", items: [0] },
        { group: "Hardware", items: [1, 2, 10, 14] },
        { group: "Connections", items: [3, 4, 5] },
        { group: "Look & feel", items: [7, 15] },
        { group: "System", items: [11, 12, 13, 18, 19, 16, 17] },
    ]

    // последняя тёмная схема — чтобы плитка «Тёмная тема» возвращала её
    property string lastDark: Settings.scheme !== "light" ? Settings.scheme : "dark"

    function toggleDark() {
        if (Settings.scheme === "light") Settings.scheme = lastDark || "dark";
        else {
            lastDark = Settings.scheme;
            Settings.scheme = "light";
        }
    }

    // действие после закрытия меню (чтобы меню не попало, например, в скриншот)
    function afterClose(cmd, delay) {
        closeMenus();
        later.command = ["sh", "-c", `sleep ${delay ?? 0.35}; exec "$@"`, "sh"].concat(cmd);
        later.running = true;
    }

    property Process later: Process {}

    function openSettings(page) {
        closeMenus();
        Quickshell.execDetached(["qs", "ipc", "call", "settings", "page", page || "system"]);
    }
}
