// Сочетания клавиш: из конфига niri + свои; смена, отключение, добавление (BindsPage.qml).
// amane не сообщает модификаторы, а Super-сочетания niri перехватывает сам — поэтому в окне выбора
// модификаторы включаются кнопками, а клавиша нажимается (или выбирается из списка особых).

use std::fs;

use amane::{Center, Color, Column, Key, Padding, Rectangle, Row, Service, Start, Weight, children};

use super::super::Prefs;
use super::super::w::{self, Btn, W, bx};
use super::Out;
use crate::json::Json;
use crate::look::Tk;
use crate::settings::{self, Settings};
use crate::ui::{self, ic};

#[derive(Debug, Clone, PartialEq)]
pub struct Bind {
    pub line: usize,
    pub enabled: bool,
    pub key: String,
    pub props: String,
    pub action: String,
}

pub const ACTIONS: [(&str, &str); 31] = [
    ("custom", "Run a command…"),
    ("spawn-sh \"$HOME/.local/bin/rexilone-shell ipc launcher toggle\";", "Shell · App launcher"),
    ("spawn-sh \"$HOME/.local/bin/rexilone-shell ipc clipboard toggle\";", "Shell · Clipboard"),
    ("spawn-sh \"$HOME/.local/bin/rexilone-shell ipc settings toggle\";", "Shell · Settings"),
    ("spawn-sh \"$HOME/.local/bin/rexilone-shell ipc wallpaper toggle\";", "Shell · Wallpapers"),
    ("spawn-sh \"$HOME/.local/bin/rexilone-shell ipc wallpaper random\";", "Shell · Random wallpaper"),
    ("spawn-sh \"$HOME/.local/bin/rexilone-shell ipc power toggle\";", "Shell · Power menu"),
    ("spawn-sh \"$HOME/.local/bin/rexilone-shell ipc recorder toggle\";", "Shell · Screen recorder"),
    ("spawn-sh \"$HOME/.local/bin/rexilone-shell ipc recorder record\";", "Shell · Start/stop recording"),
    ("spawn-sh \"$HOME/.local/bin/rexilone-shell ipc recorder saveReplay\";", "Shell · Save replay"),
    ("spawn-sh \"$HOME/.local/bin/rexilone-shell ipc idle caffeine\";", "Shell · Keep awake on/off"),
    ("spawn-sh \"$HOME/.local/bin/rexilone-shell ipc idle lock\";", "Shell · Lock screen"),
    ("close-window;", "Close window"),
    ("fullscreen-window;", "Fullscreen"),
    ("maximize-column;", "Maximize column"),
    ("toggle-window-floating;", "Float / tile window"),
    ("center-column;", "Center column"),
    ("toggle-overview;", "Overview"),
    ("screenshot;", "Screenshot (region)"),
    ("screenshot-screen;", "Screenshot (screen)"),
    ("screenshot-window;", "Screenshot (window)"),
    ("focus-workspace-up;", "Workspace up"),
    ("focus-workspace-down;", "Workspace down"),
    ("focus-column-left;", "Focus left"),
    ("focus-column-right;", "Focus right"),
    ("move-column-left;", "Move window left"),
    ("move-column-right;", "Move window right"),
    ("switch-preset-column-width;", "Cycle window width"),
    ("power-off-monitors;", "Turn off screens"),
    ("show-hotkey-overlay;", "Show shortcuts overlay"),
    ("toggle-keyboard-shortcuts-inhibit;", "Pause shortcuts"),
];

fn cfg_path() -> std::path::PathBuf {
    settings::home().join(".config/niri/config.kdl")
}

// строки блока binds { … } верхнего уровня
pub fn parse(text: &str) -> Vec<Bind> {
    let lines: Vec<&str> = text.split('\n').collect();
    let Some(start) = lines.iter().position(|l| l.starts_with("binds") && l[5..].trim_start().starts_with('{')) else { return Vec::new() };
    let mut out = Vec::new();
    for (i, l) in lines.iter().enumerate().skip(start + 1) {
        if l.starts_with('}') {
            break;
        }
        let t = l.trim_start();
        let (enabled, t) = match t.strip_prefix("/-") {
            Some(r) => (false, r.trim_start()),
            None => (true, t),
        };
        if t.starts_with("//") || t.is_empty() {
            continue;
        }
        let (Some(open), Some(close)) = (t.find('{'), t.rfind('}')) else { continue };
        if close < open || !t[close + 1..].trim().is_empty() {
            continue;
        }
        let head = t[..open].trim();
        let mut it = head.splitn(2, char::is_whitespace);
        let key = it.next().unwrap_or("").to_string();
        if key.is_empty() || key.contains('/') {
            continue;
        }
        out.push(Bind { line: i, enabled, key, props: it.next().unwrap_or("").trim().to_string(), action: t[open + 1..close].trim().to_string() });
    }
    out
}

pub fn set_cfg_enabled(text: &str, line: usize, on: bool) -> String {
    let mut lines: Vec<String> = text.split('\n').map(String::from).collect();
    if let Some(l) = lines.get_mut(line) {
        let indent: String = l.chars().take_while(|c| c.is_whitespace()).collect();
        let body = l.trim_start();
        let disabled = body.starts_with("/-");
        if on && disabled {
            *l = format!("{indent}{}", body.trim_start_matches("/-").trim_start());
        } else if !on && !disabled {
            *l = format!("{indent}/-{body}");
        }
    }
    lines.join("\n")
}

pub fn title_of(b_props: &str, action: &str) -> String {
    if let Some(i) = b_props.find("hotkey-overlay-title=\"") {
        let rest = &b_props[i + 22..];
        return rest.split('"').next().unwrap_or("").to_string();
    }
    if let Some((_, l)) = ACTIONS.iter().find(|(v, _)| *v == action) {
        return l.trim_start_matches("Shell · ").to_string();
    }
    let a = action.trim_end_matches(';');
    if let Some(rest) = a.strip_prefix("spawn-sh ").or_else(|| a.strip_prefix("spawn ")) {
        return format!("Run {}", rest.replace('"', ""));
    }
    let s = a.replace('-', " ");
    let mut c = s.chars();
    c.next().map(|f| f.to_uppercase().chain(c).collect()).unwrap_or_default()
}

// без модификатора — только F-клавиши, Print, Pause, Insert (иначе бинд съест букву при наборе)
pub fn valid_key(k: &str) -> bool {
    k.contains('+') || (k.starts_with('F') && k[1..].parse::<u32>().is_ok()) || ["Print", "Pause", "Insert"].contains(&k)
}

// нажатый символ → имя клавиши xkb (по-русски набранная буква — та же клавиша в английской раскладке)
pub fn key_name(c: char) -> Option<String> {
    let c = crate::search::translit(&c.to_lowercase().to_string()).chars().next()?;
    Some(match c {
        'a'..='z' => c.to_ascii_uppercase().to_string(),
        '0'..='9' => c.to_string(),
        '-' | '_' => "Minus".into(),
        '=' | '+' => "Equal".into(),
        '[' | '{' => "BracketLeft".into(),
        ']' | '}' => "BracketRight".into(),
        ';' | ':' => "Semicolon".into(),
        '\'' | '"' => "Apostrophe".into(),
        '`' | '~' => "Grave".into(),
        '\\' | '|' => "Backslash".into(),
        ',' | '<' => "Comma".into(),
        '.' | '>' => "Period".into(),
        '/' | '?' => "Slash".into(),
        _ => return None,
    })
}

pub const SPECIAL: [&str; 24] = [
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Space", "Return", "Tab", "BackSpace", "Print", "Pause", "Insert", "Delete", "Home", "End", "Page_Up", "Page_Down",
];

fn own() -> Vec<Json> {
    settings::load().get("binds").arr().to_vec()
}

fn set_own(i: usize, kv: Option<(&str, Json)>) {
    let mut a = own();
    match kv {
        None => {
            if i < a.len() {
                a.remove(i);
            }
        }
        Some((k, v)) => {
            if let Some(o) = a.get_mut(i) {
                o.set(k, v)
            }
        }
    }
    settings::save_key("binds", Json::Arr(a));
}

fn write_cfg(f: impl FnOnce(&str) -> String) {
    let p = cfg_path();
    if let Ok(t) = fs::read_to_string(&p) {
        let n = f(&t);
        if n != t {
            let _ = fs::write(&p, n);
        }
    }
    crate::cmd::forget("niri-config");
}

// клавиши без учёта регистра → активный бинд (свои перекрывают конфиг)
fn conflict(key: &str, cfg: &[Bind], own: &[Json], except: &str) -> Option<(bool, usize, String)> {
    let k = key.to_lowercase();
    let mut hit = None;
    for b in cfg.iter().filter(|b| b.enabled && b.key.to_lowercase() == k) {
        hit = Some((false, b.line, title_of(&b.props, &b.action)));
    }
    for (i, b) in own.iter().enumerate() {
        if b.get("enabled").bool_or(true) && b.get("key").str_or("").to_lowercase() == k {
            hit = Some((true, i, title_of(&b.get("props").str_or(""), &b.get("action").str_or(""))));
        }
    }
    hit.filter(|h| format!("{}:{}", if h.0 { "own" } else { "cfg" }, h.1) != except)
}

// сохранить выбранное сочетание (как applyCapture)
fn apply_capture(key: String) {
    let mode = Prefs::get("binds:capture");
    Prefs::set("binds:capture", "");
    if mode.is_empty() || !valid_key(&key) {
        return;
    }
    let text = fs::read_to_string(cfg_path()).unwrap_or_default();
    let cfg = parse(&text);
    let ownl = own();
    if let Some((is_own, idx, _)) = conflict(&key, &cfg, &ownl, &mode) {
        if is_own {
            set_own(idx, Some(("enabled", Json::Bool(false))));
        } else {
            write_cfg(|t| set_cfg_enabled(t, idx, false));
        }
    }
    let ownl = own();
    if let Some(line) = mode.strip_prefix("cfg:").and_then(|l| l.parse::<usize>().ok()) {
        // бинд из конфига: отключаем строку и добавляем свою копию с новыми клавишами
        if let Some(b) = cfg.iter().find(|b| b.line == line) {
            let b = b.clone();
            write_cfg(|t| set_cfg_enabled(t, line, false));
            let mut a = ownl;
            a.push(Json::Obj(vec![
                ("key".into(), Json::Str(key)),
                ("props".into(), Json::Str(b.props)),
                ("action".into(), Json::Str(b.action)),
                ("enabled".into(), Json::Bool(true)),
            ]));
            settings::save_key("binds", Json::Arr(a));
        }
    } else if let Some(i) = mode.strip_prefix("own:").and_then(|l| l.parse::<usize>().ok()) {
        set_own(i, Some(("key", Json::Str(key))));
    } else {
        let act = Prefs::get("binds:new-action");
        let act = if act.is_empty() { "custom".to_string() } else { act };
        let cmd = w::field_text("binds-cmd");
        let (action, label) = if act == "custom" {
            (format!("spawn-sh \"{}\";", cmd.replace('\\', "\\\\").replace('"', "\\\"")), cmd.clone())
        } else {
            (act.clone(), ACTIONS.iter().find(|(v, _)| *v == act).map(|(_, l)| l.trim_start_matches("Shell · ").to_string()).unwrap_or_default())
        };
        let mut a = ownl;
        a.push(Json::Obj(vec![
            ("key".into(), Json::Str(key)),
            ("props".into(), Json::Str(format!("hotkey-overlay-title=\"{}\"", label.replace('"', "")))),
            ("action".into(), Json::Str(action)),
            ("enabled".into(), Json::Bool(true)),
        ]));
        settings::save_key("binds", Json::Arr(a));
        w::set_field("binds-cmd", "");
    }
}

fn captured() -> String {
    let mods: Vec<&str> = ["Mod", "Ctrl", "Alt", "Shift"].into_iter().filter(|m| Prefs::flag(&format!("binds:mod:{m}"))).collect();
    let k = Prefs::get("binds:key");
    if k.is_empty() {
        return String::new();
    }
    let mut v: Vec<String> = mods.into_iter().map(String::from).collect();
    v.push(k);
    v.join("+")
}

// клавиши окна, пока открыт выбор сочетания
pub fn on_key(k: Key) -> bool {
    if Prefs::get("binds:capture").is_empty() {
        return false;
    }
    match k {
        Key::Escape => Prefs::set("binds:capture", ""),
        Key::Character(c) => {
            if let Some(n) = key_name(c) {
                Prefs::set("binds:key", &n);
            }
        }
        Key::Space => Prefs::set("binds:key", "Space"),
        Key::Enter => Prefs::set("binds:key", "Return"),
        Key::Tab => Prefs::set("binds:key", "Tab"),
        Key::Backspace => Prefs::set("binds:key", "BackSpace"),
        Key::Up => Prefs::set("binds:key", "Up"),
        Key::Down => Prefs::set("binds:key", "Down"),
        Key::Left => Prefs::set("binds:key", "Left"),
        Key::Right => Prefs::set("binds:key", "Right"),
        Key::Home => Prefs::set("binds:key", "Home"),
        Key::End => Prefs::set("binds:key", "End"),
        _ => {}
    }
    true
}

fn start_capture(mode: &str, key: &str) {
    // текущие клавиши — как начальный выбор
    let parts: Vec<&str> = key.split('+').collect();
    for m in ["Mod", "Ctrl", "Alt", "Shift"] {
        Prefs::set(&format!("binds:mod:{m}"), if parts.contains(&m) { "1" } else { "" });
    }
    Prefs::set("binds:key", if key.is_empty() { "" } else { parts.last().copied().unwrap_or("") });
    if key.is_empty() {
        Prefs::set("binds:mod:Mod", "1");
    }
    Prefs::set("binds:capture", mode);
}

fn key_chips(t: &Tk, key: &str) -> Row {
    let mut chips: Vec<W> = Vec::new();
    for p in key.split('+') {
        let label = if p == "Mod" { "Super".to_string() } else { p.replace('_', " ") };
        let txt = ui::text(t, label, t.p.fg).size(t.fs - 2.0).weight(Weight::Bold);
        let tw = crate::bar::width_of(&txt);
        chips.push(bx(Rectangle::new().width(tw + 14.0).height(24.0).radius(6.0).fill(t.p.surface_hi2).border(1.0, t.p.line).align_child(Center, Center).child(txt)));
    }
    Row::new(chips).gap(4.0)
}

fn bind_row(t: &Tk, w: f32, key: &str, title: &str, on: bool, own_idx: Option<usize>, cfg_line: Option<usize>) -> W {
    let id = match own_idx {
        Some(i) => format!("bown:{i}"),
        None => format!("bcfg:{}", cfg_line.unwrap_or(0)),
    };
    let hv = w::hov(&id) || w::hov(&format!("{id}:chg"));
    let mut right: Vec<W> = Vec::new();
    if own_idx.is_some() {
        let txt = ui::text(t, t.t("custom"), t.p.accent).size(t.fs - 4.0);
        let tw = crate::bar::width_of(&txt);
        right.push(bx(Rectangle::new().width(tw + 12.0).height(18.0).radius(5.0).border(1.0, t.p.accent).align_child(Center, Center).child(txt)));
    }
    let mode = match own_idx {
        Some(i) => format!("own:{i}"),
        None => format!("cfg:{}", cfg_line.unwrap_or(0)),
    };
    let k2 = key.to_string();
    if hv {
        right.push(bx(Btn::new("Change").build(t, &format!("{id}:chg"), move || start_capture(&mode, &k2))));
    }
    if let Some(i) = own_idx {
        right.push(bx(Btn::new("").icon(ic::TRASH).danger().build(t, &format!("{id}:del"), move || set_own(i, None))));
    }
    right.push(bx(w::switch(t, &format!("{id}:sw"), on, move |v| match (own_idx, cfg_line) {
        (Some(i), _) => set_own(i, Some(("enabled", Json::Bool(v)))),
        (None, Some(l)) => write_cfg(|t| set_cfg_enabled(t, l, v)),
        _ => {}
    })));
    let rr = Row::new(right).gap(8.0).align(Center);
    let (rw, _) = w::wh(&rr);
    let tw = (w - 16.0 - 12.0 - 250.0 - rw - 24.0).max(40.0);
    let r = Rectangle::new()
        .width(w)
        .height(52.0)
        .radius(10.0)
        .fill(if hv { t.p.surface_hi } else { t.p.surface })
        .opacity(if on { 1.0 } else { 0.5 })
        .padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 16.0 })
        .child(
            Row::new(children![
                Rectangle::new().width(250.0).height(52.0).align_child(Start, Center).clip().child(key_chips(t, key)),
                w::line(t, title, t.fs - 1.0, t.p.fg, tw, false),
                rr
            ])
            .gap(12.0)
            .height(52.0)
            .align(Center),
        );
    bx(w::track(r, &id))
}

pub fn page(t: &Tk, w: f32) -> Out {
    let text = crate::cmd::get("niri-config", &format!("cat {}", crate::niri::sh_quote(&cfg_path().to_string_lossy()))).unwrap_or_default();
    let cfg = parse(&text);
    let ownl = Settings::read().raw.get("binds").arr().to_vec();
    let mut items: Vec<W> = Vec::new();
    let capture = Prefs::get("binds:capture");

    // ── окно выбора сочетания (вверху страницы)
    if !capture.is_empty() {
        let cap = captured();
        let hit = if cap.is_empty() { None } else { conflict(&cap, &cfg, &ownl, &capture) };
        let (msg, col) = if cap.is_empty() {
            (t.t("Choose modifiers and press a key"), t.p.dim)
        } else if !valid_key(&cap) {
            (t.t("Add a modifier — a single letter would block typing"), t.p.urgent)
        } else if let Some((_, _, title)) = &hit {
            (if t.c.ru() { format!("Уже занято «{title}» — оно отключится") } else { format!("Already used by «{title}» — it will be turned off") }, t.p.warn)
        } else {
            (t.t("Looks good"), t.p.dim)
        };
        let mut mods: Vec<W> = Vec::new();
        for (m, label) in [("Mod", "Super"), ("Ctrl", "Ctrl"), ("Alt", "Alt"), ("Shift", "Shift")] {
            let on = Prefs::flag(&format!("binds:mod:{m}"));
            let id = format!("binds-mod:{m}");
            let txt = ui::text(t, label, if on { t.p.bg } else { t.p.fg }).size(t.fs - 1.0).weight(Weight::Bold);
            let tw = crate::bar::width_of(&txt);
            let r = Rectangle::new().width(tw + 24.0).height(32.0).radius(8.0).fill(if on { t.p.accent } else { t.p.surface_hi }).border(1.0, t.p.surface_hi2).align_child(Center, Center).child(txt);
            mods.push(bx(w::clickable(r, &id, w::act(move || Prefs::toggle_flag(&format!("binds:mod:{m}"))))));
        }
        mods.push(bx(Rectangle::new().width(14.0).height(32.0).align_child(Center, Center).child(ui::text(t, "+", t.p.dim))));
        let special: Vec<(String, String)> = std::iter::once((String::new(), t.t("Press a key or choose…"))).chain(SPECIAL.iter().map(|s| (s.to_string(), s.replace('_', " ")))).collect();
        let cur_key = Prefs::get("binds:key");
        mods.push(bx(w::dropdown(t, "binds-special", &special, if SPECIAL.contains(&cur_key.as_str()) { &cur_key } else { "" }, 200.0, |v| Prefs::set("binds:key", &v))));
        let cap2 = cap.clone();
        let inner = Column::new(children![
            w::tx(t, "Press the new shortcut", t.fs + 2.0, t.p.fg).weight(Weight::Bold),
            Row::new(mods).gap(6.0).align(Center),
            w::raw(t, if cap.is_empty() { "…".to_string() } else { cap.replace("Mod", "Super").split('+').collect::<Vec<_>>().join("  +  ") }, t.fs + 6.0, t.p.accent).weight(Weight::Bold),
            w::line(t, &msg, t.fs - 2.0, col, w - 60.0, false),
            Row::new(children![
                Btn::new("Cancel").build(t, "binds-cancel", || Prefs::set("binds:capture", "")),
                Btn::new("Save").primary().enabled(!cap.is_empty() && valid_key(&cap)).build(t, "binds-save", move || apply_capture(cap2.clone()))
            ])
            .gap(8.0)
        ])
        .gap(12.0);
        let (_, ih) = w::wh(&inner);
        items.push(bx(Rectangle::new().width(w).height(ih + 40.0).radius(16.0).fill(t.p.surface).border(1.0, t.p.accent).padding(20.0).child(inner)));
    }

    // ── добавить
    items.push(bx(w::section(t, "Add a shortcut", w)));
    let act = Prefs::get("binds:new-action");
    let act = if act.is_empty() { "custom".to_string() } else { act };
    let opts: Vec<(String, String)> = ACTIONS.iter().map(|(v, l)| (v.to_string(), l.to_string())).collect();
    let typed = w::field_text("binds-cmd");
    let mut row: Vec<W> = vec![bx(w::dropdown(t, "binds-action", &opts, &act, 260.0, |v| Prefs::set("binds:new-action", &v)))];
    if act == "custom" {
        row.push(bx(w::field(t, "binds-cmd", (w - 36.0 - 260.0 - 160.0 - 20.0).max(120.0), "Command, e.g. telegram-desktop", 0, |_| {})));
    }
    row.push(bx(Btn::new("Choose keys…").primary().enabled(act != "custom" || !typed.trim().is_empty()).build(t, "binds-choose", || start_capture("new", ""))));
    let rr = Row::new(row).gap(10.0).align(Center);
    let (_, rh) = w::wh(&rr);
    items.push(bx(Rectangle::new().width(w).height(rh + 28.0).radius(10.0).fill(t.p.surface).padding(Padding { top: 14.0, right: 18.0, bottom: 14.0, left: 18.0 }).child(rr)));

    // ── поиск и список
    let query = w::field_text("binds-search").to_lowercase();
    let search = w::field(t, "binds-search", 260.0, "Search keys or actions", ic::SEARCH, |_| {});
    items.push(bx(w::gap(14.0)));
    items.push(bx(Row::new(children![w::line(t, &t.t("Shortcuts"), t.fs, t.p.fg, w - 270.0, true), search]).gap(10.0).align(Center)));
    let matches = |key: &str, title: &str, action: &str| query.is_empty() || format!("{key} {title} {action}").to_lowercase().contains(&query);
    for (i, b) in ownl.iter().enumerate() {
        let (key, props, action) = (b.get("key").str_or(""), b.get("props").str_or(""), b.get("action").str_or(""));
        let title = title_of(&props, &action);
        if matches(&key, &title, &action) {
            items.push(bind_row(t, w, &key, &title, b.get("enabled").bool_or(true), Some(i), None));
        }
    }
    for b in &cfg {
        let title = title_of(&b.props, &b.action);
        if matches(&b.key, &title, &b.action) {
            items.push(bind_row(t, w, &b.key, &title, b.enabled, None, Some(b.line)));
        }
    }
    let _ = Color::TRANSPARENT;
    Out { crumb: String::new(), subtitle: "Change, turn off or add shortcuts. Changes apply instantly.".into(), items }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CFG: &str = "input {\n}\nbinds {\n    // комментарий\n    Mod+D hotkey-overlay-title=\"Run an Application\" { spawn-sh \"x\"; }\n    /-Mod+Q { close-window; }\n    Mod+Shift+E repeat=false { quit; }\n    XF86AudioMute allow-when-locked=true { spawn \"wpctl\" \"set-mute\"; }\n}\nwindow-rule {\n    Mod+Z { nope; }\n}\n";

    #[test]
    fn parses_binds_block() {
        let b = parse(CFG);
        assert_eq!(b.len(), 4);
        assert_eq!(b[0], Bind { line: 4, enabled: true, key: "Mod+D".into(), props: "hotkey-overlay-title=\"Run an Application\"".into(), action: "spawn-sh \"x\";".into() });
        assert!(!b[1].enabled);
        assert_eq!(b[2].props, "repeat=false");
        assert_eq!(title_of(&b[0].props, &b[0].action), "Run an Application");
        assert_eq!(title_of("", "close-window;"), "Close window");
        assert_eq!(title_of("", "spawn \"wpctl\" \"set-mute\";"), "Run wpctl set-mute");
        assert_eq!(title_of("", "focus-column-left;"), "Focus left");
        assert_eq!(title_of("", "toggle-overview-x;"), "Toggle overview x");
    }

    #[test]
    fn toggles_config_lines() {
        let off = set_cfg_enabled(CFG, 4, false);
        assert!(off.contains("\n    /-Mod+D hotkey"));
        let on = set_cfg_enabled(CFG, 5, true);
        assert!(on.contains("\n    Mod+Q { close-window; }"));
        assert_eq!(set_cfg_enabled(CFG, 4, true), CFG);
    }

    #[test]
    fn keys() {
        assert!(valid_key("Mod+T"));
        assert!(valid_key("F5"));
        assert!(valid_key("Print"));
        assert!(!valid_key("T"));
        assert!(!valid_key("Fx"));
        assert_eq!(key_name('t'), Some("T".into()));
        assert_eq!(key_name('е'), Some("T".into()));
        assert_eq!(key_name('['), Some("BracketLeft".into()));
        assert_eq!(key_name('х'), Some("BracketLeft".into()));
        assert_eq!(key_name('5'), Some("5".into()));
        assert_eq!(key_name('§'), None);
    }

    #[test]
    fn conflicts_prefer_own() {
        let cfg = parse(CFG);
        let own = vec![Json::parse(r#"{"key":"mod+d","action":"x;","enabled":true}"#).unwrap()];
        let hit = conflict("Mod+D", &cfg, &own, "").unwrap();
        assert!(hit.0);
        assert!(conflict("Mod+D", &cfg, &own, "own:0").is_none());
        assert!(conflict("Mod+Q", &cfg, &[], "").is_none());
        assert_eq!(conflict("Mod+Shift+E", &cfg, &[], "").map(|h| h.1), Some(6));
    }
}
