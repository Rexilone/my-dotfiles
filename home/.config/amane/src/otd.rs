// графический планшет через OpenTabletDriver (как Tablet.qml): экран, рабочая область, поворот.
// Настройки — ~/.config/OpenTabletDriver/settings.json; после правки — `otd loadsettings`.
// Область в мм, X/Y — центр, как у самого OTD.

use std::time::{Duration, SystemTime};

use amane::Service;

use crate::json::Json;
use crate::settings::{self, Settings};

#[derive(Debug, Clone, PartialEq)]
pub struct Disp {
    pub index: i64,
    pub name: String,
    pub w: f64,
    pub h: f64,
    pub x: f64,
    pub y: f64,
}

#[derive(Default)]
pub struct Tablet {
    pub installed: bool,
    pub running: bool,
    pub data: Json,
    pub displays: Vec<Disp>,
}

pub fn path() -> String {
    settings::home().join(".config/OpenTabletDriver/settings.json").to_string_lossy().to_string()
}

fn tb_setting(k: &str) -> f64 {
    Settings::read().raw.get("input").get("tablet").get(k).num_or(0.0)
}

impl Tablet {
    pub fn profile(&self) -> &Json {
        self.data.get("Profiles").at(0)
    }
    pub fn active(&self) -> bool {
        self.installed && !self.profile().is_null()
    }
    pub fn name(&self) -> String {
        self.profile().get("Tablet").str_or("")
    }
    pub fn area(&self) -> &Json {
        self.profile().get("AbsoluteModeSettings").get("Tablet")
    }
    pub fn display(&self) -> &Json {
        self.profile().get("AbsoluteModeSettings").get("Display")
    }
    pub fn lock(&self) -> bool {
        self.profile().get("AbsoluteModeSettings").get("LockAspectRatio").bool_or(false)
    }
    pub fn rotation(&self) -> i64 {
        self.area().get("Rotation").num_or(0.0) as i64
    }
    // полный размер планшета: запомнен, пока область была весь планшет
    pub fn max_w(&self) -> f64 {
        Some(tb_setting("otdMaxW")).filter(|v| *v > 0.0).or(self.area().get("Width").num()).unwrap_or(216.0)
    }
    pub fn max_h(&self) -> f64 {
        Some(tb_setting("otdMaxH")).filter(|v| *v > 0.0).or(self.area().get("Height").num()).unwrap_or(135.0)
    }
    // выбранный экран: имя вывода или "" — все мониторы
    pub fn screen(&self) -> String {
        let d = self.display();
        let (dw, dh, dx, dy) = (d.get("Width").num_or(0.0), d.get("Height").num_or(0.0), d.get("X").num_or(0.0), d.get("Y").num_or(0.0));
        if d.is_null() {
            return String::new();
        }
        self.displays
            .iter()
            .find(|s| s.index > 0 && (s.x + s.w / 2.0 - dx).abs() < 2.0 && (s.y + s.h / 2.0 - dy).abs() < 2.0 && (s.w - dw).abs() < 2.0 && (s.h - dh).abs() < 2.0)
            .map(|s| s.name.clone())
            .unwrap_or_default()
    }
    pub fn display_aspect(&self) -> f64 {
        let d = self.display();
        if d.is_null() {
            return 16.0 / 9.0;
        }
        let a = d.get("Width").num_or(16.0) / d.get("Height").num_or(9.0);
        if matches!(self.rotation(), 90 | 270) { 1.0 / a } else { a }
    }
}

// «2: DP-1 Xiaomi … (1920x1080@<900  0>)»
pub fn parse_displays(text: &str) -> Vec<Disp> {
    let mut v = Vec::new();
    for l in text.lines() {
        let Some((idx, rest)) = l.split_once(':') else { continue };
        let Ok(index) = idx.trim().parse::<i64>() else { continue };
        let name = rest.split_whitespace().next().unwrap_or("").to_string();
        let Some(p) = rest.rfind('(') else { continue };
        let inner = rest[p + 1..].trim_end_matches(')');
        let Some((wh, pos)) = inner.split_once("@<") else { continue };
        let Some((w, h)) = wh.split_once('x') else { continue };
        let pos: Vec<&str> = pos.trim_end_matches('>').split_whitespace().collect();
        let (Ok(w), Ok(h)) = (w.parse::<f64>(), h.parse::<f64>()) else { continue };
        let (Some(x), Some(y)) = (pos.first().and_then(|s| s.parse::<f64>().ok()), pos.get(1).and_then(|s| s.parse::<f64>().ok())) else { continue };
        v.push(Disp { index, name: if index == 0 { String::new() } else { name }, w, h, x, y });
    }
    v
}

// поправить AbsoluteModeSettings, записать файл и применить к драйверу
fn edit(f: impl FnOnce(&mut Json)) {
    let mut d = Tablet::read().data.clone();
    let Some(s) = d.get_mut("Profiles").and_then(|p| p.at_mut(0)).and_then(|p| p.get_mut("AbsoluteModeSettings")) else { return };
    f(s);
    let text = d.pretty_with(2);
    Tablet::write().data = d;
    std::thread::spawn(move || {
        if std::fs::write(path(), text).is_ok() {
            amane::output(&format!("otd loadsettings {}", crate::niri::sh_quote(&path())));
        }
    });
}

fn sub(s: &mut Json, k: &str) -> Json {
    s.get(k).clone()
}

pub fn set_screen(name: &str) {
    let ds = Tablet::read().displays.clone();
    let Some(d) = (if name.is_empty() { ds.iter().find(|x| x.index == 0) } else { ds.iter().find(|x| x.name == name) }).cloned() else { return };
    edit(|s| {
        let mut disp = sub(s, "Display");
        disp.set("Width", Json::Num(d.w));
        disp.set("Height", Json::Num(d.h));
        disp.set("X", Json::Num(d.x + d.w / 2.0));
        disp.set("Y", Json::Num(d.y + d.h / 2.0));
        s.set("Display", disp);
    });
}

// область: размер и центр в мм; не выходит за край планшета
pub fn set_area(w: f64, h: f64, cx: f64, cy: f64) {
    let (mw, mh) = {
        let t = Tablet::read();
        (t.max_w(), t.max_h())
    };
    let w = w.min(mw).max(10.0);
    let h = h.min(mh).max(10.0);
    let cx = cx.min(mw - w / 2.0).max(w / 2.0);
    let cy = cy.min(mh - h / 2.0).max(h / 2.0);
    let r = |v: f64| Json::Num((v * 100.0).round() / 100.0);
    edit(|s| {
        let mut a = sub(s, "Tablet");
        a.set("Width", r(w));
        a.set("Height", r(h));
        a.set("X", r(cx));
        a.set("Y", r(cy));
        s.set("Tablet", a);
    });
}

pub fn set_rotation(deg: i64) {
    edit(|s| {
        let mut a = sub(s, "Tablet");
        a.set("Rotation", Json::Num(deg as f64));
        s.set("Tablet", a);
    });
}

pub fn set_lock(on: bool) {
    edit(|s| s.set("LockAspectRatio", Json::Bool(on)));
}

// подогнать размер под пропорции экрана
pub fn fit(w: f64, h: f64, a: f64) -> (f64, f64) {
    if w / h > a { (h * a, h) } else { (w, w / a) }
}

pub fn preset(frac: f64) {
    let (mw, mh, lock, a) = {
        let t = Tablet::read();
        (t.max_w(), t.max_h(), t.lock(), t.display_aspect())
    };
    let (mut w, mut h) = (mw * frac, mh * frac);
    if lock {
        (w, h) = fit(w, h, a);
    }
    set_area(w, h, mw / 2.0, mh / 2.0);
}

fn load() {
    if let Some(d) = std::fs::read_to_string(path()).ok().and_then(|t| Json::parse(&t)) {
        if Tablet::read().data != d {
            Tablet::write().data = d;
        }
    }
}

pub fn refresh() {
    let out = amane::output("command -v otd >/dev/null && echo installed; systemctl --user is-active -q opentabletdriver.service && echo running; command -v otd >/dev/null && timeout 5 otd listdisplays 2>/dev/null");
    let ds = parse_displays(&out);
    {
        let mut t = Tablet::write();
        t.installed = out.lines().any(|l| l == "installed");
        t.running = out.lines().any(|l| l == "running");
        if !ds.is_empty() {
            t.displays = ds;
        }
    }
    load();
    sync();
}

// запомнить размер планшета; перенести старые настройки niri (монитор, «для левши») в OTD
fn sync() {
    if !Tablet::read().active() {
        return;
    }
    let tb = Settings::read().raw.get("input").get("tablet").clone();
    let save = |k: &str, v: Json| settings::save_path(&["input", "tablet", k], v);
    if !tb.get("otd").bool_or(false) {
        save("otd", Json::Bool(true));
    }
    let (area, has_disp) = {
        let t = Tablet::read();
        (t.area().clone(), !t.displays.is_empty())
    };
    let (aw, ah, ax, ay) = (area.get("Width").num_or(0.0), area.get("Height").num_or(0.0), area.get("X").num_or(0.0), area.get("Y").num_or(0.0));
    if tb.get("otdMaxW").num_or(0.0) == 0.0 && !area.is_null() && (ax - aw / 2.0).abs() < 0.5 && (ay - ah / 2.0).abs() < 0.5 {
        save("otdMaxW", Json::Num(aw));
        save("otdMaxH", Json::Num(ah));
    }
    if !tb.get("otdMigrated").bool_or(false) && has_disp {
        save("otdMigrated", Json::Bool(true));
        let m = tb.get("mapTo").str_or("");
        if !m.is_empty() {
            set_screen(&m);
        }
    }
    if !tb.get("otdRotMigrated").bool_or(false) {
        save("otdRotMigrated", Json::Bool(true));
        let r = tb.get("rotation").num_or(0.0) as i64;
        if r != 0 && area.get("Rotation").num_or(0.0) == 0.0 {
            set_rotation(r);
        }
    }
}

impl Service for Tablet {
    fn new() -> Self {
        Tablet::default()
    }

    // файл меняют извне (otd-gui) — перечитать; экраны и драйвер — раз в 30 с
    fn listen() {
        refresh();
        let mtime = || std::fs::metadata(path()).and_then(|m| m.modified()).ok();
        let mut seen: Option<SystemTime> = mtime();
        let mut n = 0;
        loop {
            std::thread::sleep(Duration::from_secs(2));
            let m = mtime();
            if m != seen {
                seen = m;
                load();
            }
            n += 1;
            if n % 15 == 0 && Tablet::read().installed {
                refresh();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn displays_and_fit() {
        let d = parse_displays("0: Virtual Display (3840x1080@<0 0>)\n1: DP-1 Xiaomi Mi Monitor (1920x1080@<0 0>)\n2: HDMI-A-1 LG (1920x1080@<1920  0>)\n");
        assert_eq!(d.len(), 3);
        assert_eq!(d[0].name, "");
        assert_eq!(d[2], Disp { index: 2, name: "HDMI-A-1".into(), w: 1920.0, h: 1080.0, x: 1920.0, y: 0.0 });
        let (w, h) = fit(160.0, 100.0, 16.0 / 9.0);
        assert!((w - 160.0).abs() < 0.01 && (h - 90.0).abs() < 0.01);
    }
}
