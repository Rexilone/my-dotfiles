// Rexilone Shell на amane — тот же шелл, что в ~/.config/quickshell, на Rust.
// Переключение: rexilone-shell use amane | quickshell. Настройки (тема, бар) общие с Quickshell.

mod apps;
mod bar;
mod boottheme;
mod clipboard;
mod clock;
mod devices;
mod dotfiles;
mod cmd;
mod i18n;
mod icons;
mod idle;
mod json;
mod launcher;
mod look;
mod md5;
mod meter;
mod mixer;
mod net;
mod niri;
mod nightlight;
mod niriconf;
mod notifs;
mod osd;
mod otd;
mod popups;
mod power;
mod prefs;
mod pw;
mod rexlink;
mod search;
mod settings;
mod theme;
mod themesync;
mod ui;
mod wallpaper;
mod weather;

use amane::{App, Service};

// монитор для меню: где сейчас фокус, иначе главный
pub fn focus_output() -> String {
    let n = niri::Niri::read();
    let f = n.s.focused_output().to_string();
    if !f.is_empty() {
        return f;
    }
    settings::Settings::read().c.primary(&n.s.outputs)
}

fn notifications(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("dnd") => notifs::toggle_dnd(),
        Some("clear") => amane::Notifications::clear(),
        _ => popups::toggle("notifications"),
    }
    String::from("ok")
}

fn theme(_: &[String]) -> String {
    popups::toggle_dark();
    String::from("ok")
}

fn control(args: &[String]) -> String {
    popups::toggle(args.first().map(String::as_str).unwrap_or("control"));
    String::from("ok")
}

fn main() {
    // фоновые службы: конфиг niri и тема приложений (REXILONE_NO_SERVICES=1 — проверка рядом с Quickshell)
    drop(niriconf::NiriConf::read());
    if std::env::var_os("REXILONE_NO_SERVICES").is_none() {
        drop(themesync::ThemeSync::read());
        drop(nightlight::NightLight::read());
        drop(idle::Idle::read());
        drop(dotfiles::Dotfiles::read());
        drop(dotfiles::PkgUpdates::read());
        drop(boottheme::BootTheme::read());
        drop(devices::Devices::read());
        drop(otd::Tablet::read());
    }
    let font = settings::Settings::read().c.font.clone();
    App::new()
        .font(&font)
        .window_per_monitor(bar::view)
        .window_per_monitor(popups::view)
        .window_per_monitor(notifs::view)
        .window_per_monitor(osd::view)
        .window_per_monitor(launcher::view)
        .window_per_monitor(clipboard::view)
        .window_per_monitor(wallpaper::view)
        .window_per_monitor(power::view)
        .ipc("launcher", launcher::ipc)
        .ipc("power", power::ipc)
        .ipc("clipboard", clipboard::ipc)
        .ipc("wallpaper", wallpaper::ipc)
        .ipc("notifications", notifications)
        .ipc("control", control)
        .ipc("theme", theme)
        .ipc("settings", prefs::ipc)
        .ipc("idle", idle::ipc)
        .ipc("updates", dotfiles::ipc)
        .run();
}
