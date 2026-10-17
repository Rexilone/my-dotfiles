// бар — как Bar.qml: стиль flat | floating | pills, слева воркспейсы, по центру часы, справа статус

use std::cell::RefCell;
use std::collections::HashMap;

use amane::{
    Animation, Audio, Button, Center, Color, End, Full, Layer, LayerWindow, Media, Monitor, Notifications,
    Padding, Parent, Rectangle, Row, Service, Size, Stack, Start, Text, Vertical, Widget, Zone,
    children,
};

use crate::clock::Clock;
use crate::look::{self, PADDING, Tk};
use crate::niri::{self, Niri};
use crate::notifs::NotifState;
use crate::popups::{self, Popups};
use crate::ui::{self, BAR, ic};

pub fn gap(style: &str) -> f32 {
    match style {
        "flat" => 0.0,
        "pills" => 4.0,
        _ => 6.0,
    }
}

pub fn side(style: &str) -> f32 {
    match style {
        "floating" => 10.0,
        "pills" => 4.0,
        _ => 0.0,
    }
}

pub fn width_of(w: &impl Widget) -> f32 {
    match w.width() {
        Size::Fixed(v) => v,
        Size::Parent => 0.0,
    }
}

// окно бара на мониторе; на мониторах без бара — скрыто (Настройки → Бар → мониторы)
pub fn view(m: &Monitor) -> LayerWindow {
    let t = look::tk();
    // копия: повторное чтение сервиса внутри уже открытого чтения может зависнуть, если ждёт запись
    let ns = Niri::read().s.clone();
    let on = t.c.bar_on(&ns.outputs);
    let shown = ns.outputs.is_empty() || on.contains(&m.name);
    let style = t.c.bar_style.clone();
    let g = gap(&style);
    let h = t.bar_h;

    let content = Stack::new(children![
        Row::new(children![left(&t, &ns, &m.name)]).width(Parent).height(h).justify(Start).align(Center),
        Row::new(children![middle(&t)]).width(Parent).height(h).justify(Center).align(Center),
        Row::new(children![right(&t, &ns, &m.name)]).width(Parent).height(h).justify(End).align(Center),
    ])
    .width(Parent)
    .height(h);

    let pills = style == "pills";
    let inner = Rectangle::new()
        .width(Parent)
        .height(h)
        .padding(Padding { top: 0.0, right: if pills { 0.0 } else { PADDING }, bottom: 0.0, left: if pills { 0.0 } else { PADDING } })
        .child(content);
    let bg = if pills {
        inner
    } else {
        let floating = style == "floating";
        let r = inner.radius(if floating { 14.0 } else { 0.0 }).fill(t.panel);
        if floating { r.border(1.0, t.p.surface_hi2) } else { r }
    };

    LayerWindow::new()
        .width(Full)
        .height(h + g)
        .anchor_vertical(Vertical::Top)
        .layer(Layer::Top)
        .space(Zone::Reserve)
        .namespace("rexilone-bar")
        .visible(shown)
        .child(
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .padding(Padding { top: g, right: side(&style), bottom: 0.0, left: side(&style) })
                .child(bg),
        )
}

// группа модулей; в стиле pills — на своей плашке (BarGroup.qml)
fn group(t: &Tk, items: Vec<Box<dyn Widget>>, spacing: f32) -> Option<Rectangle> {
    if items.is_empty() {
        return None;
    }
    let pill = t.c.bar_style == "pills";
    let pad = if pill { 14.0 } else { 0.0 };
    let n = items.len() as f32;
    let w: f32 = items.iter().map(|i| match i.width() {
        Size::Fixed(v) => v,
        Size::Parent => 0.0,
    }).sum::<f32>()
        + spacing * (n - 1.0)
        + pad * 2.0;
    let row = Row::new(items).gap(spacing).align(Center).height(t.bar_h);
    let r = Rectangle::new().width(w.ceil()).height(t.bar_h).padding(Padding { top: 0.0, right: pad, bottom: 0.0, left: pad }).align_child(Start, Center).child(row);
    Some(if pill { r.radius(t.radius).fill(t.panel).border(1.0, t.p.surface_hi2) } else { r })
}

fn row_of(groups: Vec<Option<Rectangle>>) -> Row {
    let list: Vec<Box<dyn Widget>> = groups.into_iter().flatten().map(|g| Box::new(g) as Box<dyn Widget>).collect();
    Row::new(list).gap(10.0).align(Center)
}

// текст с наведением (BarText.qml): ярче под мышью, тусклее, если «неактивен»
fn bar_text(t: &Tk, id: &str, s: String, size: f32, active: bool, icon_like: bool) -> Rectangle {
    let hov = ui::hovered::<BAR>(id);
    let color = if hov || active { t.p.fg } else { t.p.dim };
    let txt = Text::new(s).font(&t.font).size(size).color(color);
    let txt = if icon_like { txt.tight() } else { txt };
    let w = width_of(&txt);
    let r = Rectangle::new().width(w.ceil() + 8.0).height(t.bar_h).align_child(Center, Center).opacity(if hov || active { 1.0 } else { 0.9 }).child(txt);
    ui::track::<BAR>(r, id).cursor(amane::Pointer)
}

fn left(t: &Tk, s: &niri::State, output: &str) -> Row {
    let mut groups = Vec::new();
    if t.c.module_on("launcher", false) {
        let b = bar_text(t, "launcher", ui::glyph(ic::ARCH), t.icon + 2.0, true, true)
            .on_click(|_| {
                crate::launcher::toggle(&[]);
            });
        groups.push(group(t, children![b], 0.0));
    }
    groups.push(group(t, children![workspaces(t, s, output)], 0.0));
    if t.c.module_on("window", false) {
        if let Some(w) = s.focused() {
            let title = if w.title.is_empty() { w.app_id.clone() } else { w.title.clone() };
            let txt = Text::new(title).font(&t.font).size(t.fs - 1.0).color(t.p.muted);
            let wd = width_of(&txt).min(380.0);
            groups.push(group(t, children![Rectangle::new().width(wd).height(t.bar_h).align_child(Start, Center).clip().child(txt.elide())], 0.0));
        }
    }
    row_of(groups)
}

fn middle(t: &Tk) -> Row {
    let mut groups = Vec::new();
    if t.c.module_on("media", false) {
        let m = Media::read();
        if !m.title().is_empty() {
            let playing = m.playing();
            let play = bar_text(t, "media:play", ui::glyph(if playing { 0xF03E4 } else { 0xF040A }), t.icon - 2.0, true, true)
                .on_click(|_| Media::play_pause());
            let label = [m.artist(), m.title()].iter().filter(|s| !s.is_empty()).copied().collect::<Vec<_>>().join(" — ");
            let hov = ui::hovered::<BAR>("media:title");
            let txt = Text::new(label).font(&t.font).size(t.fs - 1.0).color(if hov || playing { t.p.fg } else { t.p.dim });
            let w = width_of(&txt).min(280.0);
            let title = ui::track::<BAR>(Rectangle::new().width(w).height(t.bar_h).align_child(Start, Center).clip().child(txt.elide()), "media:title")
                .on_scroll(|s| if s.y < 0.0 { Media::previous() } else { Media::next() });
            groups.push(group(t, children![play, title], 8.0));
        }
    }
    let clock = Clock::read();
    let text = clock.text(&t.c.clock_format, t.c.ru());
    let open = Popups::read().open == "calendar";
    let c = bar_text(t, "clock", text, t.fs, !open, false).on_click(|_| popups::toggle("calendar"));
    groups.push(group(t, children![c], 14.0));
    row_of(groups)
}

fn right(t: &Tk, ns: &niri::State, output: &str) -> Row {
    let mut status: Vec<Box<dyn Widget>> = Vec::new();
    let out = output.to_string();

    if t.c.module("keyboard") && !ns.layouts.is_empty() {
        let code = niri::layout_code(ns.layout_name());
        let k = bar_text(t, "kbd", code, t.fs, true, false)
            .on_click(|_| niri::action("switch-layout next"))
            .on_scroll(|s| niri::action(if s.y < 0.0 { "switch-layout prev" } else { "switch-layout next" }));
        status.push(Box::new(k));
    }

    let a = Audio::read();
    if t.c.module("volume") {
        let (v, muted) = (a.volume(), a.muted());
        let icon = ui::glyph(ui::volume_icon(false, muted, v));
        let s = if muted { icon } else { format!("{icon} {v}%") };
        let o = out.clone();
        let w = bar_text(t, "vol", s, t.fs, !muted, false)
            .on_click(move |b| match b {
                Button::Left => Audio::toggle_mute(),
                Button::Right => popups::toggle_at("output", &o),
                Button::Middle => amane::spawn("pavucontrol --tab 3"),
            })
            .on_scroll(|s| step_volume(false, s.y));
        status.push(Box::new(w));
    }
    if t.c.module("mic") {
        let muted = a.microphone_muted();
        let s = ui::glyph(ui::volume_icon(true, muted, a.microphone_volume()));
        let s = if muted { s } else { format!("{s} {}%", a.microphone_volume()) };
        let o = out.clone();
        let w = bar_text(t, "mic", s, t.fs, !muted, false)
            .on_click(move |b| match b {
                Button::Left => Audio::toggle_microphone_mute(),
                Button::Right => popups::toggle_at("input", &o),
                Button::Middle => amane::spawn("pavucontrol --tab 4"),
            })
            .on_scroll(|s| step_volume(true, s.y));
        status.push(Box::new(w));
    }
    drop(a);

    if t.c.module("network") {
        let (code, active) = match crate::net::Net::read().kind {
            crate::net::Kind::Ethernet => (ic::ETHERNET, true),
            crate::net::Kind::Wifi => (ic::WIFI, true),
            crate::net::Kind::None => (ic::OFFLINE, false),
        };
        let o = out.clone();
        let w = bar_text(t, "net", ui::glyph(code), t.icon, active, true).on_click(move |_| popups::toggle_at("network", &o));
        status.push(Box::new(w));
    }

    if t.c.module("notifications") {
        let count = Notifications::read().list().len();
        let dnd = NotifState::read().dnd;
        let icon = ui::glyph(if dnd { ic::BELL_OFF } else { ic::BELL });
        let s = if count > 0 { format!("{icon} {count}") } else { icon };
        let open = Popups::read().open == "notifications";
        let o = out.clone();
        let w = bar_text(t, "bell", s, t.fs, open || (count > 0 && !dnd), false).on_click(move |b| match b {
            Button::Right => crate::notifs::toggle_dnd(),
            Button::Middle => Notifications::clear(),
            Button::Left => popups::toggle_at("notifications", &o),
        });
        status.push(Box::new(w));
    }

    if t.c.module_on("control", true) {
        let open = Popups::read().open == "control";
        let o = out.clone();
        let w = bar_text(t, "control", ui::glyph(ic::TUNE), t.icon, true, true).opacity(if open { 1.0 } else { 0.95 });
        status.push(Box::new(w.on_click(move |_| popups::toggle_at("control", &o))));
    }

    row_of(vec![group(t, status, 14.0)])
}

// колесо: ±5% (тачпад даёт мелкие шаги — копим до целой строки)
thread_local! {
    static WHEEL: RefCell<f32> = const { RefCell::new(0.0) };
}

pub fn wheel_steps(acc: &mut f32, y: f32) -> i32 {
    // крутанули в другую сторону — остаток прошлого направления не в счёт
    if *acc * y < 0.0 {
        *acc = 0.0;
    }
    *acc += y;
    let steps = acc.trunc() as i32;
    *acc -= steps as f32;
    steps
}

fn step_volume(input: bool, y: f32) {
    let steps = WHEEL.with_borrow_mut(|acc| wheel_steps(acc, y));
    if steps == 0 {
        return;
    }
    let a = Audio::read();
    let cur = if input { a.microphone_volume() } else { a.volume() } as i32;
    drop(a);
    let v = (cur - steps * 5).clamp(0, 150) as u8;
    if input { Audio::set_microphone_volume(v) } else { Audio::set_volume(v) }
}

// ── воркспейсы: точки или цифры; активный индикатор «перетекает» гусеницей (Workspaces.qml)

struct WsAnim {
    lo: Animation,
    hi: Animation,
    target: f32,
    ready: bool,
    // позиция и ширина каждой точки
    slots: HashMap<i64, (Animation, Animation)>,
}

thread_local! {
    static WS: RefCell<HashMap<String, WsAnim>> = RefCell::new(HashMap::new());
}

fn anim(from: f32, ms: u64) -> Animation {
    crate::look::anim(from, ms)
}

// куда ставить точку i: после активной — сдвиг на ширину «длинной»
pub fn slot_x(i: usize, active: Option<usize>, dot: f32, wide: f32, gap: f32) -> f32 {
    i as f32 * (dot + gap) + if active.is_some_and(|a| i > a) { wide - dot } else { 0.0 }
}

fn workspaces(t: &Tk, s: &niri::State, output: &str) -> Rectangle {
    let list = s.on_output(output);
    let numbers = t.c.workspace_style == "numbers";
    let (dot, wide, gap) = if numbers { (18.0, 26.0, 4.0) } else { (8.0, 22.0, 6.0) };
    let active = list.iter().position(|w| w.active);
    let total = if list.is_empty() { 0.0 } else { (list.len() - 1) as f32 * (dot + gap) + wide };
    let target = active.map(|a| a as f32 * (dot + gap)).unwrap_or(0.0);
    let slow = 300;

    let (lo, hi, slots) = WS.with_borrow_mut(|map| {
        let a = map.entry(output.to_string()).or_insert_with(|| WsAnim {
            lo: anim(target, 1),
            hi: anim(target + wide, 1),
            target,
            ready: false,
            slots: HashMap::new(),
        });
        if active.is_some() && (!a.ready || a.target != target) {
            if a.ready {
                let forward = target >= a.lo.value();
                a.lo = anim(a.lo.value(), if forward { 380 } else { 200 });
                a.hi = anim(a.hi.value(), if forward { 200 } else { 380 });
                crate::look::go(&mut a.lo, target);
                crate::look::go(&mut a.hi, target + wide);
            } else {
                // первая позиция — без анимации
                a.lo = anim(target, 1);
                a.hi = anim(target + wide, 1);
            }
            a.target = target;
            a.ready = true;
        }
        let mut slots = Vec::new();
        for (i, w) in list.iter().enumerate() {
            let x = slot_x(i, active, dot, wide, gap);
            let width = if Some(i) == active { wide } else { dot };
            let e = a.slots.entry(w.id).or_insert_with(|| (anim(x, slow), anim(width, slow)));
            crate::look::go(&mut e.0, x);
            crate::look::go(&mut e.1, width);
            slots.push((e.0.value(), e.1.value()));
        }
        (a.lo.value(), a.hi.value(), slots)
    });

    let r = if numbers { 6.0 } else { dot / 2.0 };
    let mut layers: Vec<Box<dyn Widget>> = Vec::new();
    let indicator = || Rectangle::new().width((hi - lo).max(dot)).height(dot).radius(r).fill(t.p.accent).translate(lo, 0.0);
    if numbers && active.is_some() {
        layers.push(Box::new(indicator()));
    }
    for (i, w) in list.iter().enumerate() {
        let (x, width) = slots[i];
        let id = format!("ws:{output}:{}", w.id);
        let hov = ui::hovered::<BAR>(&id);
        let occupied = w.active_window.is_some();
        let fill = if w.urgent {
            t.p.urgent
        } else if numbers {
            if hov { t.p.surface_hi2 } else { Color::TRANSPARENT }
        } else if hov {
            t.p.fg
        } else if occupied {
            t.p.dim
        } else {
            t.p.faint
        };
        let (o, idx) = (w.output.clone(), w.idx);
        let mut b = Rectangle::new().width(width).height(dot).radius(r).fill(fill).translate(x, 0.0);
        if numbers {
            let is_active = Some(i) == active;
            let color = if is_active { t.p.bg } else if occupied { t.p.fg } else { t.p.dim };
            let txt = Text::new(w.idx.to_string()).font(&t.font).size(t.fs - 2.0).color(color);
            let txt = if is_active { txt.weight(amane::Weight::Bold) } else { txt };
            b = b.align_child(Center, Center).child(txt);
        }
        let b = ui::track::<BAR>(b, id).cursor(amane::Pointer).on_click(move |_| niri::focus_workspace(&o, idx));
        layers.push(Box::new(b));
    }
    if !numbers && active.is_some() {
        layers.push(Box::new(indicator()));
    }
    Rectangle::new()
        .width(total)
        .height(t.bar_h)
        .align_child(Start, Center)
        .on_scroll(|s| {
            let steps = WHEEL.with_borrow_mut(|acc| wheel_steps(acc, s.y));
            if steps != 0 {
                niri::action(if steps < 0 { "focus-workspace-up" } else { "focus-workspace-down" });
            }
        })
        .child(Stack::new(layers).width(total).height(dot))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn style_gaps_match_quickshell() {
        assert_eq!(gap("flat"), 0.0);
        assert_eq!(gap("pills"), 4.0);
        assert_eq!(gap("floating"), 6.0);
        assert_eq!(side("pills"), 4.0);
        assert_eq!(side("floating"), 10.0);
        assert_eq!(side("flat"), 0.0);
    }

    #[test]
    fn slots_shift_after_active() {
        // точки 8, длинная 22, промежуток 6, активна вторая
        assert_eq!(slot_x(0, Some(1), 8.0, 22.0, 6.0), 0.0);
        assert_eq!(slot_x(1, Some(1), 8.0, 22.0, 6.0), 14.0);
        assert_eq!(slot_x(2, Some(1), 8.0, 22.0, 6.0), 28.0 + 14.0);
        assert_eq!(slot_x(2, None, 8.0, 22.0, 6.0), 28.0);
    }

    #[test]
    fn wheel_accumulates_touchpad() {
        let mut acc = 0.0;
        assert_eq!(wheel_steps(&mut acc, 0.4), 0);
        assert_eq!(wheel_steps(&mut acc, 0.4), 0);
        assert_eq!(wheel_steps(&mut acc, 0.4), 1);
        assert!((acc - 0.2).abs() < 1e-5);
        assert_eq!(wheel_steps(&mut acc, -3.0), -3);
        assert_eq!(wheel_steps(&mut acc, 1.0), 1);
        assert_eq!(wheel_steps(&mut acc, 0.6), 0);
        assert_eq!(wheel_steps(&mut acc, -0.6), 0);
        assert!((acc + 0.6).abs() < 1e-5);
    }
}
