// трей (StatusNotifierItem): значки в баре, сетка «в меню» с булавками, меню приложений (dbusmenu).
// D-Bus — через data/tray.py (python-dbus): ему видно, кто зарегистрировал значок

use std::collections::HashSet;
use std::io::{BufRead, BufReader, Write};
use std::process::{ChildStdin, Command, Stdio};
use std::sync::Mutex;
use std::time::Duration;

use amane::{Button, Center, Column, End, Image, Padding, Pointer, Rectangle, Row, Service, Stack, Start, Widget, children};

use crate::json::Json;
use crate::look::Tk;
use crate::popups::{self, Popups};
use crate::settings::{self, Settings};
use crate::ui::{self, BAR, POPUP};

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Item {
    pub key: String,
    pub id: String,
    pub title: String,
    pub status: String,
    pub icon: String,
    pub menu: String,
    pub only_menu: bool,
    pub tooltip: String,
}

#[derive(Default)]
pub struct Tray {
    pub items: Vec<Item>,
    // открытое меню: значок и дерево пунктов
    pub menu: Option<(String, Json)>,
}

static STDIN: Mutex<Option<ChildStdin>> = Mutex::new(None);
static EXPANDED: Mutex<Option<HashSet<i64>>> = Mutex::new(None);

fn send(cmd: &str, key: &str, extra: Vec<(&str, Json)>) {
    let mut o = vec![("cmd".to_string(), Json::Str(cmd.into())), ("key".to_string(), Json::Str(key.into()))];
    o.extend(extra.into_iter().map(|(k, v)| (k.to_string(), v)));
    let line = format!("{}\n", Json::Obj(o).pretty_with(0).replace('\n', ""));
    if let Some(s) = STDIN.lock().unwrap().as_mut() {
        let _ = s.write_all(line.as_bytes());
        let _ = s.flush();
    }
}

pub fn parse_item(j: &Json) -> Item {
    Item {
        key: j.get("key").str_or(""),
        id: j.get("id").str_or(""),
        title: j.get("title").str_or(""),
        status: j.get("status").str_or("Active"),
        icon: j.get("icon").str_or(""),
        menu: j.get("menu").str_or(""),
        only_menu: j.get("only_menu").bool_or(false),
        tooltip: j.get("tooltip").str_or(""),
    }
}

impl Service for Tray {
    fn new() -> Self {
        Tray::default()
    }

    fn listen() {
        let script = settings::home().join(".config/amane/data/tray.py");
        loop {
            let Ok(mut child) = Command::new("python3").arg("-u").arg(&script).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn() else {
                std::thread::sleep(Duration::from_secs(10));
                continue;
            };
            *STDIN.lock().unwrap() = child.stdin.take();
            let out = child.stdout.take().unwrap();
            for line in BufReader::new(out).lines() {
                let Ok(line) = line else { break };
                let Some(j) = Json::parse(&line) else { continue };
                if let Json::Arr(list) = j.get("items") {
                    let items: Vec<Item> = list.iter().map(parse_item).filter(|i| i.status != "Passive").collect();
                    if Tray::read().items != items {
                        Tray::write().items = items;
                    }
                } else if !j.get("menu").is_null() {
                    let m = j.get("menu");
                    Tray::write().menu = Some((m.get("key").str_or(""), m.get("layout").clone()));
                }
            }
            let _ = child.wait();
            *STDIN.lock().unwrap() = None;
            Tray::write().items.clear();
            std::thread::sleep(Duration::from_secs(3));
        }
    }
}

// короткое название: без HTML и переносов строк
pub fn label(i: &Item) -> String {
    let clean = |v: &str| -> String {
        let mut out = String::new();
        let mut tag = false;
        for c in v.chars() {
            match c {
                '<' => tag = true,
                '>' => tag = false,
                _ if !tag => out.push(c),
                _ => {}
            }
        }
        out.lines().map(str::trim).find(|l| !l.is_empty()).unwrap_or("").to_string()
    };
    [&i.title, &i.tooltip, &i.id].iter().map(|s| clean(s)).find(|s| !s.is_empty()).unwrap_or_default()
}

// известные приложения — глиф Nerd Font, остальные — родная иконка
pub fn glyph(i: &Item) -> Option<u32> {
    let key = format!("{} {}", i.id, i.title).to_lowercase();
    let table: [(&[&str], u32); 10] = [
        (&["steam"], 0xF04D3),
        (&["discord", "vesktop", "webcord", "legcord", "equibop"], 0xF066F),
        (&["telegram", "ayugram", "64gram", "kotatogram"], 0xF2C6),
        (&["throne", "nekoray", "nekobox", "v2ray", "hiddify", "clash", "amnezia", "vpn"], 0xF0565),
        (&["obs"], 0xF044A),
        (&["spotify"], 0xF04C7),
        (&["blueman", "bluetooth"], 0xF00AF),
        (&["udiskie"], 0xF0553),
        (&["keepass"], 0xF0306),
        (&["firefox", "zen", "chrom", "brave"], 0xF059F),
    ];
    table.iter().find(|(ws, _)| ws.iter().any(|w| key.contains(w))).map(|(_, g)| *g)
}

fn icon(t: &Tk, i: &Item, size: f32, hover: bool) -> Rectangle {
    let r = Rectangle::new().width(size).height(size).align_child(Center, Center);
    if let Some(g) = glyph(i) {
        return r.child(ui::icon(t, g, size + 1.0, if hover { t.p.muted } else { t.p.fg }));
    }
    let file = if i.icon.starts_with('/') { Some(std::path::PathBuf::from(&i.icon)) } else { crate::apps::icon_file(&i.icon) };
    match file {
        Some(p) => r.child(Rectangle::new().width(size).height(size).fill(Image::contain(p)).opacity(if hover { 1.0 } else { 0.85 })),
        None => r.child(ui::icon(t, 0xF0335, size, t.p.dim)),
    }
}

fn pinned() -> Vec<String> {
    Settings::read().raw.get("trayPinned").arr().iter().filter_map(|v| v.str().map(String::from)).collect()
}

fn set_pinned(id: &str, on: bool) {
    let mut l: Vec<String> = pinned().into_iter().filter(|x| x != id).collect();
    if on {
        l.push(id.to_string());
    }
    settings::save_key("trayPinned", Json::Arr(l.into_iter().map(Json::Str).collect()));
}

pub fn open_menu(key: &str, output: &str) {
    *EXPANDED.lock().unwrap() = Some(HashSet::new());
    Tray::write().menu = None;
    Popups::write().tray_key = key.to_string();
    if Popups::read().open != "tray" {
        popups::toggle_at("tray", output);
    }
    send("menu", key, vec![]);
}

fn click(i: &Item, b: Button, output: &str) {
    match b {
        Button::Middle => send("secondary", &i.key, vec![]),
        Button::Right => {
            if !i.menu.is_empty() {
                open_menu(&i.key, output)
            }
        }
        Button::Left => {
            if i.only_menu && !i.menu.is_empty() {
                open_menu(&i.key, output)
            } else {
                send("activate", &i.key, vec![])
            }
        }
    }
}

// группа трея в баре: все значки или закреплённые + кнопка сетки
pub fn bar_group(t: &Tk, output: &str) -> Option<Rectangle> {
    if !t.c.module("tray") {
        return None;
    }
    let items = Tray::read().items.clone();
    let menu_mode = t.c.tray_mode == "menu";
    let pins = pinned();
    let mut v: Vec<Box<dyn Widget>> = Vec::new();
    for i in items.iter().filter(|i| !menu_mode || pins.contains(&i.id)) {
        let id = format!("tray:{}", i.key);
        let hov = ui::hovered::<BAR>(&id);
        let (it, o, it2) = (i.clone(), output.to_string(), i.key.clone());
        let r = Rectangle::new()
            .width(t.icon + 6.0)
            .height(t.bar_h)
            .cursor(Pointer)
            .align_child(Center, Center)
            .on_click(move |b| click(&it, b, &o))
            .on_scroll(move |s| send("scroll", &it2, vec![("delta", Json::Num(if s.y < 0.0 { 120.0 } else { -120.0 }))]))
            .child(icon(t, i, t.icon, hov));
        v.push(Box::new(ui::track::<BAR>(r, id)));
    }
    if menu_mode {
        let o = output.to_string();
        let open = Popups::read().open == "trayBox";
        v.push(Box::new(crate::bar::bar_text(t, "trayBox", ui::glyph(0xF003B), t.icon, open || true, true).on_click(move |_| popups::toggle_at("trayBox", &o))));
    }
    crate::bar::group(t, v, 10.0)
}

// ── сетка трея (TrayBox.qml)
pub fn box_view(t: &Tk) -> Column {
    let items = Tray::read().items.clone();
    let cols = items.len().clamp(1, 4);
    let w = (cols as f32 * 84.0 + (cols as f32 - 1.0) * 4.0).max(300.0);
    let n = items.len();
    let sub = if n == 0 { t.t("No apps in the tray") } else { format!("{n} {}", crate::i18n::plural(t.c.ru(), n as i64, "app", "apps", "приложение", "приложения", "приложений")) };
    let pins = pinned();
    let output = Popups::read().output.clone();
    let mut tiles: Vec<Box<dyn Widget>> = Vec::new();
    for i in &items {
        let id = format!("tbox:{}", i.key);
        let hov = ui::hovered::<POPUP>(&id);
        let pin_id = format!("tpin:{}", i.key);
        let ph = ui::hovered::<POPUP>(&pin_id);
        let is_pinned = pins.contains(&i.id);
        let mut layers: Vec<Box<dyn Widget>> = vec![
            Box::new(Rectangle::new().width(84.0).height(76.0).padding(Padding { top: 14.0, right: 0.0, bottom: 0.0, left: 0.0 }).align_child(Center, Start).child(icon(t, i, 22.0, hov))),
            Box::new(Rectangle::new().width(84.0).height(76.0).padding(Padding { top: 0.0, right: 6.0, bottom: 8.0, left: 6.0 }).align_child(Center, End).child(crate::prefs::w::line(t, &t.t(&label(i)), t.fs - 2.0, if hov { t.p.fg } else { t.p.muted }, 72.0, false))),
        ];
        if is_pinned || hov || ph {
            let (pid, on) = (i.id.clone(), is_pinned);
            let pin = Rectangle::new()
                .width(20.0)
                .height(20.0)
                .cursor(Pointer)
                .align_child(Center, Center)
                .on_click(move |_| set_pinned(&pid, !on))
                .child(ui::icon(t, if is_pinned { 0xF0403 } else { 0xF0931 }, t.icon - 2.0, if ph { t.p.fg } else if is_pinned { t.p.accent } else { t.p.dim }));
            layers.push(Box::new(Rectangle::new().width(84.0).height(76.0).padding(3.0).align_child(End, Start).child(ui::track::<POPUP>(pin, pin_id))));
        }
        let (it, o) = (i.clone(), output.clone());
        let r = Rectangle::new()
            .width(84.0)
            .height(76.0)
            .radius(10.0)
            .clip()
            .fill(if hov { t.p.surface_hi } else { t.p.surface })
            .cursor(Pointer)
            .on_click(move |b| {
                click(&it, b, &o);
                if b == Button::Left && !it.only_menu {
                    popups::close();
                }
            })
            .child(Stack::new(layers));
        tiles.push(Box::new(ui::track::<POPUP>(r, id)));
    }
    let mut rows: Vec<Box<dyn Widget>> = Vec::new();
    let mut it = tiles.into_iter().peekable();
    while it.peek().is_some() {
        rows.push(Box::new(Row::new(it.by_ref().take(cols).collect::<Vec<_>>()).gap(4.0)));
    }
    Column::new(children![
        ui::menu_header::<POPUP>(t, w, 0xF003B, "Tray", &sub, "bar"),
        Column::new(rows).gap(4.0),
        crate::prefs::w::para(t, &t.t("Right-click — app menu. Pin — keep the icon in the bar."), t.fs - 2.0, t.p.dim, w)
    ])
    .gap(10.0)
}

// ── меню приложения (TrayMenu.qml): подменю раскрываются внутри
fn strip_mnemonic(s: &str) -> String {
    let mut out = String::new();
    let mut ch = s.chars().peekable();
    while let Some(c) = ch.next() {
        if c == '_' {
            if ch.peek() == Some(&'_') {
                out.push('_');
                ch.next();
            }
            continue;
        }
        out.push(c);
    }
    out
}

fn menu_rows(t: &Tk, key: &str, node: &Json, depth: usize, w: f32, out: &mut Vec<Box<dyn Widget>>) {
    let expanded = EXPANDED.lock().unwrap().clone().unwrap_or_default();
    for c in node.get("children").arr() {
        if !c.get("visible").bool_or(true) {
            continue;
        }
        let iw = w - depth as f32 * 12.0;
        let pad = Padding { top: 0.0, right: 0.0, bottom: 0.0, left: depth as f32 * 12.0 };
        if c.get("type").str() == Some("separator") {
            out.push(Box::new(Rectangle::new().width(w).height(9.0).padding(Padding { top: 4.0, right: 0.0, bottom: 4.0, left: pad.left }).child(Rectangle::new().width(iw).height(1.0).fill(t.p.faint))));
            continue;
        }
        let mid = c.get("id").num_or(0.0) as i64;
        let enabled = c.get("enabled").bool_or(true);
        let has_children = !c.get("children").arr().is_empty();
        let open = expanded.contains(&mid);
        let id = format!("tmenu:{mid}");
        let hov = ui::hovered::<POPUP>(&id) && enabled;
        let mut row: Vec<Box<dyn Widget>> = Vec::new();
        let toggle = c.get("toggle").str_or("");
        let mut used = 16.0;
        if !toggle.is_empty() {
            let on = c.get("state").num_or(-1.0) as i64 == 1;
            let g = if toggle == "radio" { if on { 0xF043E } else { 0xF043D } } else if on { 0xF0132 } else { 0xF0131 };
            row.push(Box::new(ui::icon(t, g, t.fs, if on { t.p.fg } else { t.p.dim })));
            used += t.fs + 8.0;
        }
        let ic = c.get("icon").str_or("");
        if let Some(p) = crate::apps::icon_file(&ic) {
            row.push(Box::new(Rectangle::new().width(t.icon).height(t.icon).fill(Image::contain(p))));
            used += t.icon + 8.0;
        }
        if has_children {
            used += 18.0;
        }
        row.push(Box::new(crate::prefs::w::line(t, &t.t(&strip_mnemonic(&c.get("label").str_or(""))), t.fs, if enabled { t.p.fg } else { t.p.dim }, iw - used, false)));
        if has_children {
            row.push(Box::new(ui::text(t, if open { "⌄" } else { "›" }, t.p.dim)));
        }
        let k = key.to_string();
        let r = Rectangle::new()
            .width(iw)
            .height(28.0)
            .radius(6.0)
            .fill(if hov { t.p.faint } else { amane::Color::TRANSPARENT })
            .padding(Padding { top: 0.0, right: 8.0, bottom: 0.0, left: 8.0 })
            .cursor(Pointer)
            .on_click(move |_| {
                if !enabled {
                    return;
                }
                if has_children {
                    let mut e = EXPANDED.lock().unwrap();
                    let set = e.get_or_insert_with(HashSet::new);
                    if !set.remove(&mid) {
                        set.insert(mid);
                    }
                    drop(e);
                    // перерисовать: меняем «открытое меню» на то же
                    let m = Tray::read().menu.clone();
                    Tray::write().menu = m;
                } else {
                    send("event", &k, vec![("id", Json::Num(mid as f64))]);
                    popups::close();
                }
            })
            .child(Row::new(row).gap(8.0).height(28.0).align(Center));
        out.push(Box::new(Rectangle::new().width(w).height(28.0).padding(pad).child(ui::track::<POPUP>(r, id))));
        if has_children && open {
            menu_rows(t, key, c, depth + 1, w, out);
        }
    }
}

pub fn menu_view(t: &Tk) -> Column {
    let w = 300.0;
    let key = Popups::read().tray_key.clone();
    let tr = Tray::read();
    let item = tr.items.iter().find(|i| i.key == key).cloned();
    let menu = tr.menu.clone().filter(|(k, _)| *k == key).map(|(_, m)| m);
    drop(tr);
    let title = item.as_ref().map(|i| if i.tooltip.is_empty() { label(i) } else { i.tooltip.lines().next().unwrap_or("").to_string() }).unwrap_or_default();
    let mut col: Vec<Box<dyn Widget>> = Vec::new();
    if !title.is_empty() {
        col.push(Box::new(Rectangle::new().width(w).height(44.0).child(ui::menu_header::<POPUP>(t, w, 0xF0DCA, &title, "App menu", ""))));
    }
    let mut rows: Vec<Box<dyn Widget>> = Vec::new();
    match menu {
        Some(m) => menu_rows(t, &key, &m, 0, w, &mut rows),
        None => rows.push(Box::new(Rectangle::new().width(w).height(28.0).align_child(Center, Center).child(ui::text(t, "…", t.p.dim)))),
    }
    col.push(Box::new(Column::new(rows)));
    Column::new(col).gap(6.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn labels_and_glyphs() {
        let i = Item { id: "chrome_status_icon_1".into(), title: "".into(), tooltip: "<b>Throne</b>\n[Tun]".into(), ..Default::default() };
        assert_eq!(label(&i), "Throne");
        assert_eq!(glyph(&Item { id: "TelegramDesktop".into(), ..Default::default() }), Some(0xF2C6));
        assert_eq!(glyph(&Item { id: "nm-applet".into(), ..Default::default() }), None);
        assert_eq!(strip_mnemonic("_Open__File"), "Open_File");
    }
}
