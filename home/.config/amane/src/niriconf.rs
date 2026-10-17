// ~/.config/niri/qs-settings.kdl из настроек: ввод, мониторы, бинды, автозапуск (как NiriSettings.qml).
// niri перечитывает файл сам.

use std::fs;
use std::path::PathBuf;
use std::thread;
use std::time::Duration;

use amane::Service;

use crate::json::Json;
use crate::settings::{self, Config};

pub fn path() -> PathBuf {
    std::env::var_os("REXILONE_NIRI_KDL").map(PathBuf::from).unwrap_or_else(|| settings::home().join(".config/niri/qs-settings.kdl"))
}

// «производитель модель серийник» — так niri тоже называет монитор; по нему настройки
// находят монитор, даже если его переткнули в другой порт
pub fn id_of(o: &Json) -> String {
    if o.is_null() {
        return String::new();
    }
    let f = |k: &str| o.get(k).str().unwrap_or("Unknown").to_string();
    format!("{} {} {}", f("make"), f("model"), f("serial"))
}

pub fn mode_key(m: &Json) -> String {
    format!("{}x{}@{:.3}", m.get("width").num_or(0.0), m.get("height").num_or(0.0), m.get("refresh_rate").num_or(0.0) / 1000.0)
}

// настройки одного монитора из текущего состояния niri
pub fn from_live_one(o: &Json) -> Json {
    let cur = o.get("current_mode");
    let m = o.get("modes").at(cur.num().map(|n| n as usize).unwrap_or(0));
    let l = o.get("logical");
    Json::Obj(vec![
        ("id".into(), Json::Str(id_of(o))),
        ("mode".into(), Json::Str(if m.is_null() { String::new() } else { mode_key(m) })),
        ("scale".into(), Json::Num(l.get("scale").num_or(1.0))),
        ("transform".into(), Json::Str(l.get("transform").str_or("normal").to_lowercase())),
        ("x".into(), Json::Num(l.get("x").num_or(0.0))),
        ("y".into(), Json::Num(l.get("y").num_or(0.0))),
        ("vrr".into(), Json::Bool(o.get("vrr_enabled").bool_or(false))),
        ("off".into(), Json::Bool(cur.is_null())),
    ])
}

pub fn from_live(live: &Json) -> Json {
    Json::Obj(live.obj().iter().map(|(n, o)| (n.clone(), from_live_one(o))).collect())
}

// сохранённые настройки для подключённого монитора: по порту, а если там другой — по id
pub fn saved_for<'a>(saved: &'a Json, live: &Json, name: &str) -> Option<(&'a str, &'a Json)> {
    let id = id_of(live.get(name));
    for (k, s) in saved.obj() {
        if k == name {
            let sid = s.get("id").str().unwrap_or("");
            if sid.is_empty() || sid == id {
                return Some((k.as_str(), s));
            }
        }
    }
    saved
        .obj()
        .iter()
        .find(|(k, s)| s.get("id").str() == Some(id.as_str()) && live.get(k).is_null())
        .map(|(k, s)| (k.as_str(), s))
}

// подключённые мониторы: сохранённые настройки поверх текущего состояния
// порядок — по имени: niri отдаёт мониторы в случайном порядке, а файл не должен переписываться зря
pub fn current(saved: &Json, live: &Json) -> Vec<(String, Json)> {
    if live.obj().is_empty() {
        return saved.obj().to_vec();
    }
    let mut names: Vec<&(String, Json)> = live.obj().iter().collect();
    names.sort_by(|a, b| a.0.cmp(&b.0));
    names
        .into_iter()
        .map(|(name, o)| {
            let mut s = saved_for(saved, live, name).map(|(_, s)| s.clone()).unwrap_or_else(|| from_live_one(o));
            s.set("id", Json::Str(id_of(o)));
            (name.clone(), s)
        })
        .collect()
}

// сохранённые, но сейчас не подключённые (вернутся при подключении)
pub fn disconnected(saved: &Json, live: &Json) -> Vec<(String, Json)> {
    if live.obj().is_empty() {
        return Vec::new();
    }
    let used: Vec<&str> = live.obj().iter().filter_map(|(n, _)| saved_for(saved, live, n).map(|(k, _)| k)).collect();
    saved.obj().iter().filter(|(k, _)| !used.contains(&k.as_str())).cloned().collect()
}

// пропорции монитора (с учётом поворота) или всех мониторов вместе
pub fn output_aspect(live: &Json, name: &str) -> f64 {
    let outs: Vec<&Json> = if !name.is_empty() && !live.get(name).is_null() { vec![live.get(name)] } else { live.obj().iter().map(|(_, o)| o).collect() };
    let (mut x0, mut y0, mut x1, mut y1) = (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
    for o in outs {
        let l = o.get("logical");
        if l.is_null() {
            continue;
        }
        let (x, y, w, h) = (l.get("x").num_or(0.0), l.get("y").num_or(0.0), l.get("width").num_or(0.0), l.get("height").num_or(0.0));
        x0 = x0.min(x);
        y0 = y0.min(y);
        x1 = x1.max(x + w);
        y1 = y1.max(y + h);
    }
    if x1 > x0 && y1 > y0 { (x1 - x0) / (y1 - y0) } else { 0.0 }
}

// матрица калибровки планшета-экрана: поворот и обрезка под пропорции монитора
pub fn tablet_matrix(tb: &Json, live: &Json) -> Option<[f64; 6]> {
    let rot = tb.get("rotation").num_or(0.0) as i64;
    let r: [[f64; 3]; 2] = match rot {
        90 => [[0.0, -1.0, 1.0], [1.0, 0.0, 0.0]],
        180 => [[-1.0, 0.0, 1.0], [0.0, -1.0, 1.0]],
        270 => [[0.0, 1.0, 0.0], [-1.0, 0.0, 1.0]],
        _ => [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]],
    };
    let (mut sx, mut sy, mut ox, mut oy) = (1.0, 1.0, 0.0, 0.0);
    let (wmm, hmm) = (tb.get("widthMm").num_or(0.0), tb.get("heightMm").num_or(0.0));
    if tb.get("keepAspect").bool_or(false) && wmm > 0.0 && hmm > 0.0 {
        let side = rot == 90 || rot == 270;
        let ta = if side { hmm / wmm } else { wmm / hmm };
        let oa = output_aspect(live, tb.get("mapTo").str().unwrap_or(""));
        if oa > 0.0 && (ta - oa).abs() > 0.001 {
            if ta > oa {
                let f = oa / ta;
                sx = 1.0 / f;
                ox = -(1.0 - f) / (2.0 * f);
            } else {
                let f = ta / oa;
                sy = 1.0 / f;
                oy = -(1.0 - f) / (2.0 * f);
            }
        }
    }
    if rot == 0 && sx == 1.0 && sy == 1.0 {
        return None;
    }
    Some([sx * r[0][0], sx * r[0][1], sx * r[0][2] + ox, sy * r[1][0], sy * r[1][1], sy * r[1][2] + oy])
}

fn esc(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

// весь файл; live — `niri msg -j outputs`, primary — главный монитор
pub fn kdl(s: &Json, live: &Json, primary: &str) -> String {
    let c = Config::from_json(s);
    let i = s.get("input");
    let m = i.get("mouse");
    let t = i.get("touchpad");
    let mut l: Vec<String> = Vec::new();
    let mut p = |x: &str| l.push(x.to_string());
    p("// генерируется шеллом (Настройки, Super+I) — правки вручную перезапишутся");
    p("input {");
    p("    keyboard {");
    p("        xkb {");
    let layouts: Vec<&str> = i.get("layouts").arr().iter().filter_map(|v| v.str()).collect();
    p(&format!("            layout \"{}\"", if layouts.is_empty() { "us".to_string() } else { layouts.join(",") }));
    if let Some(k) = i.get("switchKey").str().filter(|k| !k.is_empty()) {
        p(&format!("            options \"{k}\""));
    }
    p("        }");
    p(&format!("        repeat-delay {}", i.get("repeatDelay").num_or(600.0)));
    p(&format!("        repeat-rate {}", i.get("repeatRate").num_or(25.0)));
    if i.get("numlock").bool_or(false) {
        p("        numlock");
    }
    p("    }");
    p("    touchpad {");
    if t.get("off").bool_or(false) {
        p("        off");
    }
    if t.get("tap").bool_or(true) {
        p("        tap");
    }
    if t.get("naturalScroll").bool_or(true) {
        p("        natural-scroll");
    }
    if t.get("dwt").bool_or(true) {
        p("        dwt");
    }
    if t.get("disabledOnExternalMouse").bool_or(false) {
        p("        disabled-on-external-mouse");
    }
    if let Some(a) = t.get("accelSpeed").num().filter(|a| *a != 0.0) {
        p(&format!("        accel-speed {a:.2}"));
    }
    if let Some(cm) = t.get("clickMethod").str().filter(|v| !v.is_empty()) {
        p(&format!("        click-method \"{cm}\""));
    }
    if let Some(f) = t.get("scrollFactor").num().filter(|f| *f != 0.0 && *f != 1.0) {
        p(&format!("        scroll-factor {f:.2}"));
    }
    p("    }");
    p("    mouse {");
    p(&format!("        accel-speed {:.2}", m.get("accelSpeed").num_or(0.0)));
    p(&format!("        accel-profile \"{}\"", m.get("accelProfile").str_or("adaptive")));
    if m.get("naturalScroll").bool_or(false) {
        p("        natural-scroll");
    }
    if m.get("leftHanded").bool_or(false) {
        p("        left-handed");
    }
    if m.get("middleEmulation").bool_or(false) {
        p("        middle-emulation");
    }
    if let Some(f) = m.get("scrollFactor").num().filter(|f| *f != 0.0 && *f != 1.0) {
        p(&format!("        scroll-factor {f:.2}"));
    }
    p("    }");
    let tb = i.get("tablet");
    p("    tablet {");
    if tb.get("off").bool_or(false) {
        p("        off");
    }
    // планшетом управляет OpenTabletDriver — niri ничего не пересчитывает
    let otd = tb.get("otd").bool_or(false);
    let map_to = tb.get("mapTo").str().unwrap_or("");
    if !otd && !map_to.is_empty() && !live.get(map_to).is_null() {
        p(&format!("        map-to-output \"{map_to}\""));
    }
    if !otd {
        if tb.get("direct").bool_or(false) {
            if let Some(cm) = tablet_matrix(tb, live) {
                let v: Vec<String> = cm.iter().map(|x| format!("{x:.4}")).collect();
                p(&format!("        calibration-matrix {}", v.join(" ")));
            }
        } else if tb.get("rotation").num_or(0.0) as i64 == 180 {
            p("        left-handed");
        }
    }
    p("    }");
    if i.get("focusFollowsMouse").bool_or(false) {
        p("    focus-follows-mouse max-scroll-amount=\"0%\"");
    }
    p("}");

    // прозрачный терминал: размытие всего окна
    if c.transparency && s.get("blur").bool_or(true) && s.get("terminalOpacity").num_or(1.0) < 1.0 {
        for x in ["", "window-rule {", "    match app-id=\"^foot$\"", "    background-effect {", "        blur true", "    }", "}"] {
            p(x);
        }
    }

    // телефон на демонстрации экрана: на месте звонка/уведомлений зрители видят пустоту
    let mut hidden: Vec<&str> = Vec::new();
    if c.module_on("phoneCastHideCalls", true) {
        hidden.push("quickshell-call");
    }
    if c.module_on("phoneCastHideNotifs", true) {
        hidden.extend(["quickshell-notifications-phone", "quickshell-popup-phone"]);
    }
    if !hidden.is_empty() {
        p("");
        p("layer-rule {");
        for n in hidden {
            p(&format!("    match namespace=\"^{n}$\""));
        }
        p("    block-out-from \"screencast\"");
        p("}");
    }

    for x in ["", "environment {", "    QT_QPA_PLATFORMTHEME \"gtk3\"", "}"] {
        p(x);
    }

    let binds: Vec<&Json> = s
        .get("binds")
        .arr()
        .iter()
        .filter(|b| b.get("enabled").bool_or(true) && !b.get("key").str_or("").is_empty() && !b.get("action").str_or("").is_empty())
        .collect();
    if !binds.is_empty() {
        p("");
        p("binds {");
        for b in binds {
            let props = b.get("props").str_or("");
            let props = if props.is_empty() { String::new() } else { format!(" {props}") };
            p(&format!("    {}{} {{ {} }}", b.get("key").str_or(""), props, b.get("action").str_or("")));
        }
        p("}");
    }

    for a in s.get("autostart").arr() {
        let cmd = a.get("command").str_or("");
        if !a.get("enabled").bool_or(false) || cmd.is_empty() {
            continue;
        }
        p("");
        p(&format!("spawn-sh-at-startup \"{}\"", esc(&cmd)));
    }

    // подключённые — по порту, отключённые — по id (если известен)
    let saved = s.get("outputs");
    let mut outs = current(saved, live);
    for (k, o) in disconnected(saved, live) {
        let id = o.get("id").str_or("");
        let n = if id.is_empty() { k.clone() } else { id };
        if !outs.iter().any(|(on, oo)| oo.get("id").str() == Some(n.as_str()) || *on == n) {
            outs.push((n, o));
        }
    }
    for (name, o) in &outs {
        p("");
        p(&format!("output \"{}\" {{", name.replace('"', "\\\"")));
        if o.get("off").bool_or(false) {
            p("    off");
        }
        if let Some(mode) = o.get("mode").str().filter(|v| !v.is_empty()) {
            p(&format!("    mode \"{mode}\""));
        }
        p(&format!("    scale {:.2}", o.get("scale").num_or(1.0)));
        p(&format!("    transform \"{}\"", o.get("transform").str_or("normal")));
        p(&format!("    position x={} y={}", o.get("x").num_or(0.0).round(), o.get("y").num_or(0.0).round()));
        if o.get("vrr").bool_or(false) {
            p("    variable-refresh-rate");
        }
        if name == primary {
            p("    focus-at-startup");
        }
        p("}");
    }
    l.join("\n") + "\n"
}

// ── служба: пишет файл, когда настройки или мониторы поменялись

pub struct NiriConf {
    pub live: Json,
    // откат смены мониторов (Дисплей): прежние настройки и сколько секунд осталось подтвердить
    pub backup: Option<Json>,
    pub confirm_left: u32,
}

pub fn query_live() -> Json {
    Json::parse(&amane::output("niri msg -j outputs 2>/dev/null")).unwrap_or(Json::Obj(Vec::new()))
}

pub fn primary_of(c: &Config, live: &Json) -> String {
    let outs: Vec<(String, u32, u32)> = live
        .obj()
        .iter()
        .filter(|(_, o)| !o.get("logical").is_null())
        .map(|(n, o)| (n.clone(), o.get("logical").get("width").num_or(0.0) as u32, o.get("logical").get("height").num_or(0.0) as u32))
        .collect();
    c.primary(&outs)
}

// записать сейчас (если текст поменялся); без данных о мониторах не пишем — иначе их настройки пропадут
// REXILONE_NO_SERVICES=1 — проверка рядом с Quickshell: мониторы читаем, файлы не трогаем
fn read_only() -> bool {
    std::env::var_os("REXILONE_NO_SERVICES").is_some()
}

pub fn write_now() {
    if read_only() {
        return;
    }
    let live = NiriConf::read().live.clone();
    let raw = settings::load();
    if raw.get("outputs").obj().is_empty() && live.obj().is_empty() {
        return;
    }
    let c = Config::from_json(&raw);
    let text = kdl(&raw, &live, &primary_of(&c, &live));
    if fs::read_to_string(path()).ok().as_deref() != Some(text.as_str()) {
        let _ = fs::write(path(), text);
    }
}

impl Service for NiriConf {
    fn new() -> Self {
        NiriConf { live: Json::Obj(Vec::new()), backup: None, confirm_left: 0 }
    }

    fn listen() {
        let mut last_key = String::new();
        let mut last_raw = Json::Null;
        loop {
            let live = query_live();
            let key: Vec<String> = live.obj().iter().map(|(n, o)| format!("{n}={}", id_of(o))).collect();
            let key = key.join("|");
            if NiriConf::read().live != live {
                NiriConf::write().live = live.clone();
            }
            // первый запуск: текущие мониторы — в настройки
            let raw = settings::load();
            if !read_only() && raw.get("outputs").obj().is_empty() && !live.obj().is_empty() {
                settings::save_key("outputs", from_live(&live));
            }
            // поменялись настройки или набор мониторов — переписать
            if raw != last_raw || key != last_key {
                last_raw = raw;
                last_key = key;
                write_now();
            }
            // отсчёт подтверждения смены мониторов
            let left = NiriConf::read().confirm_left;
            if left > 0 {
                let mut w = NiriConf::write();
                w.confirm_left -= 1;
                if w.confirm_left == 0 {
                    if let Some(b) = w.backup.take() {
                        drop(w);
                        settings::save_key("outputs", b);
                    }
                }
            }
            thread::sleep(Duration::from_secs(1));
        }
    }
}

// применить мониторы с откатом через 15 с, если не подтвердить
pub fn apply_outputs(next: Json) {
    let raw = settings::load();
    let live = NiriConf::read().live.clone();
    let mut merged = Json::Obj(disconnected(raw.get("outputs"), &live));
    for (k, v) in next.obj() {
        merged.set(k, v.clone());
    }
    {
        let mut w = NiriConf::write();
        w.backup = Some(raw.get("outputs").clone());
        w.confirm_left = 15;
    }
    settings::save_key("outputs", merged);
}

pub fn confirm() {
    let mut w = NiriConf::write();
    w.backup = None;
    w.confirm_left = 0;
}

pub fn revert() {
    let b = {
        let mut w = NiriConf::write();
        w.confirm_left = 0;
        w.backup.take()
    };
    if let Some(b) = b {
        settings::save_key("outputs", b);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn live() -> Json {
        Json::parse(r#"{
          "DP-1":{"name":"DP-1","make":"Xiaomi Corporation","model":"Mi Monitor","serial":"5790010043153","modes":[{"width":1920,"height":1080,"refresh_rate":180000,"is_preferred":true},{"width":1920,"height":1080,"refresh_rate":60000,"is_preferred":false}],"current_mode":0,"vrr_enabled":true,"logical":{"x":900,"y":0,"width":1920,"height":1080,"scale":1.0,"transform":"Normal"}},
          "HDMI-A-2":{"name":"HDMI-A-2","make":"Samsung Electric Company","model":"SyncMaster","serial":"9CQA07687T","modes":[{"width":1440,"height":900,"refresh_rate":74984,"is_preferred":false}],"current_mode":0,"vrr_enabled":false,"logical":{"x":0,"y":0,"width":900,"height":1440,"scale":1.0,"transform":"_270"}}
        }"#).unwrap()
    }

    #[test]
    fn ids_and_modes() {
        let l = live();
        assert_eq!(id_of(l.get("DP-1")), "Xiaomi Corporation Mi Monitor 5790010043153");
        assert_eq!(mode_key(l.get("DP-1").get("modes").at(0)), "1920x1080@180.000");
        let o = from_live_one(l.get("HDMI-A-2"));
        assert_eq!(o.get("mode").str(), Some("1440x900@74.984"));
        assert_eq!(o.get("transform").str(), Some("_270"));
        assert_eq!(o.get("vrr").bool(), Some(false));
    }

    #[test]
    fn saved_settings_follow_monitor_to_another_port() {
        let l = live();
        let saved = Json::parse(r#"{"HDMI-A-1":{"id":"Samsung Electric Company SyncMaster 9CQA07687T","mode":"1440x900@74.984","scale":1,"transform":"270","x":0,"y":0}}"#).unwrap();
        let (k, s) = saved_for(&saved, &l, "HDMI-A-2").unwrap();
        assert_eq!(k, "HDMI-A-1");
        assert_eq!(s.get("transform").str(), Some("270"));
        // монитор в DP-1 не сохранён — берётся из niri
        assert!(saved_for(&saved, &l, "DP-1").is_none());
        assert!(disconnected(&saved, &l).is_empty());
    }

    #[test]
    fn generates_like_quickshell() {
        let s = Json::parse(r#"{
            "input":{"focusFollowsMouse":true,"layouts":["us","ru"],"mouse":{"accelProfile":"adaptive","accelSpeed":0,"leftHanded":false,"naturalScroll":false},
                     "numlock":true,"repeatDelay":600,"repeatRate":25,"switchKey":"grp:caps_toggle","tablet":{"otd":true,"rotation":180,"mapTo":"DP-1"},"touchpad":{"naturalScroll":true,"tap":true}},
            "outputs":{"DP-1":{"id":"Xiaomi Corporation Mi Monitor 5790010043153","mode":"1920x1080@180.000","off":false,"scale":1,"transform":"normal","vrr":true,"x":900,"y":0},
                       "HDMI-A-1":{"mode":"1440x900@74.984","off":false,"scale":1,"transform":"270","vrr":false,"x":0,"y":0}},
            "autostart":[{"command":"echo \"hi\"","enabled":true},{"command":"off","enabled":false}],
            "binds":[{"key":"Mod+Y","action":"spawn \"foot\";","enabled":true},{"key":"Mod+U","action":"x;","enabled":false}]
        }"#).unwrap();
        let out = kdl(&s, &live(), "DP-1");
        let want_parts = [
            "input {\n    keyboard {\n        xkb {\n            layout \"us,ru\"\n            options \"grp:caps_toggle\"\n        }\n        repeat-delay 600\n        repeat-rate 25\n        numlock\n    }",
            "    touchpad {\n        tap\n        natural-scroll\n        dwt\n    }\n    mouse {\n        accel-speed 0.00\n        accel-profile \"adaptive\"\n    }\n    tablet {\n    }\n    focus-follows-mouse max-scroll-amount=\"0%\"\n}",
            "layer-rule {\n    match namespace=\"^quickshell-call$\"",
            "environment {\n    QT_QPA_PLATFORMTHEME \"gtk3\"\n}",
            "binds {\n    Mod+Y { spawn \"foot\"; }\n}",
            "spawn-sh-at-startup \"echo \\\"hi\\\"\"",
            "output \"DP-1\" {\n    mode \"1920x1080@180.000\"\n    scale 1.00\n    transform \"normal\"\n    position x=900 y=0\n    variable-refresh-rate\n    focus-at-startup\n}",
            // HDMI-A-2 не сохранён — из состояния niri
            "output \"HDMI-A-2\" {\n    mode \"1440x900@74.984\"\n    scale 1.00\n    transform \"_270\"\n    position x=0 y=0\n}",
            // сохранённый, но отключённый — остаётся
            "output \"HDMI-A-1\" {",
        ];
        for w in want_parts {
            assert!(out.contains(w), "нет:\n{w}\n---\n{out}");
        }
        assert!(!out.contains("Mod+U"));
        assert!(!out.contains("spawn-sh-at-startup \"off\""));
        assert!(out.ends_with("}\n"));
    }

    #[test]
    fn tablet_rotation_and_aspect() {
        let l = live();
        // обычный планшет: только поворот на 180 — «левша»
        let s = Json::parse(r#"{"input":{"tablet":{"rotation":180,"mapTo":"DP-1"}}}"#).unwrap();
        let out = kdl(&s, &l, "");
        assert!(out.contains("    tablet {\n        map-to-output \"DP-1\"\n        left-handed\n    }"));
        // планшет-экран 16:10 на мониторе 16:9 — обрезка по высоте
        let tb = Json::parse(r#"{"direct":true,"keepAspect":true,"widthMm":216,"heightMm":135,"mapTo":"DP-1","rotation":0}"#).unwrap();
        let m = tablet_matrix(&tb, &l).unwrap();
        assert!((m[0] - 1.0).abs() < 1e-9);
        assert!(m[4] > 1.0 && m[5] < 0.0);
        let plain = Json::parse(r#"{"direct":true,"rotation":0}"#).unwrap();
        assert!(tablet_matrix(&plain, &l).is_none());
    }

    #[test]
    fn same_output_as_quickshell_wrote() {
        // если на машине есть файл Quickshell — сверка с ним (кроме первой строки-комментария)
        let f = settings::home().join(".config/niri/qs-settings.kdl");
        let (Ok(old), Some(raw)) = (fs::read_to_string(&f), fs::read_to_string(settings::path()).ok().and_then(|t| Json::parse(&t))) else { return };
        if !old.starts_with("// генерируется Quickshell") {
            return;
        }
        let live = query_live();
        if live.obj().is_empty() {
            return;
        }
        let c = Config::from_json(&raw);
        let new = kdl(&raw, &live, &primary_of(&c, &live));
        // блоки мониторов Quickshell пишет в порядке niri — сравниваем как множества блоков
        let blocks = |t: &str| {
            let mut v: Vec<String> = t.split("\n\n").skip(1).map(String::from).collect();
            v.sort();
            v
        };
        assert_eq!(blocks(&old), blocks(&new));
    }
}
