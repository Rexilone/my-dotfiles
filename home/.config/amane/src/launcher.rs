// меню приложений (Super+D) — как Launcher.qml: строка поиска с закреплёнными, ниже результаты по группам

use std::collections::HashMap;
use std::fs;
use std::time::{Duration, Instant};

use amane::{
    Animation, Apps, Button, Center, Color, Column, Full, Image, Key, Keyboard, Layer, LayerWindow, Padding, Parent,
    Rectangle, Row, Service, Stack, Start, Weight, Widget, Zone,
};

use crate::apps::{self, AppList, Entry};
use crate::json::Json;
use crate::look;
use crate::search::{self, Item, Kind, Query};
use crate::ui::{self, LAUNCHER, ic};

const ROW_H: f32 = 46.0;
const HEAD_H: f32 = 26.0;
const MAX_ROWS: f32 = 8.0;
const WIDTH: f32 = 660.0;
const BAR_H: f32 = 58.0;

pub struct Launcher {
    pub open: bool,
    pub output: String,
    pub query: String,
    pub sel: usize,
    pub browsing: bool,
    pub actions_for: Option<usize>,
    pub scroll: f32,
    // выбор мышью — только после настоящего движения (не реагировать на курсор при открытии)
    pub armed: bool,
    pub last_mouse: Option<(f32, f32)>,
    pub toast: String,
    pub toast_until: Option<Instant>,
    pub anim: Animation,
    pub usage: Usage,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Usage {
    pub counts: HashMap<String, i64>,
    pub pinned: Vec<String>,
}

// частота и закреплённые — в том же файле, что у Quickshell
fn usage_path() -> std::path::PathBuf {
    crate::settings::path().with_file_name("launcher.json")
}

pub fn parse_usage(j: &Json) -> Usage {
    Usage {
        counts: j.get("counts").obj().iter().filter_map(|(k, v)| v.num().map(|n| (k.clone(), n as i64))).collect(),
        pinned: j.get("pinned").arr().iter().filter_map(|v| v.str().map(String::from)).collect(),
    }
}

fn load_usage() -> Usage {
    fs::read_to_string(usage_path()).ok().and_then(|t| Json::parse(&t)).map(|j| parse_usage(&j)).unwrap_or_default()
}

fn save_usage(u: &Usage) {
    let mut counts: Vec<(&String, &i64)> = u.counts.iter().collect();
    counts.sort();
    let j = Json::Obj(vec![
        ("counts".into(), Json::Obj(counts.into_iter().map(|(k, v)| (k.clone(), Json::Num(*v as f64))).collect())),
        ("pinned".into(), Json::Arr(u.pinned.iter().map(|p| Json::Str(p.clone())).collect())),
    ]);
    let _ = fs::write(usage_path(), j.pretty());
}

impl Service for Launcher {
    fn new() -> Self {
        Launcher {
            open: false,
            output: String::new(),
            query: String::new(),
            sel: 0,
            browsing: false,
            actions_for: None,
            scroll: 0.0,
            armed: false,
            last_mouse: None,
            toast: String::new(),
            toast_until: None,
            anim: crate::look::anim(0.0, 220),
            usage: load_usage(),
        }
    }

    fn interval() -> Duration {
        Duration::from_millis(300)
    }

    // подсказка («Скопировано») гаснет сама
    fn update(&mut self) -> bool {
        if self.toast_until.is_some_and(|t| Instant::now() >= t) {
            self.toast.clear();
            self.toast_until = None;
            return true;
        }
        false
    }
}

pub fn toggle(_: &[String]) -> String {
    let open = !Launcher::read().open;
    set_open(open);
    String::from(if open { "opened" } else { "closed" })
}

pub fn ipc(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("open") => set_open(true),
        Some("hide") | Some("close") => set_open(false),
        _ => return toggle(args),
    }
    String::from("ok")
}

pub fn set_open(open: bool) {
    let mut l = Launcher::write();
    if open == l.open {
        return;
    }
    l.open = open;
    if open {
        l.output = crate::focus_output();
        l.query.clear();
        l.sel = 0;
        l.browsing = false;
        l.actions_for = None;
        l.scroll = 0.0;
        l.armed = false;
        l.last_mouse = None;
        l.toast.clear();
        l.usage = load_usage();
        l.anim = crate::look::anim(0.0, 220);
        // появление — после первого кадра (look::appear)
    } else {
        crate::look::go(&mut l.anim, 0.0);
    }
    drop(l);
    if open {
        crate::popups::close();
    }
}

fn current_items(l: &Launcher, list: &[Entry], ru: bool) -> Vec<Item> {
    let expanded = !l.query.trim().is_empty() || l.browsing || l.actions_for.is_some();
    if !expanded {
        return Vec::new();
    }
    search::items(&Query { text: &l.query, apps: list, counts: &l.usage.counts, actions_for: l.actions_for, ru })
}

// высота строки с подписью группы (подпись — у первой строки каждой группы, кроме самой первой)
fn row_heights(items: &[Item]) -> Vec<f32> {
    items
        .iter()
        .enumerate()
        .map(|(i, it)| if i > 0 && items[i - 1].group != it.group { ROW_H + HEAD_H } else { ROW_H })
        .collect()
}

// прокрутка, чтобы выбранная строка была видна
pub fn keep_visible(heights: &[f32], sel: usize, scroll: f32, view: f32) -> f32 {
    let top: f32 = heights[..sel.min(heights.len())].iter().sum();
    let h = heights.get(sel).copied().unwrap_or(ROW_H);
    let total: f32 = heights.iter().sum();
    let mut s = scroll;
    if top < s {
        s = top;
    }
    if top + h > s + view {
        s = top + h - view;
    }
    s.clamp(0.0, (total - view).max(0.0))
}

fn view_height(heights: &[f32]) -> f32 {
    let total: f32 = heights.iter().sum();
    total.min(MAX_ROWS * ROW_H + 60.0)
}

fn move_sel(delta: i64) {
    let ru = crate::settings::Settings::read().c.ru();
    let apps = AppList::read();
    let mut l = Launcher::write();
    l.armed = false;
    let items = current_items(&l, &apps.list, ru);
    if items.is_empty() {
        return;
    }
    let n = items.len() as i64;
    // без зацикливания: на краю выбор стоит (иначе «вниз» возвращает наверх)
    l.sel = (l.sel as i64 + delta).clamp(0, n - 1) as usize;
    let hs = row_heights(&items);
    let view = view_height(&hs);
    l.scroll = keep_visible(&hs, l.sel, l.scroll, view);
}

fn set_query(f: impl FnOnce(&mut String)) {
    let mut l = Launcher::write();
    f(&mut l.query);
    if l.query.is_empty() {
        l.browsing = false;
    }
    l.sel = 0;
    l.scroll = 0.0;
}

// → — действия выбранного приложения, ← — назад
fn show_actions() {
    let ru = crate::settings::Settings::read().c.ru();
    let apps = AppList::read();
    let l = Launcher::read();
    let expanded = !l.query.trim().is_empty() || l.browsing || l.actions_for.is_some();
    let it = current_items(&l, &apps.list, ru).get(l.sel).cloned();
    let has = |i: usize| apps.list.get(i).is_some_and(|e| !e.actions.is_empty());
    let target = match it.map(|i| i.kind) {
        Some(Kind::App(i)) if expanded && l.actions_for.is_none() && has(i) => Some(i),
        _ => None,
    };
    drop((l, apps));
    if let Some(i) = target {
        let mut l = Launcher::write();
        l.actions_for = Some(i);
        l.sel = 0;
        l.scroll = 0.0;
    }
}

fn on_key(k: Key) {
    match k {
        Key::Character(c) => return set_query(|q| q.push(c)),
        Key::Space => return set_query(|q| q.push(' ')),
        Key::Backspace => {
            // пусто и открыты действия — назад к списку
            let back = Launcher::read().query.is_empty() && Launcher::read().actions_for.is_some();
            if back {
                let mut l = Launcher::write();
                l.actions_for = None;
                l.sel = 0;
            } else {
                set_query(|q| {
                    q.pop();
                });
            }
            return;
        }
        Key::Enter => return submit(),
        Key::Right => return show_actions(),
        Key::Left => {
            let mut l = Launcher::write();
            if l.actions_for.is_some() {
                l.actions_for = None;
                l.sel = 0;
                l.scroll = 0.0;
            }
            return;
        }
        _ => {}
    }
    let expanded = {
        let l = Launcher::read();
        !l.query.trim().is_empty() || l.browsing || l.actions_for.is_some()
    };
    match k {
        Key::Escape => {
            let mut l = Launcher::write();
            if l.actions_for.is_some() {
                l.actions_for = None;
                l.sel = 0;
            } else if l.browsing && l.query.is_empty() {
                l.browsing = false;
            } else {
                drop(l);
                set_open(false);
            }
        }
        Key::Down | Key::Tab if !expanded => {
            let mut l = Launcher::write();
            l.browsing = true;
            l.sel = 0;
            l.scroll = 0.0;
        }
        Key::Down | Key::Tab => move_sel(1),
        Key::Up => {
            let back = {
                let l = Launcher::read();
                l.browsing && l.query.is_empty() && l.sel == 0 && l.actions_for.is_none()
            };
            if back {
                Launcher::write().browsing = false;
            } else {
                move_sel(-1);
            }
        }
        _ => {}
    }
}

fn submit() {
    let ru = crate::settings::Settings::read().c.ru();
    let apps = AppList::read();
    let l = Launcher::read();
    let expanded = !l.query.trim().is_empty() || l.browsing || l.actions_for.is_some();
    let items = current_items(&l, &apps.list, ru);
    let first_pin = l.usage.pinned.first().and_then(|id| apps.list.iter().position(|e| &e.id == id));
    let it = items.get(l.sel).cloned();
    drop((l, apps));
    if expanded {
        if let Some(it) = it {
            run(&it);
        }
    } else if let Some(p) = first_pin {
        launch_app(p, None);
    }
}

fn bump(id: &str) {
    let mut l = Launcher::write();
    *l.usage.counts.entry(id.to_string()).or_insert(0) += 1;
    save_usage(&l.usage);
}

fn launch_app(i: usize, action: Option<usize>) {
    let apps = AppList::read();
    let Some(e) = apps.list.get(i) else { return };
    let exec = action.and_then(|a| e.actions.get(a)).map(|a| a.exec.clone()).unwrap_or_else(|| e.exec.clone());
    amane::spawn(&apps::launch_cmd(e, &exec));
    let id = e.id.clone();
    drop(apps);
    bump(&id);
    set_open(false);
}

fn flash(text: String) {
    let mut l = Launcher::write();
    l.toast = text;
    l.toast_until = Some(Instant::now() + Duration::from_millis(1800));
}

fn run(it: &Item) {
    let ru = crate::settings::Settings::read().c.ru();
    match &it.kind {
        Kind::App(i) => launch_app(*i, None),
        Kind::Action(i, a) => launch_app(*i, Some(*a)),
        Kind::Calc(v) => {
            amane::spawn(&format!("wl-copy {}", crate::niri::sh_quote(v)));
            flash(format!("{} {v}", if ru { "Скопировано" } else { "Copied" }));
        }
        Kind::Run(cmd) => {
            if !cmd.is_empty() {
                amane::spawn(&format!("setsid -f foot --hold sh -c {} >/dev/null 2>&1", crate::niri::sh_quote(cmd)));
                set_open(false);
            }
        }
        Kind::Web(text) => {
            if !text.is_empty() {
                amane::spawn(&format!("xdg-open {}", crate::niri::sh_quote(&format!("https://www.google.com/search?q={}", search::url_encode(text)))));
                set_open(false);
            }
        }
        Kind::System(i) => {
            set_open(false);
            let cmd = search::SYSTEM[*i].cmd;
            match cmd {
                "amane ipc call notifications dnd" => crate::notifs::toggle_dnd(),
                "amane ipc call theme toggle" => crate::popups::toggle_dark(),
                "amane ipc call power toggle" => {
                    crate::power::toggle(&[]);
                }
                "amane ipc call wallpaper toggle" => {
                    crate::wallpaper::toggle(&[]);
                }
                "amane ipc call clipboard toggle" => {
                    crate::clipboard::toggle(&[]);
                }
                _ => amane::spawn(&format!("sleep 0.25; {cmd}")),
            }
        }
    }
}

fn toggle_pin(id: &str, name: &str) {
    let ru = crate::settings::Settings::read().c.ru();
    let mut l = Launcher::write();
    let was = l.usage.pinned.iter().position(|p| p == id);
    match was {
        Some(i) => {
            l.usage.pinned.remove(i);
        }
        None => l.usage.pinned.push(id.to_string()),
    }
    save_usage(&l.usage);
    drop(l);
    flash(match (was.is_some(), ru) {
        (true, true) => format!("Откреплено: {name}"),
        (false, true) => format!("Закреплено: {name}"),
        (true, false) => format!("Unpinned {name}"),
        (false, false) => format!("Pinned {name}"),
    });
}

// значок приложения: из темы (через список amane) или по имени
fn app_icon(e: &Entry, size: f32) -> Rectangle {
    let r = Rectangle::new().width(size).height(size);
    let path = if e.icon.starts_with('/') {
        Some(std::path::PathBuf::from(&e.icon))
    } else {
        let themed = Apps::read()
            .list()
            .iter()
            .find(|a| a.icon() == Some(e.icon.as_str()))
            .and_then(|a| a.icon_path().map(|p| p.to_path_buf()));
        themed.or_else(|| crate::icons::resolve(&e.icon))
    };
    match path {
        Some(p) => r.fill(Image::contain(p)),
        None => r,
    }
}

pub fn view(m: &amane::Monitor) -> LayerWindow {
    let t = look::tk();
    let l = Launcher::read();
    let apps = AppList::read();
    let here = l.output == m.name;
    let k = if here { l.anim.value() } else { 0.0 };
    let open = l.open && here;
    look::appear("launcher", open, || {
        let mut x = Launcher::write();
        if x.open {
            look::go(&mut x.anim, 1.0);
        }
    });
    let items = current_items(&l, &apps.list, t.c.ru());
    let expanded = !l.query.trim().is_empty() || l.browsing || l.actions_for.is_some();

    // ── строка поиска
    let q = l.query.trim();
    let lead_icon = if l.actions_for.is_some() {
        0xF0241
    } else if q.starts_with('>') {
        0xF018D
    } else if q.starts_with('?') {
        0xF059F
    } else {
        ic::SEARCH
    };
    let mut bar: Vec<Box<dyn Widget>> = vec![
        Box::new(ui::spacer(6.0, 1.0)),
        Box::new(ui::icon(&t, lead_icon, t.icon + 4.0, if l.query.is_empty() && l.actions_for.is_none() { t.p.dim } else { t.p.fg })),
    ];
    if let Some(a) = l.actions_for.and_then(|a| apps.list.get(a)) {
        bar.push(Box::new(ui::text(&t, format!("{}  ›", a.name), t.p.muted).size(t.fs + 3.0)));
    }
    let pins: Vec<(usize, &Entry)> = l
        .usage
        .pinned
        .iter()
        .filter_map(|id| apps.list.iter().position(|e| &e.id == id).map(|i| (i, &apps.list[i])))
        .take(6)
        .collect();
    let pins_w = if !expanded && !pins.is_empty() { pins.len() as f32 * 40.0 } else { 20.0 };
    let input_w = WIDTH - 6.0 - (t.icon + 4.0) - 12.0 * 3.0 - pins_w - 6.0;
    bar.push(Box::new(
        Rectangle::new().width(input_w).height(BAR_H).align_child(Start, Center).child(
            // своё поле ввода: курсор всегда в конце, а стрелки ←/→ достаются меню (действия приложения)
            {
                let shown = if l.query.is_empty() { t.tr("Type to search…", "Начните вводить…").to_string() } else { l.query.clone() };
                let txt = ui::text(&t, shown, if l.query.is_empty() { t.p.dim } else { t.p.fg }).size(t.fs + 4.0);
                let (tw, _) = ui::size_of(&txt);
                let caret = Rectangle::new().width(2.0).height(t.fs + 8.0).radius(1.0).fill(t.p.accent);
                let caret_x = if l.query.is_empty() { 0.0 } else { tw.min(input_w - 4.0) + 1.0 };
                Stack::new(amane::children![
                    Rectangle::new().width(input_w).height(BAR_H).align_child(Start, Center).clip().child(txt),
                    Rectangle::new().width(input_w).height(BAR_H).align_child(Start, Center).child(caret.translate(caret_x, 0.0))
                ])
            },
        ),
    ));
    if !expanded && !pins.is_empty() {
        let mut row: Vec<Box<dyn Widget>> = Vec::new();
        for (i, e) in &pins {
            let id = format!("pin:{}", e.id);
            let hov = ui::hovered::<LAUNCHER>(&id);
            let (i, eid, name) = (*i, e.id.clone(), e.name.clone());
            let r = Rectangle::new()
                .width(38.0)
                .height(38.0)
                .radius(10.0)
                .fill(if hov { t.p.surface_hi2 } else { Color::TRANSPARENT })
                .align_child(Center, Center)
                .child(app_icon(e, 24.0))
                .cursor(amane::Pointer)
                .on_click(move |b| if b == Button::Right { toggle_pin(&eid, &name) } else { launch_app(i, None) });
            row.push(Box::new(ui::track::<LAUNCHER>(r, id)));
        }
        bar.push(Box::new(Row::new(row).gap(2.0)));
    } else if !expanded {
        bar.push(Box::new(ui::text(&t, "↓", t.p.faint)));
    }
    let bar = Row::new(bar).gap(12.0).height(BAR_H).align(Center);

    // ── результаты
    let hs = row_heights(&items);
    let view_h = if items.is_empty() { 50.0 } else { view_height(&hs) };
    let results_h = view_h + 18.0;
    let mut rows: Vec<Box<dyn Widget>> = Vec::new();
    for (i, it) in items.iter().enumerate() {
        let cur = i == l.sel;
        let mut parts: Vec<Box<dyn Widget>> = Vec::new();
        if hs[i] > ROW_H {
            parts.push(Box::new(
                Rectangle::new()
                    .width(WIDTH - 16.0)
                    .height(HEAD_H)
                    .padding(Padding { top: 7.0, right: 0.0, bottom: 0.0, left: 14.0 })
                    .child(ui::bold(&t, search::group_name(it.group, t.c.ru()), t.p.faint).size(t.fs - 3.0)),
            ));
        }
        let icon: Box<dyn Widget> = match &it.kind {
            Kind::App(a) | Kind::Action(a, _) => Box::new(app_icon(&apps.list[*a], 24.0)),
            _ => Box::new(ui::icon(&t, it.glyph, t.icon + 2.0, if cur { t.p.fg } else { t.p.muted })),
        };
        let is_calc = matches!(it.kind, Kind::Calc(_));
        let label = ui::text(&t, it.label.clone(), if cur { t.p.fg } else { t.p.muted }).size(if is_calc { t.fs + 4.0 } else { t.fs + 1.0 });
        let label = if is_calc { label.weight(Weight::Bold) } else { label };
        let lw = crate::bar::width_of(&label).min(330.0);
        let has_actions = matches!(it.kind, Kind::App(a) if !apps.list[a].actions.is_empty());
        let pinned = matches!(&it.kind, Kind::App(a) if l.usage.pinned.contains(&apps.list[*a].id));
        let hint = if cur { if has_actions && l.actions_for.is_none() { "→  ↵" } else { "↵" } } else { "" };
        let hint_t = ui::text(&t, hint, t.p.dim).size(t.fs - 1.0);
        let hint_w = crate::bar::width_of(&hint_t);
        let pin_w = if pinned { t.icon } else { 0.0 };
        let sub_w = (WIDTH - 16.0 - 4.0 - 26.0 - lw - pin_w - hint_w - 6.0 - 12.0 * 5.0).max(0.0);
        let mut line: Vec<Box<dyn Widget>> = vec![
            Box::new(ui::spacer(4.0, 1.0)),
            Box::new(Rectangle::new().width(26.0).height(26.0).align_child(Center, Center).child(Column::new(vec![icon]))),
            Box::new(Rectangle::new().width(lw).height(ROW_H).align_child(Start, Center).clip().child(label.elide())),
            Box::new(Rectangle::new().width(sub_w).height(ROW_H).align_child(Start, Center).clip().child(ui::text(&t, it.sub.clone(), t.p.dim).size(t.fs - 2.0).elide())),
        ];
        if pinned {
            line.push(Box::new(ui::icon(&t, 0xF0403, t.icon - 3.0, t.p.faint)));
        }
        line.push(Box::new(hint_t));
        // действия приложения — стрелка мышью или →
        if has_actions && l.actions_for.is_none() {
            if let Kind::App(a) = it.kind {
                let aid = format!("act:{a}");
                let hov = ui::hovered::<LAUNCHER>(&aid);
                let b = Rectangle::new().width(26.0).height(26.0).radius(8.0).fill(if hov { t.p.surface_hi2 } else { Color::TRANSPARENT }).align_child(Center, Center).child(ui::icon(&t, 0xF0142, t.icon, t.p.dim));
                let b = ui::on_left(ui::track::<LAUNCHER>(b, aid), move || {
                    let mut l = Launcher::write();
                    l.actions_for = Some(a);
                    l.sel = 0;
                    l.scroll = 0.0;
                });
                line.push(Box::new(b));
            }
        }
        let it2 = it.clone();
        let entry = match &it.kind {
            Kind::App(a) => Some((apps.list[*a].id.clone(), apps.list[*a].name.clone())),
            _ => None,
        };
        let row = Rectangle::new()
            .width(WIDTH - 16.0)
            .height(ROW_H)
            .radius(10.0)
            .fill(if cur { t.p.surface_hi } else { Color::TRANSPARENT })
            .cursor(amane::Pointer)
            .on_click(move |b| {
                if b == Button::Right {
                    if let Some((id, name)) = &entry {
                        toggle_pin(id, name);
                    }
                } else {
                    run(&it2);
                }
            })
            .child(Row::new(line).gap(12.0).height(ROW_H).align(Center));
        parts.push(Box::new(row));
        rows.push(Box::new(Column::new(parts)));
    }
    let scroll = l.scroll;
    let total: f32 = hs.iter().sum();
    let starts: Vec<f32> = hs.iter().scan(0.0, |acc, h| {
        let s = *acc;
        *acc += h;
        Some(s)
    }).collect();
    let results: Box<dyn Widget> = if items.is_empty() {
        Box::new(
            Rectangle::new().width(WIDTH).height(results_h).align_child(Center, Center).child(ui::text(
                &t,
                if l.actions_for.is_some() { t.tr("No actions", "Нет действий") } else { t.tr("Nothing found", "Ничего не найдено") },
                t.p.dim,
            )),
        )
    } else {
        let hs2 = hs.clone();
        Box::new(
            Rectangle::new()
                .width(WIDTH)
                .height(results_h)
                .padding(Padding { top: 9.0, right: 8.0, bottom: 9.0, left: 8.0 })
                .child(
                    Rectangle::new()
                        .width(WIDTH - 16.0)
                        .height(view_h)
                        .clip()
                        .on_scroll(move |s| {
                            let mut l = Launcher::write();
                            l.scroll = (l.scroll + s.y * 40.0).clamp(0.0, (total - view_h).max(0.0));
                        })
                        // выбор под мышью — только когда её правда двигали
                        .on_move(move |p| {
                            let mut l = Launcher::read().last_mouse;
                            let moved = l.is_some_and(|(x, y)| ((p.x - x).powi(2) + (p.y - y).powi(2)).sqrt() > 2.0);
                            l = Some((p.x, p.y));
                            let cur = Launcher::read();
                            let armed = cur.armed || moved;
                            let y = p.y + cur.scroll;
                            let idx = starts.iter().rposition(|s| *s <= y).unwrap_or(0);
                            let in_head = hs2.get(idx).is_some_and(|h| *h > ROW_H && y - starts[idx] < HEAD_H);
                            let sel = cur.sel;
                            drop(cur);
                            let mut w = Launcher::write();
                            w.last_mouse = l;
                            w.armed = armed;
                            if armed && !in_head && idx != sel {
                                w.sel = idx;
                            }
                        })
                        .child(Rectangle::new().width(WIDTH - 16.0).height(total).translate(0.0, -scroll).child(Column::new(rows))),
                ),
        )
    };
    let card_h = BAR_H + if expanded { results_h } else { 0.0 };
    let mut card_parts: Vec<Box<dyn Widget>> = vec![Box::new(Rectangle::new().width(WIDTH).height(BAR_H).child(bar))];
    if expanded {
        card_parts.push(Box::new(Rectangle::new().width(WIDTH).height(1.0).fill(t.p.surface_hi2)));
        card_parts.push(results);
    }
    let toast = l.toast.clone();
    drop((l, apps));
    let mut layers: Vec<Box<dyn Widget>> = vec![Box::new(Column::new(card_parts))];
    if !toast.is_empty() {
        let tt = ui::text(&t, toast, t.p.fg).size(t.fs - 2.0);
        let w = crate::bar::width_of(&tt) + 20.0;
        layers.push(Box::new(
            Rectangle::new().width(WIDTH).height(BAR_H).align_child(amane::End, Center).padding(Padding { top: 0.0, right: 14.0, bottom: 0.0, left: 0.0 }).child(
                Rectangle::new().width(w).height(28.0).radius(8.0).fill(t.p.surface_hi2).align_child(Center, Center).child(tt),
            ),
        ));
    }
    let card = Rectangle::new()
        .width(WIDTH)
        .height(card_h)
        .radius(16.0)
        .fill(t.panel)
        .border(1.0, t.p.surface_hi2)
        .clip()
        .opacity(k)
        .scale(0.97 + 0.03 * k)
        .on_click(|_| {})
        .child(Stack::new(layers));

    let (_, sh) = amane::window_size();
    let top = (sh * 0.24).round();
    LayerWindow::new()
        .width(Full)
        .height(Full)
        .layer(Layer::Overlay)
        .space(Zone::Ignore)
        .namespace("rexilone-launcher")
        .keyboard(if open { Keyboard::Exclusive } else { Keyboard::None })
        .on_key(on_key)
        .visible(open || k > 0.01)
        .child(
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .fill(Color::rgba(0, 0, 0, (0.35 * k * 255.0) as u8))
                .padding(Padding { top, right: 0.0, bottom: 0.0, left: 0.0 })
                .align_child(Center, Start)
                .on_click(|_| set_open(false))
                .child(card),
        )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn it(group: &'static str) -> Item {
        Item { kind: Kind::Web(String::new()), group, label: String::new(), sub: String::new(), glyph: 0 }
    }

    #[test]
    fn group_headers_add_height() {
        let items = vec![it("Frequent"), it("Frequent"), it("All apps"), it("All apps")];
        assert_eq!(row_heights(&items), vec![ROW_H, ROW_H, ROW_H + HEAD_H, ROW_H]);
    }

    #[test]
    fn selection_stays_visible() {
        let hs = vec![ROW_H; 20];
        let view = 8.0 * ROW_H;
        assert_eq!(keep_visible(&hs, 0, 0.0, view), 0.0);
        assert_eq!(keep_visible(&hs, 7, 0.0, view), 0.0);
        assert_eq!(keep_visible(&hs, 8, 0.0, view), ROW_H);
        assert_eq!(keep_visible(&hs, 19, 0.0, view), 12.0 * ROW_H);
        // назад — к верхнему краю
        assert_eq!(keep_visible(&hs, 3, 10.0 * ROW_H, view), 3.0 * ROW_H);
    }

    #[test]
    fn usage_file_format() {
        let j = Json::parse(r#"{"counts":{"foot":3,"steam":13},"pinned":["steam","foot"]}"#).unwrap();
        let u = parse_usage(&j);
        assert_eq!(u.counts.get("steam"), Some(&13));
        assert_eq!(u.pinned, vec!["steam", "foot"]);
        assert_eq!(parse_usage(&Json::Null), Usage::default());
    }
}
