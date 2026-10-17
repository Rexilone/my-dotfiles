// Периферия: устройства и их настройки — клавиатура, мышь, тачпад, планшет, геймпады, принтеры и сканеры
// (PeripheralsPage.qml, PrintersPanel.qml). Настройки ввода пишутся в settings.json → niri (NiriConf)

use std::sync::Mutex;
use std::time::{Duration, Instant};

use amane::{Center, Column, End, Rectangle, Row, Service, Stack, Start, Weight, children};

use super::super::w::{self, Btn, Card, Slide, W, bx};
use super::super::show;
use super::{Out, set_tab, tab};
use crate::cmd;
use crate::devices::{self, Devices, Pad};
use crate::json::Json;
use crate::look::Tk;
use crate::niri::sh_quote;
use crate::niriconf::{NiriConf, output_aspect};
use crate::otd::{self, Tablet};
use crate::settings::{self, Settings};
use crate::ui::{self, ic};

const PAGE: usize = 10;

const TABS: [(&str, &str, u32); 6] = [
    ("keyboard", "Keyboard", 0xF030C),
    ("mouse", "Mouse", 0xF037D),
    ("touchpad", "Touchpad", 0xF0741),
    ("tablet", "Graphics tablet", 0xF03EB),
    ("gamepad", "Gamepads", 0xF0EB5),
    ("printers", "Printers & scanners", 0xF042A),
];

const KNOWN: [(&str, &str); 15] = [
    ("us", "English (US)"),
    ("ru", "Russian"),
    ("ua", "Ukrainian"),
    ("by", "Belarusian"),
    ("kz", "Kazakh"),
    ("de", "German"),
    ("fr", "French"),
    ("es", "Spanish"),
    ("it", "Italian"),
    ("pl", "Polish"),
    ("cz", "Czech"),
    ("tr", "Turkish"),
    ("gb", "English (UK)"),
    ("jp", "Japanese"),
    ("ge", "Georgian"),
];

fn label_of(code: &str) -> &str {
    KNOWN.iter().find(|k| k.0 == code).map(|k| k.1).unwrap_or(code)
}

fn inp() -> Json {
    Settings::read().raw.get("input").clone()
}

fn set_in(key: &str, v: Json) {
    settings::save_path(&["input", key], v);
}

fn set_sec(sec: &str, key: &str, v: Json) {
    settings::save_path(&["input", sec, key], v);
}

fn layouts() -> Vec<String> {
    inp().get("layouts").arr().iter().filter_map(|v| v.str().map(String::from)).collect()
}

fn device_desc(d: &Json) -> String {
    let mut p = vec![devices::bus_label(d).to_string()];
    if let Some(b) = d.get("battery").num() {
        p.push(format!("battery {b}%"));
    }
    p.join("   ·   ")
}

fn device_cards(t: &Tk, w: f32, list: &[Json], items: &mut Vec<W>) {
    for d in list {
        let name = d.get("name").str_or("");
        items.push(bx(Card::new(devices::kind_icon(d.get("kind").str().unwrap_or("")), &name, &device_desc(d)).id(&format!("dev:{}", d.get("id").str_or(""))).build(t, w)));
    }
}

pub fn page(t: &Tk, w: f32) -> Out {
    devices::need();
    let tb = tab(PAGE);
    // ушли со вкладки геймпадов — перестать читать
    if tb != "gamepad" && !Pad::read().node.is_empty() {
        std::thread::spawn(devices::test_stop);
    }
    let mut items: Vec<W> = Vec::new();
    let crumb = TABS.iter().find(|x| x.0 == tb).map(|x| t.t(x.1)).unwrap_or_default();
    match tb.as_str() {
        "keyboard" => keyboard(t, w, &mut items),
        "mouse" => mouse(t, w, &mut items),
        "touchpad" => touchpad(t, w, &mut items),
        "tablet" => tablet(t, w, &mut items),
        "gamepad" => gamepad(t, w, &mut items),
        "printers" => printers(t, w, &mut items),
        _ => home(t, w, &mut items),
    }
    let subtitle = if tb.is_empty() { "Keyboard, mouse, graphics tablet, gamepads, printers and scanners".to_string() } else { String::new() };
    Out { crumb, subtitle, items }
}

// ═════════ главная: плитки устройств и разделы
fn home(t: &Tk, w: f32, items: &mut Vec<W>) {
    let list = Devices::read().list.clone();
    let tw = w::width_for(4, w, 8.0);
    let mut tiles: Vec<W> = Vec::new();
    for d in &list {
        let kind = d.get("kind").str_or("");
        let id = format!("tile:{}", d.get("id").str_or(""));
        let h = w::hov(&id);
        let mut layers: Vec<W> = vec![bx(Rectangle::new().width(tw).height(112.0).padding(16.0).child(ui::icon(t, devices::kind_icon(&kind), t.icon + 9.0, t.p.fg)))];
        if let Some(b) = d.get("battery").num() {
            layers.push(bx(Rectangle::new().width(tw).height(112.0).padding(14.0).align_child(End, Start).child(w::raw(t, format!("{b}%"), t.fs - 2.0, if b <= 15.0 { t.p.urgent } else { t.p.dim }))));
        }
        layers.push(bx(Rectangle::new().width(tw).height(112.0).padding(amane::Padding { top: 0.0, right: 16.0, bottom: 14.0, left: 16.0 }).align_child(Start, End).child(
            Column::new(children![
                w::line(t, &t.t(&d.get("name").str_or("")), t.fs - 1.0, t.p.fg, tw - 32.0, false),
                w::line(t, &t.t(devices::bus_label(d)), t.fs - 3.0, t.p.dim, tw - 32.0, false)
            ])
            .gap(2.0),
        )));
        let r = Rectangle::new().width(tw).height(112.0).radius(10.0).fill(if h { t.p.surface_hi } else { t.p.surface }).child(Stack::new(layers));
        tiles.push(bx(w::clickable(r, &id, w::act(move || set_tab(PAGE, &kind)))));
    }
    // добавить устройство — через Bluetooth
    let ah = w::hov("tile:add");
    let fg = if ah { t.p.fg } else { t.p.dim };
    let add = Rectangle::new().width(tw).height(112.0).radius(10.0).border(1.0, if ah { t.p.line } else { t.p.surface_hi2 }).align_child(Center, Center).child(
        Column::new(children![w::raw(t, "+", t.icon + 9.0, fg), w::tx(t, "Add device", t.fs - 2.0, fg)]).gap(6.0).align(Center),
    );
    tiles.push(bx(w::clickable(add, "tile:add", w::act(|| show(4)))));
    items.push(bx(w::grid(tiles, 4, 8.0)));
    items.push(bx(w::gap(11.0)));

    let ls = layouts();
    let names = |k: &str| list.iter().filter(|d| d.get("kind").str() == Some(k)).map(|d| d.get("name").str_or("")).collect::<Vec<_>>();
    let (mice, pads, tabs) = (names("mouse"), names("gamepad"), names("tablet"));
    let has_touchpad = !names("touchpad").is_empty();
    for (key, label, icon) in TABS {
        let desc = match key {
            "keyboard" => format!("{}   ·   {}", ls.iter().map(|l| l.to_uppercase()).collect::<Vec<_>>().join(" · "), t.t("typing, layout switching")),
            "mouse" => if mice.is_empty() { t.t("Pointer speed, buttons, scrolling") } else { mice.join(", ") },
            "touchpad" => t.t("Taps, scrolling, right click"),
            "tablet" => tabs.first().cloned().unwrap_or_else(|| t.t("Not connected   ·   screen, orientation")),
            "gamepad" => if pads.is_empty() { t.t("None connected   ·   test buttons and sticks") } else { pads.join(", ") },
            _ => t.t("Add a printer, print a test page, scan documents"),
        };
        if key == "touchpad" && !has_touchpad {
            continue;
        }
        items.push(bx(Card::new(icon, label, &desc).click(move || set_tab(PAGE, key)).build(t, w)));
    }
}

// ═════════ клавиатура
fn keyboard(t: &Tk, w: f32, items: &mut Vec<W>) {
    device_cards(t, w, &Devices::read().of("keyboard"), items);
    items.push(bx(w::section(t, "Layouts", w)));
    let i = inp();
    let ls = layouts();
    let mut opts: Vec<(String, String)> = vec![(String::new(), t.t("+ Add layout"))];
    opts.extend(KNOWN.iter().filter(|k| !ls.iter().any(|l| l == k.0)).map(|k| (k.0.to_string(), t.t(k.1))));
    let ls2 = ls.clone();
    let dd = w::dropdown(t, "kb-add", &opts, "", 170.0, move |v| {
        if !v.is_empty() {
            let mut n: Vec<Json> = ls2.iter().map(|s| Json::Str(s.clone())).collect();
            n.push(Json::Str(v));
            set_in("layouts", Json::Arr(n));
        }
    });
    let (dw, _) = w::wh(&dd);
    let head = Row::new(children![
        Rectangle::new().width(22.0).height(40.0).align_child(Center, Center).child(ui::icon(t, 0xF030C, t.icon + 3.0, t.p.fg)),
        Column::new(children![w::tx(t, "Layouts", t.fs, t.p.fg), w::tx(t, "Order matters: the first one is the default", t.fs - 2.0, t.p.dim)]).gap(2.0).width(w - 36.0 - 38.0 - dw - 16.0),
        dd
    ])
    .gap(16.0);
    let mut chips: Vec<W> = Vec::new();
    for (idx, l) in ls.iter().enumerate() {
        let mut parts: Vec<W> = vec![bx(w::raw(t, l.to_uppercase(), t.fs - 2.0, t.p.fg).weight(Weight::Bold)), bx(w::tx(t, label_of(l), t.fs - 2.0, t.p.muted))];
        if ls.len() > 1 {
            let id = format!("kb-rm:{l}");
            let col = if w::hov(&id) { t.p.urgent } else { t.p.dim };
            let rest: Vec<Json> = ls.iter().enumerate().filter(|(j, _)| *j != idx).map(|(_, s)| Json::Str(s.clone())).collect();
            let x = Rectangle::new().width(14.0).height(20.0).align_child(Center, Center).child(ui::icon(t, ic::CLOSE, t.fs - 2.0, col));
            parts.push(bx(w::clickable(x, &id, w::act(move || set_in("layouts", Json::Arr(rest.clone()))))));
        }
        let row = Row::new(parts).gap(8.0).align(Center);
        let (rw, _) = w::wh(&row);
        chips.push(bx(Rectangle::new().width(rw + 20.0).height(30.0).radius(8.0).fill(t.p.surface_hi).align_child(Center, Center).child(row)));
    }
    let chip_row = Row::new(chips).gap(6.0);
    let body = Column::new(children![head, Rectangle::new().width(w - 36.0).height(30.0).padding(amane::Padding { top: 0.0, right: 0.0, bottom: 0.0, left: 38.0 }).child(chip_row)]).gap(10.0);
    let (_, bh) = w::wh(&body);
    items.push(bx(Rectangle::new().width(w).height(bh + 28.0).radius(10.0).fill(t.p.surface).padding(amane::Padding { top: 14.0, right: 18.0, bottom: 14.0, left: 18.0 }).child(body)));
    let sk: Vec<(String, String)> = [
        ("grp:caps_toggle", "Caps Lock"),
        ("grp:alt_shift_toggle", "Alt + Shift"),
        ("grp:ctrl_shift_toggle", "Ctrl + Shift"),
        ("grp:win_space_toggle", "Super + Space"),
        ("grp:alt_space_toggle", "Alt + Space"),
    ]
    .iter()
    .map(|(a, b)| (a.to_string(), b.to_string()))
    .collect();
    items.push(bx(Card::new(0xF0CB6, "Switch layout with", "")
        .ctrl(w::dropdown(t, "kb-switch", &sk, &i.get("switchKey").str_or("grp:caps_toggle"), 190.0, |v| set_in("switchKey", Json::Str(v))))
        .build(t, w)));
    items.push(bx(w::section(t, "Typing", w)));
    items.push(bx(Card::new(0xF051B, "Repeat delay", "How long to hold a key before it repeats")
        .ctrl(Slide::new(i.get("repeatDelay").num_or(600.0), 150.0, 1000.0, 10.0).suffix(" ms").build(t, "kb-delay", |v| set_in("repeatDelay", Json::Num(v.round()))))
        .build(t, w)));
    items.push(bx(Card::new(0xF04C5, "Repeat rate", "Characters per second while holding a key")
        .ctrl(Slide::new(i.get("repeatRate").num_or(25.0), 10.0, 60.0, 1.0).suffix("/s").build(t, "kb-rate", |v| set_in("repeatRate", Json::Num(v.round()))))
        .build(t, w)));
    items.push(bx(Card::new(0xF03A0, "Num Lock on startup", "").ctrl(w::switch(t, "kb-num", i.get("numlock").bool_or(true), |v| set_in("numlock", Json::Bool(v)))).build(t, w)));
    items.push(bx(Card::new(0xF0313, "Keyboard shortcuts", "Change or add your own key bindings").click(|| show(11)).build(t, w)));
}

fn speed(t: &Tk, id: &str, v: f64, f: impl Fn(f64) + Clone + 'static) -> amane::Row {
    Slide::new(v, -1.0, 1.0, 0.05).display(v * 100.0).suffix("%").build(t, id, move |x| f((x * 100.0).round() / 100.0))
}

// ═════════ мышь
fn mouse(t: &Tk, w: f32, items: &mut Vec<W>) {
    device_cards(t, w, &Devices::read().of("mouse"), items);
    let i = inp();
    let m = i.get("mouse").clone();
    let sm = |k: &'static str| move |v: bool| set_sec("mouse", k, Json::Bool(v));
    items.push(bx(w::section(t, "Pointer", w)));
    items.push(bx(Card::new(0xF037D, "Pointer speed", "").ctrl(speed(t, "m-speed", m.get("accelSpeed").num_or(0.0), |v| set_sec("mouse", "accelSpeed", Json::Num(v)))).build(t, w)));
    items.push(bx(Card::new(0xF0E2E, "Acceleration", "Flat is best for games — speed doesn't depend on how fast you move")
        .ctrl(w::choice(t, "m-accel", &[("adaptive", "Adaptive"), ("flat", "Flat")], &m.get("accelProfile").str_or("adaptive"), |v| set_sec("mouse", "accelProfile", Json::Str(v))))
        .build(t, w)));
    items.push(bx(Card::new(0xF0A9D, "Left-handed", "Swap left and right buttons").ctrl(w::switch(t, "m-left", m.get("leftHanded").bool_or(false), sm("leftHanded"))).build(t, w)));
    items.push(bx(Card::new(0xF0C3E, "Focus follows mouse", "Focus windows by hovering them")
        .ctrl(w::switch(t, "m-ffm", i.get("focusFollowsMouse").bool_or(true), |v| set_in("focusFollowsMouse", Json::Bool(v))))
        .build(t, w)));
    items.push(bx(w::section(t, "Scrolling and buttons", w)));
    items.push(bx(Card::new(0xF0E8A, "Natural scrolling", "Content moves in the direction of the wheel").ctrl(w::switch(t, "m-nat", m.get("naturalScroll").bool_or(false), sm("naturalScroll"))).build(t, w)));
    let sf = m.get("scrollFactor").num_or(1.0);
    items.push(bx(Card::new(0xF0D27, "Scroll speed", "How far one wheel step scrolls")
        .ctrl(Slide::new(sf, 0.2, 3.0, 0.1).display(sf * 100.0).suffix("%").build(t, "m-scroll", |v| set_sec("mouse", "scrollFactor", Json::Num((v * 10.0).round() / 10.0))))
        .build(t, w)));
    items.push(bx(Card::new(0xF037D, "Middle click with both buttons", "Pressing left and right together acts as a middle click")
        .id("m-mid")
        .ctrl(w::switch(t, "m-mid", m.get("middleEmulation").bool_or(false), sm("middleEmulation")))
        .build(t, w)));
}

// ═════════ тачпад
fn touchpad(t: &Tk, w: f32, items: &mut Vec<W>) {
    device_cards(t, w, &Devices::read().of("touchpad"), items);
    let p = inp().get("touchpad").clone();
    let sw = |id: &'static str, k: &'static str, def: bool| w::switch(t, id, p.get(k).bool_or(def), move |v| set_sec("touchpad", k, Json::Bool(v)));
    items.push(bx(Card::new(0xF0741, "Touchpad", "Turn it off completely").ctrl(w::switch(t, "tp-on", !p.get("off").bool_or(false), |v| set_sec("touchpad", "off", Json::Bool(!v)))).build(t, w)));
    items.push(bx(Card::new(0xF0741, "Tap to click", "").ctrl(sw("tp-tap", "tap", true)).build(t, w)));
    items.push(bx(Card::new(0xF0E8A, "Natural scrolling", "").ctrl(sw("tp-nat", "naturalScroll", true)).build(t, w)));
    items.push(bx(Card::new(0xF030C, "Disable while typing", "").ctrl(sw("tp-dwt", "dwt", true)).build(t, w)));
    items.push(bx(Card::new(0xF037D, "Disable when a mouse is connected", "").ctrl(sw("tp-ext", "disabledOnExternalMouse", false)).build(t, w)));
    items.push(bx(Card::new(0xF037D, "Pointer speed", "").id("tp-speed").ctrl(speed(t, "tp-speed", p.get("accelSpeed").num_or(0.0), |v| set_sec("touchpad", "accelSpeed", Json::Num(v)))).build(t, w)));
    items.push(bx(Card::new(0xF0741, "Right click", "Bottom-right corner, or press with two fingers")
        .ctrl(w::choice(t, "tp-click", &[("button-areas", "Corner"), ("clickfinger", "Two fingers")], &p.get("clickMethod").str_or("button-areas"), |v| {
            set_sec("touchpad", "clickMethod", Json::Str(v))
        }))
        .build(t, w)));
}

// ═════════ графический планшет
fn tablet(t: &Tk, w: f32, items: &mut Vec<W>) {
    if Tablet::read().active() {
        tablet_otd(t, w, items);
    } else {
        tablet_niri(t, w, items);
    }
}

// перетаскивание области: начальная точка и значения на время жеста
fn drag() -> &'static Mutex<Option<(f32, f32, [f64; 4])>> {
    static D: Mutex<Option<(f32, f32, [f64; 4])>> = Mutex::new(None);
    &D
}
fn live_area() -> &'static Mutex<Option<[f64; 4]>> {
    static A: Mutex<Option<[f64; 4]>> = Mutex::new(None);
    &A
}

fn commit() {
    *drag().lock().unwrap() = None;
    if let Some([aw, ah, ax, ay]) = live_area().lock().unwrap().take() {
        otd::set_area(aw, ah, ax, ay);
    }
}

fn tablet_otd(t: &Tk, w: f32, items: &mut Vec<W>) {
    let tb = Tablet::read();
    let (mw, mh, lock, aspect) = (tb.max_w(), tb.max_h(), tb.lock(), tb.display_aspect());
    let a = tb.area().clone();
    let cur = [a.get("Width").num_or(mw), a.get("Height").num_or(mh), a.get("X").num_or(mw / 2.0), a.get("Y").num_or(mh / 2.0)];
    let [aw, ah, ax, ay] = live_area().lock().unwrap().unwrap_or(cur);
    let (name, running, screen, rot) = (tb.name(), tb.running, tb.screen(), tb.rotation());
    let displays = tb.displays.clone();
    drop(tb);

    let pw = (w - 36.0).min((300.0 * mw / mh) as f32);
    let k = pw as f64 / mw;
    let ph = (pw as f64 * mh / mw).round() as f32;
    let mut layers: Vec<W> = Vec::new();
    // сетка 1 см
    let mut x = 10.0;
    while x < mw {
        let px = (x * k) as f32;
        if px < pw - 2.0 {
            layers.push(bx(Rectangle::new().width(1.0).height(ph).fill(t.p.surface_hi2).translate(px, 0.0)));
        }
        x += 10.0;
    }
    let (rw, rh) = ((aw * k) as f32, (ah * k) as f32);
    let (rx, ry) = ((ax * k) as f32 - rw / 2.0, (ay * k) as f32 - rh / 2.0);
    let dragging = drag().lock().unwrap().is_some();
    let hv = w::hov("otd-area");
    let fill = crate::theme::alpha(t.p.accent, if hv || dragging { 0.2 } else { 0.12 });
    let label = format!("↑ {}", if screen.is_empty() { t.t("all screens") } else { screen.clone() });
    let area = Rectangle::new()
        .width(rw)
        .height(rh)
        .radius(6.0)
        .fill(fill)
        .border(2.0, t.p.accent)
        .rotate(rot as f32)
        .translate(rx, ry)
        .align_child(Center, Center)
        .cursor(amane::Grab)
        .on_drag(move |pt| {
            let mut d = drag().lock().unwrap();
            let Some((gx, gy, s)) = *d else {
                *d = Some((pt.x, pt.y, [aw, ah, ax, ay]));
                return;
            };
            let nx = (s[2] + (pt.x - gx) as f64 / k).clamp(s[0] / 2.0, mw - s[0] / 2.0);
            let ny = (s[3] + (pt.y - gy) as f64 / k).clamp(s[1] / 2.0, mh - s[1] / 2.0);
            *live_area().lock().unwrap() = Some([s[0], s[1], nx, ny]);
            amane::request_frame();
        })
        .on_click(|_| commit())
        .child(w::raw(t, label, t.fs - 1.0, t.p.accent).weight(Weight::Bold));
    layers.push(bx(w::track(area, "otd-area")));
    // потянуть за угол — размер от центра
    let handle = Rectangle::new()
        .width(14.0)
        .height(14.0)
        .radius(7.0)
        .fill(t.p.accent)
        .border(2.0, t.p.surface_hi)
        .translate(rx + rw - 8.0, ry + rh - 8.0)
        .cursor(amane::Grab)
        .on_drag(move |pt| {
            let mut d = drag().lock().unwrap();
            let Some((gx, gy, s)) = *d else {
                *d = Some((pt.x, pt.y, [aw, ah, ax, ay]));
                return;
            };
            let mut nw = s[0] + 2.0 * (pt.x - gx) as f64 / k;
            let mut nh = s[1] + 2.0 * (pt.y - gy) as f64 / k;
            if lock {
                nh = nw / aspect;
            }
            nw = nw.min(2.0 * s[2].min(mw - s[2])).max(10.0);
            nh = nh.min(2.0 * s[3].min(mh - s[3])).max(10.0);
            if lock {
                nw = nw.min(nh * aspect);
            }
            *live_area().lock().unwrap() = Some([nw, nh, s[2], s[3]]);
            amane::request_frame();
        })
        .on_click(|_| commit());
    layers.push(bx(handle));
    let pad = Rectangle::new().width(pw).height(ph).radius(10.0).fill(t.p.surface_hi).border(1.0, t.p.line).child(Stack::new(layers));

    let mm = t.tr("mm", "мм");
    let mut btm: Vec<W> = vec![bx(Rectangle::new().width(w - 36.0 - 4.0 * 66.0).height(32.0).align_child(Start, Center).child(w::raw(
        t,
        format!("{aw:.1} × {ah:.1} {mm}   ·   {} {mw} × {mh}", t.t("of")),
        t.fs - 2.0,
        t.p.muted,
    )))];
    for (f, l) in [(1.0, "Full"), (0.75, "3/4"), (0.5, "1/2"), (1.0 / 3.0, "1/3")] {
        btm.push(bx(Rectangle::new().width(60.0).height(32.0).align_child(End, Center).child(Btn::new(l).build(t, &format!("otd-p{l}"), move || otd::preset(f)))));
    }
    let status = format!("OpenTabletDriver   ·   {}", t.t(if running { "running" } else { "not running" }));
    let card = Column::new(children![
        Row::new(children![
            Rectangle::new().width((w - 36.0) / 2.0).height(24.0).child(w::raw(t, name, t.fs + 1.0, t.p.fg).weight(Weight::Bold)),
            Rectangle::new().width((w - 36.0) / 2.0).height(24.0).align_child(End, Center).child(w::raw(t, status, t.fs - 2.0, if running { t.p.dim } else { t.p.urgent }))
        ]),
        Rectangle::new().width(w - 36.0).height(ph).align_child(Center, Start).child(pad),
        Row::new(btm).gap(6.0)
    ])
    .gap(10.0);
    let (_, chh) = w::wh(&card);
    items.push(bx(Rectangle::new().width(w).height(chh + 28.0).radius(10.0).fill(t.p.surface).padding(amane::Padding { top: 14.0, right: 18.0, bottom: 14.0, left: 18.0 }).child(card)));

    items.push(bx(w::section(t, "Mapping", w)));
    let mut opts: Vec<(String, String)> = vec![(String::new(), t.t("All monitors"))];
    opts.extend(displays.iter().filter(|d| d.index > 0).map(|d| (d.name.clone(), format!("{}  ·  {}×{}", d.name, d.w, d.h))));
    items.push(bx(Card::new(0xF0379, "Screen", "Which monitor the tablet draws on").ctrl(w::dropdown(t, "otd-screen", &opts, &screen, 220.0, |v| otd::set_screen(&v))).build(t, w)));
    items.push(bx(Card::new(0xF0A9D, "Orientation", "Left-handed turns the tablet upside down; 90° for a portrait monitor")
        .ctrl(w::choice(t, "otd-rot", &[("0", "Normal"), ("180", "Left-handed"), ("90", "90°"), ("270", "270°")], &rot.to_string(), |v| otd::set_rotation(v.parse().unwrap_or(0))))
        .build(t, w)));
    items.push(bx(Card::new(0xF0E2E, "Keep proportions", "Area follows the screen's shape, so a circle on the tablet is a circle on the screen")
        .ctrl(w::switch(t, "otd-lock", lock, move |v| {
            otd::set_lock(v);
            if v {
                // подогнать текущую область под пропорции экрана
                let (nw, nh) = otd::fit(aw, ah, aspect);
                otd::set_area(nw, nh, ax, ay);
            }
        }))
        .build(t, w)));
    items.push(bx(Card::new(0xF03EB, "OpenTabletDriver", "Pen buttons, pressure curve and filters — in the driver's own app")
        .ctrl(Btn::new("Open").build(t, "otd-gui", || amane::spawn("setsid -f otd-gui >/dev/null 2>&1")))
        .build(t, w)));
}

// какая часть планшета используется (как tablet_matrix), доли 0..1
pub fn used_area(tb: &Json, dev: Option<&Json>, direct: bool, live: &Json) -> [f64; 4] {
    let dw = dev.and_then(|d| d.get("widthMm").num()).or(tb.get("widthMm").num()).unwrap_or(0.0);
    let dh = dev.and_then(|d| d.get("heightMm").num()).or(tb.get("heightMm").num()).unwrap_or(0.0);
    if !direct || !tb.get("keepAspect").bool_or(false) || dw == 0.0 || dh == 0.0 {
        return [0.0, 0.0, 1.0, 1.0];
    }
    let rot = tb.get("rotation").num_or(0.0) as i64;
    let side = rot == 90 || rot == 270;
    let ta = if side { dh / dw } else { dw / dh };
    let oa = output_aspect(live, tb.get("mapTo").str().unwrap_or(""));
    if oa == 0.0 {
        return [0.0, 0.0, 1.0, 1.0];
    }
    let (mut fw, mut fh) = (1.0, 1.0);
    if ta > oa {
        if side { fh = oa / ta } else { fw = oa / ta }
    } else if side {
        fw = ta / oa
    } else {
        fh = ta / oa
    }
    [(1.0 - fw) / 2.0, (1.0 - fh) / 2.0, fw, fh]
}

fn tablet_niri(t: &Tk, w: f32, items: &mut Vec<W>) {
    let dev = Devices::read().of("tablet").into_iter().next();
    let tb = inp().get("tablet").clone();
    let live = NiriConf::read().live.clone();
    let direct = dev.as_ref().map(|d| d.get("direct").bool_or(false)).unwrap_or(tb.get("direct").bool_or(false));
    let a = used_area(&tb, dev.as_ref(), direct, &live);
    // запомнить размер и тип планшета: нужны для конфига, даже если планшет отключат
    let d2 = dev.clone();
    let set = move |k: &str, v: Json| {
        if let Some(d) = &d2 {
            if let Some(wm) = d.get("widthMm").num() {
                set_sec("tablet", "widthMm", Json::Num(wm));
                set_sec("tablet", "heightMm", Json::Num(d.get("heightMm").num_or(0.0)));
            }
            set_sec("tablet", "direct", Json::Bool(d.get("direct").bool_or(false)));
        }
        set_sec("tablet", k, v);
    };
    match &dev {
        None => items.push(bx(Card::new(0xF03EB, "No graphics tablet connected", "Wacom, Huion, XP-Pen and other tablets work out of the box. Settings below apply when one is connected").build(t, w))),
        Some(d) => {
            let ratio = (d.get("widthMm").num_or(16.0) / d.get("heightMm").num_or(10.0)) as f32;
            let (bw, bh) = (220.0f32.min(164.0 * ratio), 220.0f32.min(164.0 * ratio) / ratio);
            let (iw, ih) = (bw - 16.0, bh - 16.0);
            let map = tb.get("mapTo").str_or("");
            let used = Rectangle::new()
                .width(iw * a[2] as f32)
                .height(ih * a[3] as f32)
                .radius(4.0)
                .fill(crate::theme::alpha(t.p.accent, 0.12))
                .border(1.5, t.p.accent)
                .translate(8.0 + iw * a[0] as f32, 8.0 + ih * a[1] as f32)
                .align_child(Center, Center)
                .child(w::raw(t, format!("↑ {}", if map.is_empty() { t.t("all screens") } else { map }), t.fs - 3.0, t.p.accent));
            let body = Rectangle::new().width(bw).height(bh).radius(10.0).fill(t.p.surface_hi).border(1.0, t.p.line).child(Stack::new(children![used]));
            let tw = w - 36.0 - 220.0 - 24.0;
            let mut info: Vec<W> = vec![
                bx(w::line(t, &d.get("name").str_or(""), t.fs + 1.0, t.p.fg, tw, true)),
                bx(w::line(t, &[d.get("model").str_or(""), t.t(devices::bus_label(d))].iter().filter(|x| !x.is_empty()).cloned().collect::<Vec<_>>().join("   ·   "), t.fs - 2.0, t.p.dim, tw, false)),
            ];
            if let Some(wm) = d.get("widthMm").num() {
                let hm = d.get("heightMm").num_or(0.0);
                let full = format!("{} × {} mm", wm.round(), hm.round());
                let s = if a[2] == 1.0 && a[3] == 1.0 {
                    format!("{}: {full} ({})", t.t("Active area"), t.t("whole tablet"))
                } else {
                    format!("{}: {} × {} mm {} {full}", t.t("Active area"), (wm * a[2]).round(), (hm * a[3]).round(), t.t("of"))
                };
                info.push(bx(w::gap(8.0)));
                info.push(bx(w::para(t, &s, t.fs - 1.0, t.p.muted, tw)));
            }
            info.push(bx(w::para(t, &t.t("Pen buttons: lower — right click, upper — middle click"), t.fs - 2.0, t.p.dim, tw)));
            items.push(bx(Rectangle::new().width(w).height(200.0).radius(10.0).fill(t.p.surface).padding(18.0).child(
                Row::new(children![Rectangle::new().width(220.0).height(164.0).align_child(Center, Center).child(body), Column::new(info).gap(4.0)]).gap(24.0).height(164.0).align(Center),
            )));
        }
    }
    items.push(bx(w::section(t, "Mapping", w)));
    let mut opts: Vec<(String, String)> = vec![(String::new(), t.t("All monitors"))];
    let mut names: Vec<(String, String)> = live.obj().iter().map(|(n, o)| (n.clone(), format!("{n}  ·  {}", o.get("model").str_or("")))).collect();
    names.sort();
    opts.extend(names);
    let s1 = set.clone();
    items.push(bx(Card::new(0xF0379, "Screen", "Which monitor the tablet draws on").ctrl(w::dropdown(t, "tab-map", &opts, &tb.get("mapTo").str_or(""), 200.0, move |v| s1("mapTo", Json::Str(v)))).build(t, w)));
    let r = tb.get("rotation").num_or(0.0) as i64;
    let cur = if direct || r == 180 { r } else { 0 };
    let opts: &[(&str, &str)] = if direct { &[("0", "Normal"), ("180", "Left-handed"), ("90", "90°"), ("270", "270°")] } else { &[("0", "Normal"), ("180", "Left-handed")] };
    let s2 = set.clone();
    items.push(bx(Card::new(0xF0A9D, "Orientation", if direct { "Left-handed turns the tablet upside down; 90° for a portrait monitor" } else { "Left-handed turns the tablet upside down" })
        .ctrl(w::choice(t, "tab-rot", opts, &cur.to_string(), move |v| s2("rotation", Json::Num(v.parse().unwrap_or(0.0)))))
        .build(t, w)));
    if direct {
        let s3 = set.clone();
        items.push(bx(Card::new(0xF0E2E, "Keep proportions", "Use part of the tablet so a circle on it is a circle on the screen")
            .ctrl(w::switch(t, "tab-aspect", tb.get("keepAspect").bool_or(false), move |v| s3("keepAspect", Json::Bool(v))))
            .build(t, w)));
    }
    if dev.is_some() && !direct {
        items.push(bx(w::para(t, &t.t("Rotation by 90° and keeping proportions work only for pen displays: niri passes them to libinput, which ignores them for regular tablets."), t.fs - 2.0, t.p.dim, w)));
    }
    items.push(bx(Card::new(0xF03EB, "Tablet", "Turn the pen input off completely").ctrl(w::switch(t, "tab-off", !tb.get("off").bool_or(false), move |v| set("off", Json::Bool(!v)))).build(t, w)));
}

// ═════════ геймпады
fn gamepad(t: &Tk, w: f32, items: &mut Vec<W>) {
    let pads = Devices::read().of("gamepad");
    let testing = Pad::read().node.clone();
    // геймпад отключили — перестать
    if !testing.is_empty() && !pads.iter().any(|g| g.get("js").arr().iter().any(|j| j.str().is_some_and(|s| s.ends_with(&testing)))) {
        std::thread::spawn(devices::test_stop);
    }
    if pads.is_empty() {
        items.push(bx(Card::new(0xF0EB5, "No gamepads connected", "Plug in by USB or pair over Bluetooth (hold the pairing button on the controller)")
            .ctrl(Btn::new("Bluetooth").build(t, "gp-bt", || show(4)))
            .build(t, w)));
    }
    for g in &pads {
        let node = g.get("js").at(0).str_or("");
        let short = node.rsplit('/').next().unwrap_or("").to_string();
        let (gname, gdesc, gid) = (g.get("name").str_or(""), device_desc(g), format!("gp:{node}"));
        let mut card = Card::new(0xF0EB5, &gname, &gdesc).id(&gid);
        if !node.is_empty() {
            let on = testing == short;
            let n2 = node.clone();
            card = card.ctrl(Btn::new(if on { "Stop" } else { "Test" }).primary_if(!on).build(t, &format!("gp-test:{node}"), move || {
                if on { devices::test_stop() } else { devices::test_start(&n2) }
            }));
        }
        items.push(bx(card.build(t, w)));
    }
    if !testing.is_empty() {
        let p = Pad::read();
        let (axes, buttons) = (p.axes.clone(), p.buttons.clone());
        drop(p);
        let iw = w - 36.0;
        let mut btns: Vec<W> = Vec::new();
        for (i, on) in buttons.iter().enumerate() {
            btns.push(bx(Rectangle::new()
                .width(34.0)
                .height(34.0)
                .radius(17.0)
                .fill(if *on { t.p.accent } else { t.p.surface_hi })
                .border(1.0, t.p.surface_hi2)
                .align_child(Center, Center)
                .child(w::raw(t, i.to_string(), t.fs - 2.0, if *on { t.p.bg } else { t.p.dim }).weight(Weight::Bold))));
        }
        let per = ((iw + 6.0) / 40.0).floor().max(1.0) as usize;
        let cw = (iw - 12.0) / 2.0;
        let mut ax: Vec<W> = Vec::new();
        for (i, v) in axes.iter().enumerate() {
            let bw = cw - 58.0;
            let v = v.clamp(-1.0, 1.0);
            let fx = if v < 0.0 { bw / 2.0 * (1.0 + v) } else { bw / 2.0 };
            let bar = Rectangle::new().width(bw).height(8.0).radius(4.0).fill(t.p.surface_hi2).child(Stack::new(children![
                Rectangle::new().width(bw / 2.0 * v.abs()).height(8.0).radius(4.0).fill(t.p.accent).translate(fx, 0.0),
                Rectangle::new().width(2.0).height(8.0).fill(t.p.line).translate(bw / 2.0 - 1.0, 0.0)
            ]));
            ax.push(bx(Row::new(children![Rectangle::new().width(48.0).height(16.0).child(w::raw(t, format!("Axis {i}"), t.fs - 2.0, t.p.dim)), bar]).gap(10.0).width(cw).align(Center)));
        }
        let body = Column::new(children![w::tx(t, "Press buttons and move the sticks", t.fs - 1.0, t.p.muted), w::grid(btns, per, 6.0), w::grid(ax, 2, 12.0)]).gap(14.0);
        let (_, bh) = w::wh(&body);
        items.push(bx(Rectangle::new().width(w).height(bh + 32.0).radius(10.0).fill(t.p.surface).padding(amane::Padding { top: 16.0, right: 18.0, bottom: 16.0, left: 18.0 }).child(body)));
        amane::request_frame();
    }
    items.push(bx(w::gap(8.0)));
    items.push(bx(Card::new(0xF04D3, "Games in Steam", "Button layouts per game are set in Steam → Settings → Controller").build(t, w)));
}

// ═════════ принтеры и сканеры
const PRINTERS: &str = r#"
echo '@default'; lpstat -d 2>/dev/null
echo '@printers'; LANG=C lpstat -p 2>/dev/null
echo '@devices'; LANG=C lpstat -v 2>/dev/null
echo '@jobs'; LANG=C lpstat -o 2>/dev/null
echo '@sane'; command -v scanimage >/dev/null && echo yes
echo '@simplescan'; command -v simple-scan >/dev/null && echo yes
"#;
const SCANNERS: &str = "scanimage -f '%d|%v %m%n' 2>/dev/null";

#[derive(Debug, PartialEq)]
pub struct Printer {
    pub name: String,
    pub state: String,
    pub device: String,
    pub default: bool,
}

#[derive(Debug, PartialEq)]
pub struct Job {
    pub id: String,
    pub printer: String,
    pub user: String,
    pub size: u64,
}

pub fn parse_printers(text: &str) -> (Vec<Printer>, Vec<Job>, bool, bool) {
    let mut sec: Vec<(String, Vec<String>)> = Vec::new();
    for l in text.lines() {
        if let Some(n) = l.strip_prefix('@') {
            sec.push((n.to_string(), Vec::new()));
        } else if !l.trim().is_empty() {
            if let Some(s) = sec.last_mut() {
                s.1.push(l.to_string());
            }
        }
    }
    let get = |k: &str| sec.iter().find(|s| s.0 == k).map(|s| s.1.clone()).unwrap_or_default();
    let def = get("default").first().and_then(|l| l.split_once(": ").map(|x| x.1.trim().to_string())).unwrap_or_default();
    let devices: Vec<(String, String)> = get("devices")
        .iter()
        .filter_map(|l| l.strip_prefix("device for ").and_then(|r| r.split_once(": ")).map(|(a, b)| (a.to_string(), b.to_string())))
        .collect();
    let printers = get("printers")
        .iter()
        .filter_map(|l| {
            let r = l.strip_prefix("printer ")?;
            let (name, rest) = r.split_once(' ').unwrap_or((r, ""));
            let rest = rest.strip_prefix("is ").unwrap_or(rest);
            let state = ["idle", "now printing", "disabled"].iter().find(|s| rest.starts_with(**s)).map(|s| s.to_string()).unwrap_or_else(|| "unknown".into());
            Some(Printer {
                name: name.to_string(),
                state,
                device: devices.iter().find(|d| d.0 == name).map(|d| d.1.clone()).unwrap_or_default(),
                default: name == def,
            })
        })
        .collect();
    let jobs = get("jobs")
        .iter()
        .filter_map(|l| {
            let p: Vec<&str> = l.split_whitespace().collect();
            let (pr, _) = p.first()?.rsplit_once('-')?;
            Some(Job { id: p[0].to_string(), printer: pr.to_string(), user: p.get(1)?.to_string(), size: p.get(2)?.parse().ok()? })
        })
        .collect();
    (printers, jobs, !get("sane").is_empty(), !get("simplescan").is_empty())
}

// опрос раз в 4 с, пока вкладка открыта
fn poll() {
    static LAST: Mutex<Option<Instant>> = Mutex::new(None);
    let mut l = LAST.lock().unwrap();
    if l.is_none_or(|i| i.elapsed() > Duration::from_secs(4)) {
        *l = Some(Instant::now());
        cmd::refresh("printers", PRINTERS);
    }
}

fn run(c: String) {
    std::thread::spawn(move || {
        amane::output(&c);
        std::thread::sleep(Duration::from_millis(1200));
        cmd::refresh("printers", PRINTERS);
    });
}

fn printers(t: &Tk, w: f32, items: &mut Vec<W>) {
    poll();
    let out = cmd::get("printers", PRINTERS);
    let loading = out.is_none();
    let (printers, jobs, sane, simple) = parse_printers(&out.unwrap_or_default());
    items.push(bx(Row::new(children![
        w::section(t, "Printers", w - 170.0),
        Rectangle::new().width(170.0).height(54.0).align_child(End, End).child(Btn::new("Add a printer").icon('+' as u32).primary().build(t, "pr-add", || run("setsid -f system-config-printer >/dev/null 2>&1".into())))
    ])
    .align(End)));
    if !loading && printers.is_empty() {
        items.push(bx(Card::new(0xF042A, "No printers yet", "Connect a printer by USB or network and press «Add a printer»").build(t, w)));
    }
    for p in &printers {
        let title = format!("{}{}", p.name, if p.default { "   ·   default" } else { "" });
        let mut ctrl: Vec<W> = Vec::new();
        let n = sh_quote(&p.name);
        if !p.default {
            let n2 = n.clone();
            ctrl.push(bx(Btn::new("Set default").build(t, &format!("pr-def:{}", p.name), move || run(format!("lpoptions -d {n2}")))));
        }
        let n3 = n.clone();
        ctrl.push(bx(Btn::new("Test page").build(t, &format!("pr-test:{}", p.name), move || run(format!("lp -d {n3} /usr/share/cups/data/testprint")))));
        ctrl.push(bx(Btn::new("").icon(ic::TRASH).danger().build(t, &format!("pr-rm:{}", p.name), move || run(format!("pkexec lpadmin -x {n}")))));
        items.push(bx(Card::new(0xF042A, &title, &format!("{}   ·   {}", p.state, p.device)).id(&format!("pr:{}", p.name)).ctrl(Row::new(ctrl).gap(8.0).align(Center)).build(t, w)));
    }
    if !jobs.is_empty() {
        items.push(bx(w::section(t, "Print queue", w)));
    }
    for j in &jobs {
        let id = sh_quote(&j.id);
        items.push(bx(Card::new(0xF0B2B, &format!("{} {}", t.t("Job"), j.id), &format!("{} · {} · {} KB", j.printer, j.user, (j.size as f64 / 1024.0).round()))
            .id(&format!("job:{}", j.id))
            .ctrl(Btn::new("Cancel").danger().build(t, &format!("job-x:{}", j.id), move || run(format!("cancel {id}"))))
            .build(t, w)));
    }
    items.push(bx(w::section(t, "Scanners", w)));
    if !loading && !sane {
        items.push(bx(Card::new(0xF06AB, "Scanner support is not installed", "Installs SANE drivers and the Document Scanner app (needs your password)")
            .ctrl(Btn::new("Install").primary().build(t, "sc-install", || run("pkexec pacman -S --needed --noconfirm sane simple-scan".into())))
            .build(t, w)));
    }
    if sane {
        let sc = cmd::get("scanners", SCANNERS);
        let list: Vec<(String, String)> =
            sc.clone().unwrap_or_default().lines().filter_map(|l| l.split_once('|').map(|(a, b)| (a.to_string(), b.to_string()))).collect();
        if list.is_empty() {
            let looking = sc.is_none();
            items.push(bx(Card::new(0xF06AB, if looking { "Looking for scanners…" } else { "No scanners found" }, "Make sure the scanner is on and connected")
                .ctrl(Btn::new("Search again").enabled(!looking).build(t, "sc-again", || {
                    cmd::forget("scanners");
                    cmd::refresh("scanners", SCANNERS);
                }))
                .build(t, w)));
        }
        for (dev, name) in list {
            let c = if simple {
                "setsid -f simple-scan >/dev/null 2>&1".to_string()
            } else {
                format!("scanimage -d {} --format=png -o \"$HOME/Документы/scan-$(date +%F_%H-%M-%S).png\"", sh_quote(&dev))
            };
            items.push(bx(Card::new(0xF06AB, &name, &dev).id(&format!("sc:{dev}")).ctrl(Btn::new("Scan").primary().build(t, &format!("sc:{dev}"), move || run(c.clone()))).build(t, w)));
        }
    }
    items.push(bx(w::gap(10.0)));
    items.push(bx(Card::new(0xF059F, "CUPS web interface", "Advanced printer options at localhost:631").click(|| amane::spawn("xdg-open http://localhost:631")).build(t, w)));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lpstat() {
        let (p, j, sane, simple) = parse_printers(
            "@default\nsystem default destination: HP\n@printers\nprinter HP is idle.  enabled since Mon\nprinter Canon disabled since Tue\n@devices\ndevice for HP: usb://HP/LaserJet\n@jobs\nHP-12   user   2048   Mon\n@sane\nyes\n@simplescan\n",
        );
        assert_eq!(p[0], Printer { name: "HP".into(), state: "idle".into(), device: "usb://HP/LaserJet".into(), default: true });
        assert_eq!(p[1].state, "disabled");
        assert_eq!(j[0], Job { id: "HP-12".into(), printer: "HP".into(), user: "user".into(), size: 2048 });
        assert!(sane && !simple);
    }

    #[test]
    fn tablet_area() {
        let live = Json::parse(r#"{"DP-1":{"logical":{"x":0,"y":0,"width":1920,"height":1080}}}"#).unwrap();
        let tb = Json::parse(r#"{"keepAspect":true,"mapTo":"DP-1","widthMm":160,"heightMm":100}"#).unwrap();
        let a = used_area(&tb, None, true, &live);
        // планшет 16:10 уже экрана 16:9 — по высоте используется 0.9, по центру
        assert!(a[2] == 1.0 && (a[3] - 0.9).abs() < 1e-9 && (a[1] - 0.05).abs() < 1e-9);
        assert_eq!(used_area(&tb, None, false, &live), [0.0, 0.0, 1.0, 1.0]);
    }
}
