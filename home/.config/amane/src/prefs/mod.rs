// окно Настроек (Super+I) — как SettingsWindow.qml: слева разделы по группам и поиск, справа страница

pub mod pages;
pub mod w;

use std::collections::HashMap;
use std::time::Duration;

use amane::{
    Center, Column, Key, Padding, Parent, Rectangle, Row, ScrollArea, Service, Start, Stack, TextInput, Weight,
    Widget, Window, children, close_window, open_window,
};

use crate::look::{self, Tk};
use crate::settings::Settings;
use crate::ui;
use w::{W, bx};

pub struct Page {
    pub name: &'static str,
    pub keys: &'static str,
    pub icon: u32,
    // для разработчиков (Настройки → О системе → режим разработчика)
    pub dev: bool,
    // ссылка на вкладку другой страницы: в меню не показывается
    pub go: Option<(usize, &'static str)>,
}

const fn pg(name: &'static str, keys: &'static str, icon: u32) -> Page {
    Page { name, keys, icon, dev: false, go: None }
}

// порядок = номер страницы (на него ссылаются страницы и IPC), как Ui.settingsPages
pub const PAGES: [Page; 20] = [
    pg("System", "home overview", 0xF0493),
    pg("Display", "monitor screen resolution refresh hz scale rotation position vrr", 0xF0379),
    pg("Sound", "audio volume speaker microphone output input level", 0xF057E),
    pg("Network & Internet", "wifi ethernet vpn firewall ufw internet ip dns", 0xF0200),
    pg("Bluetooth", "devices headphones pair", 0xF00AF),
    pg("Phone", "rexlink android phone tablet watch notifications calls sms messages files clipboard webcam camera screen mirror", 0xF011C),
    Page { name: "Printers & scanners", keys: "print cups scan sane", icon: 0xF042A, dev: false, go: Some((10, "printers")) },
    pg("Personalization", "theme colors dark light wallpaper scheme accent font transparency blur bar panel clock workspaces modules tray widgets desktop weather notes quote", 0xF03D8),
    Page { name: "Widgets", keys: "desktop clock weather notes quote", icon: 0xF0B92, dev: false, go: Some((7, "widgets")) },
    Page { name: "Bar", keys: "panel clock workspaces modules tray", icon: 0xF0570, dev: false, go: Some((7, "bar")) },
    pg("Peripherals", "keyboard mouse input layout language repeat pointer speed acceleration scroll touchpad tablet wacom pen stylus gamepad controller joystick printer scanner devices", 0xF0FB0),
    pg("Keyboard shortcuts", "binds hotkeys keys", 0xF0313),
    pg("Startup apps", "autostart login", 0xF0412),
    pg("Time & language", "timezone clock date ntp locale language", 0xF0954),
    pg("Power", "sleep suspend idle lock screen off caffeine profile", 0xF0425),
    pg("Notifications", "do not disturb popups dnd", 0xF009A),
    pg("About", "device name account specs version hostname developer", 0xF02FD),
    Page { name: "Plugins", keys: "plugins developer extensions", icon: 0xF0431, dev: true, go: None },
    pg("Updates", "update upgrade version git github dotfiles packages pacman", 0xF06B0),
    pg("Boot & login", "boot limine bootloader menu login lightdm greetd greeter password screen windows dual other systems disk", 0xF0342),
];

// группы боковой панели
pub const NAV: [(&str, &[usize]); 5] = [
    ("", &[0]),
    ("Hardware", &[1, 2, 10, 14]),
    ("Connections", &[3, 4, 5]),
    ("Look & feel", &[7, 15]),
    ("System", &[11, 12, 13, 18, 19, 16, 17]),
];

// состояние окна: страница, поиск и мелочи страниц (вкладки, раскрытые списки, введённый текст)
pub struct Prefs {
    pub open: bool,
    pub page: usize,
    pub map: HashMap<String, String>,
}

impl Service for Prefs {
    fn new() -> Self {
        Prefs { open: false, page: 0, map: HashMap::new() }
    }

    fn interval() -> Duration {
        Duration::from_secs(3600)
    }
}

impl Prefs {
    pub fn get(key: &str) -> String {
        Prefs::read().map.get(key).cloned().unwrap_or_default()
    }

    // только из обработчиков (клик, ввод, IPC), не из вида
    pub fn set(key: &str, val: &str) {
        if Prefs::read().map.get(key).map(String::as_str) == Some(val) {
            return;
        }
        Prefs::write().map.insert(key.to_string(), val.to_string());
    }

    pub fn flag(key: &str) -> bool {
        Prefs::get(key) == "1"
    }

    pub fn toggle_flag(key: &str) {
        Prefs::set(key, if Prefs::flag(key) { "" } else { "1" });
    }
}

fn dev_mode() -> bool {
    Settings::read().raw.get("developerMode").bool_or(false)
}

// какие страницы видны при поиске
pub fn visible(query: &str, ru: bool, dev: bool) -> Vec<usize> {
    let q = query.trim().to_lowercase();
    (0..PAGES.len())
        .filter(|i| {
            let p = &PAGES[*i];
            (!p.dev || dev) && p.go.is_none() && {
                q.is_empty() || format!("{} {} {}", p.name, crate::i18n::tr(ru, p.name), p.keys).to_lowercase().contains(&q)
            }
        })
        .collect()
}

// найдена ли страница-ссылка (вкладка) по запросу
fn matching_links(query: &str, ru: bool) -> Vec<usize> {
    let q = query.trim().to_lowercase();
    if q.is_empty() {
        return Vec::new();
    }
    (0..PAGES.len())
        .filter(|i| PAGES[*i].go.is_some() && format!("{} {} {}", PAGES[*i].name, crate::i18n::tr(ru, PAGES[*i].name), PAGES[*i].keys).to_lowercase().contains(&q))
        .collect()
}

// открыть страницу (ссылка ведёт на вкладку другой страницы)
pub fn show(i: usize) {
    let (page, tab) = match PAGES.get(i).and_then(|p| p.go) {
        Some((go, tab)) => (go, Some(tab)),
        None => (i.min(PAGES.len() - 1), None),
    };
    {
        let mut p = Prefs::write();
        p.page = page;
        if let Some(tab) = tab {
            p.map.insert(format!("tab:{page}"), tab.to_string());
        }
        p.open = true;
    }
    open_window("settings", view);
}

pub fn close() {
    pages::phone::leave();
    Prefs::write().open = false;
    close_window("settings");
}

pub fn toggle() {
    if Prefs::read().open {
        close();
    } else {
        let page = Prefs::read().page;
        show(page);
    }
}

// rexilone-shell ipc settings toggle | open | hide | page <имя> | scheme <схема>
pub fn ipc(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("open") => show(Prefs::read().page),
        Some("hide") | Some("close") => close(),
        Some("page") => {
            let n = args.get(1).map(|s| s.to_lowercase()).unwrap_or_default();
            let alias = match n.as_str() {
                "keyboard" | "mouse" | "input" => "peripherals".to_string(),
                other => other.to_string(),
            };
            let dev = dev_mode();
            let i = PAGES.iter().position(|p| p.name.to_lowercase().starts_with(&alias) && (!p.dev || dev)).unwrap_or(0);
            show(i);
        }
        // вкладка текущей страницы: settings tab bar
        Some("tab") => {
            let page = Prefs::read().page;
            let tab = args.get(1).cloned().unwrap_or_default();
            Prefs::set(&format!("tab:{page}"), if tab == "home" { "" } else { &tab });
            show(page);
        }
        Some("scheme") => {
            let s = args.get(1).cloned().unwrap_or_default();
            if ["dark", "light", "nord", "gruvbox", "rose", "wallpaper"].contains(&s.as_str()) {
                crate::settings::save_key("scheme", crate::json::Json::Str(s));
            }
        }
        _ => toggle(),
    }
    String::from("ok")
}

const SIDE: f32 = 280.0;

fn sidebar(t: &Tk, h: f32) -> Rectangle {
    let ru = t.c.ru();
    let query = Prefs::get("query");
    let vis = visible(&query, ru, dev_mode());
    let cur = Prefs::read().page;
    let user = std::env::var("USER").unwrap_or_default();
    let host = std::fs::read_to_string("/etc/hostname").map(|s| s.trim().to_string()).unwrap_or_default();
    let inner = SIDE - 32.0;

    let avatar = Rectangle::new()
        .width(46.0)
        .height(46.0)
        .radius(amane::Full)
        .fill(t.p.accent)
        .align_child(Center, Center)
        .child(ui::bold(t, user.chars().next().map(|c| c.to_uppercase().collect::<String>()).unwrap_or_else(|| "?".into()), t.p.bg).size(20.0));
    let who = Column::new(children![
        w::line(t, &user, t.fs + 2.0, t.p.fg, inner - 70.0, true),
        w::line(t, &if host.is_empty() { t.t("Local account") } else { host }, t.fs - 2.0, t.p.dim, inner - 70.0, false)
    ])
    .gap(2.0);
    let head = Rectangle::new()
        .width(inner)
        .height(46.0 + 18.0)
        .padding(Padding { top: 0.0, right: 0.0, bottom: 18.0, left: 6.0 })
        .child(Row::new(children![avatar, who]).gap(12.0).align(Center));

    // поиск настроек
    let search = Rectangle::new()
        .width(inner)
        .height(38.0)
        .radius(10.0)
        .fill(t.p.surface)
        .padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 12.0 })
        .child(
            Row::new(children![
                ui::icon(t, ui::ic::SEARCH, t.icon - 1.0, t.p.dim),
                Rectangle::new().width(inner - 24.0 - t.icon - 10.0).height(38.0).align_child(Start, Center).child(
                    TextInput::new("prefs-search")
                        .size(t.fs - 1.0)
                        .color(t.p.fg)
                        .placeholder(t.t("Find a setting"))
                        .on_change(|q| {
                            Prefs::set("query", &q);
                            let ru = Settings::read().c.ru();
                            let vis = visible(&q, ru, dev_mode());
                            let cur = Prefs::read().page;
                            if !vis.is_empty() && !vis.contains(&cur) {
                                Prefs::write().page = vis[0];
                            }
                        })
                        .on_submit(|q| {
                            let ru = Settings::read().c.ru();
                            let links = matching_links(&q, ru);
                            let vis = visible(&q, ru, dev_mode());
                            if let Some(i) = vis.first().copied().or(links.first().copied()) {
                                show(i);
                            }
                        })
                )
            ])
            .gap(10.0)
            .height(38.0)
            .align(Center),
        );

    let mut nav: Vec<W> = Vec::new();
    for (group, items) in NAV {
        let shown: Vec<usize> = items.iter().copied().filter(|i| vis.contains(i)).collect();
        if shown.is_empty() {
            continue;
        }
        if !group.is_empty() {
            nav.push(bx(Rectangle::new().width(inner).height(14.0 + w::line_h(t.fs - 3.0) + 4.0).padding(Padding { top: 14.0, right: 0.0, bottom: 4.0, left: 14.0 }).child(w::tx(t, group, t.fs - 3.0, t.p.dim).weight(Weight::Bold))));
        }
        for i in shown {
            let p = &PAGES[i];
            let sel = i == cur;
            let id = format!("nav:{i}");
            let hv = w::hov(&id);
            let mut layers: Vec<W> = Vec::new();
            if sel {
                layers.push(bx(Rectangle::new().width(inner).height(38.0).radius(10.0).fill(t.p.surface)));
                layers.push(bx(Rectangle::new().width(3.0).height(18.0).radius(2.0).fill(t.p.accent).translate(0.0, 10.0)));
            } else if hv {
                layers.push(bx(Rectangle::new().width(inner).height(38.0).radius(10.0).fill(t.p.surface).opacity(0.6)));
            }
            let name = w::tx(t, p.name, t.fs - 1.0, if sel || hv { t.p.fg } else { t.p.muted });
            let name = if sel { name.weight(Weight::Bold) } else { name };
            layers.push(bx(Rectangle::new().width(inner).height(38.0).padding(Padding { top: 0.0, right: 10.0, bottom: 0.0, left: 16.0 }).child(
                Row::new(children![
                    Rectangle::new().width(20.0).height(38.0).align_child(Center, Center).child(ui::icon(t, p.icon, t.icon + 1.0, if sel { t.p.accent } else { t.p.muted })),
                    Rectangle::new().width(inner - 16.0 - 10.0 - 20.0 - 14.0).height(38.0).align_child(Start, Center).clip().child(name.elide())
                ])
                .gap(14.0)
                .align(Center),
            )));
            let r = Rectangle::new().width(inner).height(38.0).child(Stack::new(layers));
            nav.push(bx(w::clickable(r, &id, w::act(move || {
                Prefs::write().page = i;
            }))));
        }
    }
    if vis.is_empty() {
        nav.push(bx(Rectangle::new().width(inner).height(40.0).padding(Padding { top: 10.0, right: 0.0, bottom: 0.0, left: 14.0 }).child(w::tx(t, "Nothing found", t.fs - 1.0, t.p.dim))));
    }
    let nav_h = (h - 20.0 - 16.0 - 64.0 - 38.0 - 14.0).max(100.0);
    Rectangle::new()
        .width(SIDE)
        .height(h)
        .padding(Padding { top: 20.0, right: 16.0, bottom: 16.0, left: 16.0 })
        .child(Column::new(children![
            head,
            search,
            w::gap(14.0),
            ScrollArea::new("prefs-nav", Column::new(nav).gap(2.0)).width(inner).height(nav_h)
        ]))
}

// заголовок страницы; на подстранице — «Раздел › Подстраница», раздел кликабелен (назад)
pub fn header(t: &Tk, title: &str, crumb: &str, subtitle: &str, w: f32, back: impl Fn() + 'static) -> W {
    let big = t.fs + 13.0;
    let mut row: Vec<W> = Vec::new();
    let tt = w::tx(t, title, big, if crumb.is_empty() || w::hov("hdr-back") { t.p.fg } else { t.p.dim }).weight(Weight::Bold);
    if crumb.is_empty() {
        row.push(bx(tt));
    } else {
        row.push(bx(w::clickable(ui::wrap(tt), "hdr-back", w::act(back))));
        row.push(bx(w::raw(t, "›", big, t.p.dim)));
        row.push(bx(w::tx(t, crumb, big, t.p.fg).weight(Weight::Bold)));
    }
    let mut col: Vec<W> = vec![bx(Row::new(row).gap(12.0).align(Center))];
    if subtitle.is_empty() {
        col.push(bx(w::gap(10.0)));
    } else {
        col.push(bx(w::line(t, &t.t(subtitle), t.fs - 1.0, t.p.dim, w, false)));
        col.push(bx(w::gap(10.0)));
    }
    bx(Column::new(col).gap(6.0))
}

pub fn view() -> Window {
    let t = look::tk();
    let (ww, wh) = amane::window_size();
    let (ww, wh) = if ww <= 0.0 { (1100.0, 760.0) } else { (ww, wh) };
    let page = Prefs::read().page;
    let panel_w = (ww - SIDE - 10.0).max(300.0);
    let panel_h = (wh - 20.0).max(200.0);
    let content_w = panel_w - 72.0;
    pages::set_panel_h(panel_h);
    let body = pages::build(page, &t, content_w);
    let scroll_id = w::sid(&format!("prefs-page-{page}"));
    let col = Column::new(body).gap(6.0);
    let (_, ch) = w::wh(&col);
    let page_col = Rectangle::new()
        .width(panel_w)
        .height(ch + 56.0)
        .padding(Padding { top: 28.0, right: 36.0, bottom: 28.0, left: 36.0 })
        .child(col);
    let panel_fill = crate::theme::mix(t.panel, t.p.surface, 0.5);
    let panel = Rectangle::new()
        .width(panel_w)
        .height(panel_h)
        .radius(16.0)
        .fill(panel_fill)
        .border(1.0, t.p.surface_hi)
        .clip()
        .child(ScrollArea::new(scroll_id, page_col).width(panel_w).height(panel_h));
    Window::new()
        .title("Settings")
        .size(1100.0, 760.0)
        .resizable(true)
        .on_key(|k| {
            // выбор сочетания клавиш забирает клавиши себе
            if pages::binds::on_key(k) {
                return;
            }
            // экран устройства забирает клавиши себе
            if pages::phone::on_key(k) {
                return;
            }
            if k == Key::Escape {
                if !Prefs::get("dd").is_empty() {
                    Prefs::set("dd", "");
                } else {
                    close();
                }
            }
        })
        .child(
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .fill(t.panel)
                .child(Row::new(children![
                    sidebar(&t, wh),
                    Rectangle::new().width(panel_w + 10.0).height(wh).padding(Padding { top: 10.0, right: 10.0, bottom: 10.0, left: 0.0 }).child(panel)
                ])),
        )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn search_finds_pages_by_keywords_and_russian_names() {
        let v = visible("", false, false);
        assert!(v.contains(&0) && !v.contains(&17) && !v.contains(&6));
        assert!(visible("", false, true).contains(&17));
        assert_eq!(visible("hz", false, false), vec![1]);
        assert!(visible("звук", true, false).contains(&2));
        assert!(visible("zzzz", false, false).is_empty());
        assert_eq!(matching_links("printer", false), vec![6]);
    }

    #[test]
    fn nav_covers_all_regular_pages() {
        let mut all: Vec<usize> = NAV.iter().flat_map(|(_, i)| i.iter().copied()).collect();
        all.sort();
        let regular: Vec<usize> = (0..PAGES.len()).filter(|i| PAGES[*i].go.is_none()).collect();
        assert_eq!(all, regular);
    }
}
