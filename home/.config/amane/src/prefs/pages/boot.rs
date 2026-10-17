// Загрузка и вход: меню Limine и экран входа в стиле шелла, системы на других дисках (BootPage.qml)

use amane::{Center, End, Rectangle, Row, Service, children};

use super::super::w::{self, Btn, Card, W, bx};
use super::Out;
use crate::boottheme::{self, BootTheme};
use crate::json::Json;
use crate::look::Tk;
use crate::settings::{self, Settings};
use crate::ui::ic;

fn sw(t: &Tk, key: &'static str, def: bool) -> amane::Rectangle {
    let on = Settings::read().raw.get(key).bool_or(def);
    w::switch(t, key, on, move |v| settings::save_key(key, Json::Bool(v)))
}

pub fn page(t: &Tk, w: f32) -> Out {
    let b = BootTheme::read();
    let (installed, outdated, busy, dots) = (b.installed, b.outdated, b.busy, b.dots.clone());
    let st = b.status.clone();
    let systems = b.systems().to_vec();
    drop(b);
    let mut items: Vec<W> = Vec::new();
    if !installed || outdated {
        items.push(bx(Card::new(0xF0026, if installed { "The boot service has an update" } else { "The boot service is not set up" }, "rexilone-boot themes the boot menu and the login screen and finds systems on other disks. Needs the password once")
            .ctrl(Btn::new(if busy { "Installing…" } else if installed { "Update" } else { "Set up" }).primary().enabled(!busy && !dots.is_empty()).build(t, "boot-setup", boottheme::setup))
            .build(t, w)));
    }
    if installed {
        let locked = st.get("locked").bool_or(false);
        let desc = if locked {
            t.t("Limine has an enrolled config hash (Secure Boot) — the boot menu isn't changed; the login screen still is")
        } else if let Some(tm) = st.get("time").num() {
            let c = crate::clock::civil(tm as i64, crate::clock::Clock::read().offset);
            format!("{}   ·   {} {}", t.t("On every shutdown and boot"), t.t("last time"), crate::clock::format("dd.MM HH:mm", &c, t.c.ru()))
        } else {
            t.t("On every shutdown and boot. Apply now to see it on the next start")
        };
        items.push(bx(Card::new(0xF0493, if locked { "The boot menu is locked" } else { "Applied automatically" }, &desc)
            .ctrl(Btn::new(if busy { "Applying…" } else { "Apply now" }).primary().enabled(!busy).build(t, "boot-apply", boottheme::apply_now))
            .build(t, w)));
    }
    items.push(bx(w::section(t, "Boot menu (Limine)", w)));
    let to = format!("{}", Settings::read().raw.get("bootTimeout").num_or(5.0) as i64);
    let ru = t.c.ru();
    items.push(bx(Card::new(0xF051B, "Show the menu for", "Then the selected system starts by itself")
        .ctrl(w::choice(t, "boot-timeout", &[("0", if ru { "сразу" } else { "skip" }), ("3", "3 s"), ("5", "5 s"), ("10", "10 s"), ("-1", if ru { "ждать" } else { "wait" })], &to, |v| {
            settings::save_key("bootTimeout", Json::Num(v.parse().unwrap_or(5.0)))
        }))
        .build(t, w)));
    items.push(bx(Card::new(0xF0450, "Remember the last system", "Start what was chosen last time").ctrl(sw(t, "bootRemember", true)).build(t, w)));
    items.push(bx(Card::new(0xF0E09, "Wallpaper in the boot menu", "The current wallpaper under a card in the scheme's colors").ctrl(sw(t, "bootWallpaper", true)).build(t, w)));

    let mut head: Vec<W> = vec![bx(w::section(t, "Other systems", w - 170.0))];
    if installed {
        head.push(bx(Rectangle::new().width(160.0).height(54.0).align_child(End, End).child(Btn::new("Search disks").icon(ic::SEARCH).enabled(!busy).build(t, "boot-scan", boottheme::scan_now))));
    }
    items.push(bx(Row::new(head).align(End)));
    let others = Settings::read().raw.get("bootOtherSystems").bool_or(true);
    items.push(bx(Card::new(0xF02CA, "Find systems on connected disks", "Windows and other Linux on any disk — plug it in and it appears in the boot menu by itself").ctrl(sw(t, "bootOtherSystems", true)).build(t, w)));
    if others && systems.is_empty() {
        items.push(bx(w::para(t, &t.t("Nothing yet besides this system. Connect a disk with Windows or another Linux — it's found automatically."), t.fs - 1.0, t.p.dim, w)));
    }
    if others {
        for s in systems {
            let name = s.get("name").str_or("");
            let own = s.get("own").bool_or(false);
            let title = if own { name.clone() } else { format!("{name}   ·   {}", s.get("disk").str_or("")) };
            let kind = if own {
                t.t("This disk")
            } else if s.get("removable").bool_or(false) || s.get("tran").str() == Some("usb") {
                t.t("External disk")
            } else {
                t.t("Another disk")
            };
            let present = s.get("present").bool_or(false);
            let hidden = s.get("hidden").bool_or(false);
            let mut d = vec![kind, t.t(if present { "connected" } else { "not connected" })];
            if hidden {
                d.push(t.t("hidden from the menu"));
            }
            let path = s.get("path").str_or("");
            if !path.is_empty() {
                d.push(path);
            }
            let id = s.get("id").str_or("");
            let mut ctrl: Vec<W> = Vec::new();
            if !present {
                let i = id.clone();
                ctrl.push(bx(Btn::new("Forget").enabled(!busy).build(t, &format!("forget:{id}"), move || boottheme::forget(&i))));
            }
            let i = id.clone();
            ctrl.push(bx(w::switch(t, &format!("sys:{id}"), !hidden, move |v| if v { boottheme::show(&i) } else { boottheme::hide(&i) })));
            let icon = if name.to_lowercase().contains("windows") { 0xF05B3 } else { 0xF033D };
            items.push(bx(Card::new(icon, &title, &d.join("   ·   ")).id(&id).ctrl(Row::new(ctrl).gap(8.0).align(Center)).build(t, w)));
        }
    }

    items.push(bx(w::section(t, "Login screen", w)));
    let dms: Vec<String> = st.get("dms").arr().iter().filter_map(|v| v.str().map(String::from)).collect();
    let dm = st.get("dm").str_or("");
    if installed && !dms.is_empty() {
        let mut opts = vec![("rexilone", "Rexilone")];
        if dms.iter().any(|d| d == "lightdm") {
            opts.push(("lightdm", "LightDM"));
        }
        let cur = if dm == "greetd" { "rexilone" } else if dm == "lightdm" { "lightdm" } else { "" };
        let desc = if dm == "greetd" { "Rexilone — like the shell: the bar, the card, the colors and the wallpaper. Takes effect on the next boot" } else { "LightDM — the classic GTK login screen. Takes effect on the next boot" };
        items.push(bx(Card::new(ic::LOCK, "Login screen", desc).ctrl(w::choice(t, "dm", &opts, cur, move |v| if !busy { boottheme::set_dm(&v) })).build(t, w)));
    }
    if installed && !dms.iter().any(|d| d == "rexilone") {
        items.push(bx(Card::new(0xF0026, "The Rexilone login screen isn't installed", "Needs the greetd package: Settings → Updates installs missing packages, then Update the boot service above").build(t, w)));
    }
    items.push(bx(Card::new(0xF0E09, "Blurred wallpaper", "Otherwise the wallpaper as is").ctrl(sw(t, "greeterBlur", true)).build(t, w)));
    items.push(bx(Card::new(0xF0954, "Date and time in the top bar", "").ctrl(sw(t, "greeterClock", true)).build(t, w)));
    items.push(bx(Card::new(0xF0004, "User picture", "~/.face — the picture next to the password field").ctrl(sw(t, "greeterUserImage", false)).build(t, w)));
    items.push(bx(w::gap(10.0)));
    items.push(bx(w::para(t, &t.t("Changes are saved now and reach the boot menu and the login screen on the next shutdown — or right away with Apply now."), t.fs - 2.0, t.p.dim, w)));
    let _ = (Center, children![w::gap(1.0)]);
    Out { crumb: String::new(), subtitle: "Boot menu and login screen follow the shell's colors and wallpaper".into(), items }
}
