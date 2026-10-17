// виджеты рабочего стола (DesktopWidgets.qml): слой под окнами на каждом мониторе.
// Редактирование (Настройки → Виджеты или `amane ipc call widgets edit`): поверх всего, перетаскивание,
// примагничивание к сетке 20 px, «Готово» — сохранить. Настройки — Settings.widgets, общие с Quickshell

use std::sync::Mutex;

use amane::{Center, Color, Column, End, Key, Keyboard, Layer, LayerWindow, Monitor, Padding, Parent, Pointer, Rectangle, Row, Service, Stack, Start, Text, Weight, Widget, Zone, children};

use crate::clock::{self, Clock};
use crate::json::Json;
use crate::look::{self, Tk};
use crate::rexlink::{self as rl, Rexlink};
use crate::settings::{self, Settings};
use crate::ui;

type W = Box<dyn Widget>;

fn bx(w: impl Widget + 'static) -> W {
    Box::new(w)
}

pub const DESK: u8 = 8;

pub const DEFS: [(&str, &str); 7] = [
    ("clock", "Clock"),
    ("perf", "Performance"),
    ("weather", "Weather"),
    ("media", "Media"),
    ("calendar", "Calendar"),
    ("notes", "Today's notes"),
    ("quote", "Quote of the day"),
];

#[derive(Default)]
pub struct Desk {
    pub editing: bool,
}

impl Service for Desk {
    fn new() -> Self {
        Desk::default()
    }

    fn listen() {}
}

pub fn ipc(args: &[String]) -> String {
    if args.first().map(String::as_str) == Some("edit") || args.is_empty() {
        let e = !Desk::read().editing;
        Desk::write().editing = e;
    }
    "ok".into()
}

// перетаскивание: виджет, точка захвата, начальная позиция, смещение сейчас
struct Drag {
    id: String,
    grab: (f32, f32),
    start: (f32, f32),
    now: (f32, f32),
}
static DRAG: Mutex<Option<Drag>> = Mutex::new(None);

fn primary() -> String {
    let outs = crate::niri::Niri::read().s.outputs.clone();
    Settings::read().c.primary(&outs)
}

// мягкая тень под текстом без фона: тёмная копия со сдвигом
fn shadowed(t: Text, dark: Text) -> Rectangle {
    let (w, h) = ui::size_of(&t);
    Rectangle::new().width(w + 2.0).height(h + 3.0).child(Stack::new(children![Rectangle::new().width(w).height(h).translate(1.0, 2.0).child(dark), Rectangle::new().width(w).height(h).child(t)]))
}

fn txt(t: &Tk, s: impl Into<String>, size: f32, c: Color, font: &str) -> Text {
    let x = Text::new(s.into()).size(size).color(c);
    if font.is_empty() { x.font(&t.font) } else { x.font(font) }
}

// ── отдельные виджеты

fn clock_w(t: &Tk, cfg: &Json, bg: bool) -> W {
    let fmt = cfg.get("format").str_or("HH:mm");
    if fmt.contains("ss") {
        drop(clock::Seconds::read());
    }
    let now = Clock::read().now();
    let font = cfg.get("font").str_or("");
    let big = clock::format(&fmt, &now, t.c.ru());
    let shadow = Color::rgba(0, 0, 0, 200);
    let mut col: Vec<W> = Vec::new();
    let main = txt(t, big.clone(), 96.0, t.p.fg, &font).weight(Weight::Bold);
    col.push(if bg { bx(main) } else { bx(shadowed(main, txt(t, big, 96.0, shadow, &font).weight(Weight::Bold))) });
    if cfg.get("showDate").bool_or(true) {
        let d = clock::format("dddd, d MMMM", &now, t.c.ru());
        let main = txt(t, d.clone(), 22.0, t.p.muted, &font);
        let dr = if bg { main.size(22.0) } else { main };
        col.push(bx(Rectangle::new().width(ui::size_of(&dr).0 + 8.0).height(30.0).padding(Padding { top: 0.0, right: 0.0, bottom: 0.0, left: 6.0 }).child(Column::new(vec![if bg { Box::new(dr) as W } else { bx(shadowed(dr, txt(t, d, 22.0, shadow, &font))) }]))));
    }
    bx(Column::new(col))
}

fn perf_w(t: &Tk) -> W {
    crate::sysstats::need();
    let s = crate::sysstats::SysStats::read().clone();
    let gpu_sub = format!("{}°C · {:.1}/{} GB", s.gpu_temp.round(), s.vram_used / 1073741824.0, (s.vram_total / 1073741824.0).round());
    let ram = if s.ram_total > 0.0 { (s.ram_used / s.ram_total) as f32 } else { 0.0 };
    let row = Row::new(children![
        crate::dash::ring(t, s.cpu, "CPU", &format!("{}°C", s.cpu_temp.round()), false),
        crate::dash::ring(t, s.gpu, "GPU", &gpu_sub, false),
        crate::dash::ring(t, ram, "RAM", &format!("{} / {} GB", crate::sysstats::gb(s.ram_used), crate::sysstats::gb(s.ram_total)), false)
    ])
    .gap(56.0);
    let (_, h) = ui::size_of(&row);
    bx(Rectangle::new().width(460.0).height(h).align_child(Center, Start).child(row))
}

fn weather_w(t: &Tk) -> W {
    let wt = crate::weather::Weather::read();
    let w = 300.0;
    if !wt.configured() {
        return bx(crate::prefs::w::para(t, &t.t("Set your city in the clock menu → Weather"), t.fs - 1.0, t.p.dim, w));
    }
    let mut col: Vec<W> = Vec::new();
    if let Some(c) = &wt.current {
        let (icon, text) = crate::weather::info(c.code, c.is_day);
        col.push(bx(Row::new(children![
            ui::icon(t, icon, 48.0, t.p.fg),
            Column::new(children![ui::bold(t, format!("{}°", c.temp), t.p.fg).size(38.0), crate::prefs::w::line(t, &format!("{}  ·  {}", wt.city(), t.t(text)), t.fs - 1.0, t.p.muted, w - 62.0, false)])
        ])
        .gap(14.0)
        .align(Center)));
    }
    if wt.daily.len() > 1 {
        let names = if t.c.ru() { ["пн", "вт", "ср", "чт", "пт", "сб", "вс"] } else { ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] };
        let dw = ((w - 12.0) / 3.0).floor();
        let mut days: Vec<W> = Vec::new();
        for d in wt.daily.iter().skip(1).take(3) {
            let p: Vec<i64> = d.date.split('-').filter_map(|x| x.parse().ok()).collect();
            let wd = if p.len() == 3 { clock::civil(crate::popups::days_from_civil(p[0], p[1] as u32, p[2] as u32) * 86400, 0).weekday } else { 0 };
            days.push(bx(Rectangle::new().width(dw).height(66.0).radius(12.0).fill(crate::theme::alpha(t.p.surface_hi, 0.7)).align_child(Center, Center).child(
                Column::new(children![
                    ui::text(t, names[wd as usize % 7], t.p.dim).size(t.fs - 2.0),
                    ui::text(t, format!("{} {}°", ui::glyph(crate::weather::info(d.code, true).0), d.max), t.p.fg)
                ])
                .gap(3.0)
                .align(Center),
            )));
        }
        col.push(bx(Row::new(days).gap(6.0)));
    }
    bx(Column::new(col).gap(10.0).width(w))
}

fn calendar_w(t: &Tk) -> W {
    let now = Clock::read().now();
    let monday = Settings::read().raw.get("weekStartsMonday").bool_or(true);
    let cell = 32.0;
    let head = clock::format("MMMM yyyy", &now, t.c.ru());
    let mut rows: Vec<W> = vec![bx(Rectangle::new().width(7.0 * cell).height(26.0).padding(Padding { top: 0.0, right: 0.0, bottom: 0.0, left: 4.0 }).align_child(Start, Center).child(ui::bold(t, head, t.p.fg).size(t.fs + 1.0)))];
    let names = if monday { ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"] } else { ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"] };
    rows.push(bx(Row::new(names.iter().map(|d| bx(Rectangle::new().width(cell).height(22.0).align_child(Center, Center).child(ui::text(t, t.t(d), t.p.faint).size(t.fs - 2.0)))).collect::<Vec<_>>())));
    let grid = crate::popups::month_grid(now.year, now.month, monday);
    let notes = crate::notes::Notes::read();
    for wk in 0..6 {
        let mut line: Vec<W> = Vec::new();
        for (i, (d, inside)) in grid[wk * 7..wk * 7 + 7].iter().enumerate() {
            let idx = wk * 7 + i;
            let (dy, dm) = if *inside { (now.year, now.month) } else if idx < 7 { crate::popups::shift_month(now.year, now.month, -1) } else { crate::popups::shift_month(now.year, now.month, 1) };
            let today = *inside && *d == now.day;
            let has = notes.has(&crate::notes::key(dy, dm, *d));
            let c = if today { t.p.bg } else if *inside { t.p.fg } else { t.p.faint };
            let tx = ui::text(t, d.to_string(), c).size(t.fs - 1.0);
            let tx = if today { tx.weight(Weight::Bold) } else { tx };
            let mut inner: Vec<W> = vec![bx(Rectangle::new().width(cell - 4.0).height(cell - 4.0 - if has { 4.0 } else { 0.0 }).align_child(Center, Center).child(tx))];
            if has {
                inner.push(bx(Rectangle::new().width(cell - 4.0).height(cell - 4.0).padding(Padding { top: 0.0, right: 0.0, bottom: 4.0, left: 0.0 }).align_child(Center, End).child(Rectangle::new().width(4.0).height(4.0).radius(2.0).fill(if today { t.p.bg } else { t.p.warn }))));
            }
            line.push(bx(Rectangle::new().width(cell).height(cell).align_child(Center, Center).child(Rectangle::new().width(cell - 4.0).height(cell - 4.0).radius(9.0).fill(if today { t.p.accent } else { Color::TRANSPARENT }).child(Stack::new(inner)))));
        }
        rows.push(bx(Row::new(line)));
    }
    bx(Column::new(rows).gap(8.0))
}

fn notes_w(t: &Tk) -> W {
    let now = Clock::read().now();
    let items = crate::notes::Notes::read().list(&crate::notes::key(now.year, now.month, now.day));
    let w = 280.0;
    let mut col: Vec<W> = vec![bx(ui::bold(t, format!("{}  {}", ui::glyph(0xF00ED), t.t("Today")), t.p.fg).size(t.fs + 1.0))];
    if items.is_empty() {
        col.push(bx(ui::text(t, t.t("No notes for today"), t.p.dim).size(t.fs - 1.0)));
    }
    for n in &items {
        let time = n.get("time").str_or("");
        let done = !time.is_empty() && n.get("notified").bool_or(false);
        let lead = ui::bold(t, if time.is_empty() { "•".to_string() } else { time.clone() }, if time.is_empty() { t.p.dim } else { t.p.accent }).size(t.fs - 1.0);
        let (lw, _) = ui::size_of(&lead);
        col.push(bx(Row::new(children![lead, crate::prefs::w::para(t, &n.get("text").str_or(""), t.fs - 1.0, if done { t.p.dim } else { t.p.fg }, w - lw - 8.0)]).gap(8.0)));
    }
    bx(Column::new(col).gap(8.0).width(w))
}

const QUOTES: [(&str, &str); 14] = [
    ("Simplicity is the ultimate sophistication.", "Leonardo da Vinci"),
    ("Talk is cheap. Show me the code.", "Linus Torvalds"),
    ("Make it work, make it right, make it fast.", "Kent Beck"),
    ("The best way to predict the future is to invent it.", "Alan Kay"),
    ("Less is more.", "Ludwig Mies van der Rohe"),
    ("Первая заповедь программиста: работает — не трогай.", "народная мудрость"),
    ("Тише едешь — дальше будешь.", "пословица"),
    ("Stay hungry, stay foolish.", "Steve Jobs"),
    ("Programs must be written for people to read.", "Harold Abelson"),
    ("Мы — то, что мы делаем постоянно.", "Аристотель"),
    ("Done is better than perfect.", "Sheryl Sandberg"),
    ("Не ошибается тот, кто ничего не делает.", "Теодор Рузвельт"),
    ("First, solve the problem. Then, write the code.", "John Johnson"),
    ("Kaizen: a little better every day.", "Japanese proverb"),
];
static QUOTE_SHIFT: Mutex<usize> = Mutex::new(0);

pub fn quote_index(days: i64, shift: usize) -> usize {
    (days.rem_euclid(QUOTES.len() as i64) as usize + shift) % QUOTES.len()
}

fn quote_w(t: &Tk, bg: bool) -> W {
    let days = clock::unix_now() / 86400;
    let (q, who) = QUOTES[quote_index(days, *QUOTE_SHIFT.lock().unwrap())];
    let w = 360.0;
    let body = crate::prefs::w::para(t, &format!("“{q}”"), t.fs + 5.0, t.p.fg, w);
    let mut col: Vec<W> = Vec::new();
    if bg {
        col.push(bx(body));
    } else {
        let (bw, bh) = ui::size_of(&body);
        col.push(bx(Rectangle::new().width(bw + 2.0).height(bh + 3.0).child(Stack::new(children![
            Rectangle::new().width(bw).height(bh).translate(1.0, 2.0).child(crate::prefs::w::para(t, &format!("“{q}”"), t.fs + 5.0, Color::rgba(0, 0, 0, 200), w)),
            body
        ]))));
    }
    col.push(bx(ui::text(t, format!("— {who}"), t.p.accent).size(t.fs - 1.0)));
    let c = Column::new(col).gap(8.0);
    let (_, h) = ui::size_of(&c);
    bx(Rectangle::new().width(w).height(h).cursor(Pointer).on_click(|_| *QUOTE_SHIFT.lock().unwrap() += 1).child(c))
}

// ── виджет телефона: battery | status | notifications | media | actions | full
fn phone_title(t: &Tk, dev: &Option<rl::Device>, online: bool, w: f32) -> Row {
    let connected = Rexlink::read().connected;
    let name = dev.as_ref().map(|d| d.name.clone()).unwrap_or_else(|| t.t(if connected { "No device" } else { "Rexlink is off" }));
    let mut parts: Vec<W> = vec![bx(ui::icon(t, rl::kind_icon(&dev.as_ref().map(|d| d.kind.clone()).unwrap_or_default()), t.icon + 2.0, if online { t.p.accent } else { t.p.dim }))];
    parts.push(bx(crate::prefs::w::line(t, &name, t.fs + 1.0, t.p.fg, w - t.icon - 10.0 - if online { 0.0 } else { 60.0 }, true)));
    if !online {
        parts.push(bx(ui::text(t, t.t("offline"), t.p.dim).size(t.fs - 3.0)));
    }
    Row::new(parts).gap(8.0).align(Center)
}

fn phone_w(t: &Tk, cfg: &Json, id: &str) -> W {
    let device = cfg.get("device").str_or("");
    let variant = cfg.get("variant").str_or("full");
    let r = Rexlink::read();
    let dev = r.dev_for(&device);
    let did = dev.as_ref().map(|d| d.id.clone()).unwrap_or_default();
    let online = dev.as_ref().is_some_and(|d| d.online);
    let st = r.status_for(&device);
    let media = r.media_for(&device);
    let notifs = r.notifs_for(&device).arr().to_vec();
    drop(r);
    let battery = st.get("battery").num().map(|x| x as i64).or(dev.as_ref().map(|d| d.battery)).unwrap_or(-1);
    let charging = st.get("charging").bool_or(false);
    let temp = st.get("temp").num().map(|x| format!("{x}")).unwrap_or_else(|| "—".into());
    // кольцо заряда (StatRing, battery: мало — плохо)
    let ring = |_size: f32, label: &str, sub: &str| -> Column { crate::dash::ring(t, (battery.max(0) as f32) / 100.0, label, sub, true) };
    match variant.as_str() {
        "battery" => {
            let sub = if !online { t.t("offline") } else if charging { t.t("charging") } else { format!("{temp}°C") };
            bx(ring(104.0, &dev.as_ref().map(|d| d.name.clone()).unwrap_or_default(), &sub))
        }
        "status" => {
            let w = 300.0;
            let low = battery >= 0 && battery <= 15 && !charging;
            let bar_w = w - 30.0 - 50.0 - 20.0;
            bx(Column::new(children![
                phone_title(t, &dev, online, w),
                Row::new(children![
                    ui::icon(t, rl::battery_icon(battery, charging), 22.0, if low { t.p.urgent } else { t.p.accent }),
                    Rectangle::new().width(bar_w).height(8.0).radius(4.0).fill(t.p.surface_hi2).child(Rectangle::new().width(bar_w * battery.max(0) as f32 / 100.0).height(8.0).radius(4.0).fill(if low { t.p.urgent } else { t.p.accent })),
                    ui::bold(t, if battery >= 0 { format!("{battery}%") } else { "—".into() }, t.p.fg)
                ])
                .gap(10.0)
                .align(Center)
            ])
            .gap(10.0)
            .width(w))
        }
        "notifications" => {
            let w = 340.0;
            let cnt = ui::text(t, format!("{} {}", ui::glyph(0xF009A), notifs.len()), if notifs.is_empty() { t.p.dim } else { t.p.accent }).size(t.fs - 1.0);
            let (cw, _) = ui::size_of(&cnt);
            let mut col: Vec<W> = vec![bx(Row::new(children![phone_title(t, &dev, online, w - cw - 8.0), cnt]).gap(8.0).align(Center))];
            if notifs.is_empty() {
                col.push(bx(ui::text(t, t.t(if online { "Nothing new" } else { "Device is offline" }), t.p.dim).size(t.fs - 1.0)));
            }
            for n in notifs.iter().take(5) {
                let key = n.get("key").str_or("");
                let iw = w - 20.0;
                let mut c: Vec<W> = Vec::new();
                let mut top: Vec<W> = vec![bx(crate::prefs::w::line(t, &n.get("app").str_or(""), t.fs - 3.0, t.p.dim, iw - 20.0, false))];
                if n.get("clearable").bool() != Some(false) {
                    let xid = format!("dpx:{id}:{key}");
                    let xh = ui::hovered::<DESK>(&xid);
                    let (k, d) = (key.clone(), did.clone());
                    top.push(bx(ui::on_left(ui::track::<DESK>(Rectangle::new().width(16.0).height(16.0).cursor(Pointer).align_child(Center, Center).child(ui::icon(t, ui::ic::CLOSE, t.fs - 2.0, if xh { t.p.urgent } else { t.p.dim })), xid), move || rl::notif_dismiss(&k, &d))));
                }
                c.push(bx(Row::new(top).gap(4.0).align(Center)));
                c.push(bx(crate::prefs::w::line(t, &n.get("title").str_or(""), t.fs - 1.0, t.p.fg, iw, true)));
                let body = n.get("text").str_or("");
                if !body.is_empty() {
                    c.push(bx(crate::prefs::w::para(t, &body.lines().take(2).collect::<Vec<_>>().join("\n"), t.fs - 2.0, t.p.muted, iw)));
                }
                let cc = Column::new(c).gap(1.0);
                let (_, ch) = ui::size_of(&cc);
                col.push(bx(Rectangle::new().width(w).height(ch + 16.0).radius(10.0).fill(crate::theme::alpha(t.p.surface_hi, 0.7)).padding(Padding { top: 8.0, right: 10.0, bottom: 8.0, left: 10.0 }).child(cc)));
            }
            if notifs.len() > 5 {
                col.push(bx(ui::text(t, if t.c.ru() { format!("ещё {}", notifs.len() - 5) } else { format!("+{} more", notifs.len() - 5) }, t.p.dim).size(t.fs - 2.0)));
            }
            bx(Column::new(col).gap(8.0).width(w))
        }
        "media" => {
            let w = 320.0;
            let title = media.get("title").str_or("");
            let mut col: Vec<W> = vec![bx(phone_title(t, &dev, online, w))];
            col.push(bx(crate::prefs::w::line(t, &if title.is_empty() { t.t("Nothing playing") } else { title.clone() }, t.fs + 1.0, if title.is_empty() { t.p.dim } else { t.p.fg }, w, !title.is_empty())));
            let sub = [media.get("artist").str_or(""), media.get("app").str_or("")].into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join("  ·  ");
            if !sub.is_empty() {
                col.push(bx(crate::prefs::w::line(t, &sub, t.fs - 2.0, t.p.dim, w, false)));
            }
            let len = media.get("len").num_or(0.0);
            if len > 0.0 {
                col.push(bx(Rectangle::new().width(w).height(4.0).radius(2.0).fill(t.p.surface_hi2).child(Rectangle::new().width(w * (media.get("pos").num_or(0.0) / len).min(1.0) as f32).height(4.0).radius(2.0).fill(t.p.accent))));
            }
            let playing = media.get("playing").bool_or(false);
            let mut btns: Vec<W> = Vec::new();
            for (a, icon, main) in [("prev", 0xF04AE, false), ("toggle", if playing { 0xF03E4 } else { 0xF040A }, true), ("next", 0xF04AD, false)] {
                let bid = format!("dpm:{id}:{a}");
                let hov = ui::hovered::<DESK>(&bid);
                let s = if main { 44.0 } else { 36.0 };
                let d = did.clone();
                let r = Rectangle::new()
                    .width(s)
                    .height(s)
                    .radius(s / 2.0)
                    .fill(if main { t.p.accent } else if hov { t.p.surface_hi2 } else { t.p.surface_hi })
                    .opacity(if online { 1.0 } else { 0.4 })
                    .cursor(Pointer)
                    .align_child(Center, Center)
                    .child(ui::icon(t, icon, t.icon + if main { 2.0 } else { 0.0 }, if main { t.p.bg } else { t.p.fg }));
                btns.push(bx(ui::on_left(ui::track::<DESK>(r, bid), move || if online { rl::media_action(a, &d, 0.0) })));
            }
            col.push(bx(Rectangle::new().width(w).height(44.0).align_child(Center, Center).child(Row::new(btns).gap(10.0).align(Center))));
            bx(Column::new(col).gap(8.0).width(w))
        }
        "actions" => {
            let w: f32 = 300.0;
            let aw = ((w - 16.0) / 3.0).floor();
            let mk = |key: &str, icon: u32, label: &str, f: Box<dyn Fn()>| -> W {
                let bid = format!("dpa:{id}:{key}");
                let hov = ui::hovered::<DESK>(&bid);
                let r = Rectangle::new()
                    .width(aw)
                    .height(58.0)
                    .radius(12.0)
                    .fill(if hov { t.p.surface_hi } else { crate::theme::alpha(t.p.surface_hi, 0.6) })
                    .opacity(if online { 1.0 } else { 0.4 })
                    .cursor(Pointer)
                    .align_child(Center, Center)
                    .child(Column::new(children![ui::icon(t, icon, t.icon + 2.0, t.p.fg), ui::text(t, t.t(label), t.p.muted).size(t.fs - 3.0)]).gap(4.0).align(Center));
                bx(ui::on_left(ui::track::<DESK>(r, bid), move || if online { f() }))
            };
            let d = did.clone();
            let (d1, d2, d3, d4, d5) = (d.clone(), d.clone(), d.clone(), d.clone(), d.clone());
            let r1 = Row::new(vec![
                mk("find", 0xF08D3, "Find", Box::new(move || rl::ring(&d1))),
                mk("clip", ui::ic::CLIPBOARD, "Clipboard", Box::new(move || rl::clipboard_pull(&d2))),
                mk("files", 0xF0552, "Files", Box::new(move || {
                    rl::select(&d3);
                    rl::show("files");
                })),
            ])
            .gap(8.0);
            let r2 = Row::new(vec![
                mk("screen", 0xF0379, "Screen", Box::new(move || rl::screen_start(&d4))),
                mk("cam", 0xF0100, "Webcam", Box::new(move || if Rexlink::read().camera.get("running").bool_or(false) { rl::camera_stop() } else { rl::camera_start(&d5) })),
                mk("sms", 0xF0369, "Messages", Box::new(move || {
                    rl::select(&d);
                    rl::show("messages");
                })),
            ])
            .gap(8.0);
            bx(Column::new(children![phone_title(t, &dev, online, w), Column::new(children![r1, r2]).gap(8.0)]).gap(10.0).width(w))
        }
        _ => {
            let w = 380.0;
            let label = if charging { t.t("Charging") } else { String::new() };
            let tw = w - 108.0 - 18.0;
            let mut col: Vec<W> = vec![bx(phone_title(t, &dev, online, tw))];
            let line = if !online {
                t.t("Offline")
            } else {
                let cell = st.get("cell");
                format!("{} {}  ·  {}  ·  {temp}°C", cell.get("operator").str_or(""), cell.get("gen").str_or(""), if st.get("net").str() == Some("wifi") { "Wi-Fi" } else { "mobile" })
            };
            col.push(bx(crate::prefs::w::line(t, &line, t.fs - 2.0, t.p.muted, tw, false)));
            if online {
                col.push(bx(ui::text(t, format!("{} {} {}", ui::glyph(0xF009A), notifs.len(), crate::i18n::plural(t.c.ru(), notifs.len() as i64, "notification", "notifications", "уведомление", "уведомления", "уведомлений")), if notifs.is_empty() { t.p.dim } else { t.p.accent }).size(t.fs - 2.0)));
                let mt = media.get("title").str_or("");
                if !mt.is_empty() {
                    col.push(bx(crate::prefs::w::line(t, &format!("{}  {mt}", ui::glyph(if media.get("playing").bool_or(false) { 0xF040A } else { 0xF03E4 })), t.fs - 2.0, t.p.dim, tw, false)));
                }
            }
            bx(Row::new(vec![bx(ring(96.0, &label, "")), bx(Column::new(col).gap(4.0).width(tw))]).gap(18.0).align(Center))
        }
    }
}

// ── слой на мониторе

fn widget(t: &Tk, id: &str, cfg: &Json, bg: bool) -> W {
    if id.starts_with("phone-") {
        return phone_w(t, cfg, id);
    }
    match id {
        "clock" => clock_w(t, cfg, bg),
        "perf" => perf_w(t),
        "weather" => weather_w(t),
        "media" => bx(crate::dash::media_body::<DESK>(t, 400.0, 96.0)),
        "calendar" => calendar_w(t),
        "notes" => notes_w(t),
        _ => quote_w(t, bg),
    }
}

fn name_of(id: &str, cfg: &Json) -> String {
    if id.starts_with("phone-") {
        let dev = Rexlink::read().dev_for(&cfg.get("device").str_or("")).map(|d| d.name).unwrap_or_else(|| "Phone".into());
        return format!("{dev} · {}", cfg.get("variant").str_or("full"));
    }
    DEFS.iter().find(|d| d.0 == id).map(|d| d.1.to_string()).unwrap_or_else(|| id.to_string())
}

pub fn snap(v: f32) -> f32 {
    (v / 20.0).round() * 20.0
}

fn save_pos(id: &str, x: f32, y: f32) {
    let all = Settings::read().raw.get("widgets").clone();
    let mut w = all.get(id).clone();
    if !matches!(w, Json::Obj(_)) {
        w = Json::Obj(Vec::new());
    }
    w.set("x", Json::Num(x as f64));
    w.set("y", Json::Num(y as f64));
    settings::save_path(&["widgets", id], w);
}

pub fn view(m: &Monitor) -> LayerWindow {
    let tk = look::tk();
    let t = &tk;
    let editing = Desk::read().editing;
    let all = Settings::read().raw.get("widgets").clone();
    let outs = crate::niri::Niri::read().s.outputs.clone();
    let prim = primary();
    let (sw, sh) = outs.iter().find(|o| o.0 == m.name).map(|o| (o.1 as f32, o.2 as f32)).unwrap_or((1920.0, 1080.0));
    let mut ids: Vec<String> = DEFS.iter().map(|d| d.0.to_string()).collect();
    let mut phones: Vec<String> = all.obj().iter().map(|(k, _)| k.clone()).filter(|k| k.starts_with("phone-")).collect();
    phones.sort();
    ids.extend(phones);
    let mine: Vec<String> = ids
        .into_iter()
        .filter(|id| {
            let c = all.get(id);
            let scr = c.get("screen").str_or("");
            c.get("enabled").bool_or(false) && (scr == m.name || (!outs.iter().any(|o| o.0 == scr) && m.name == prim))
        })
        .collect();
    if mine.is_empty() && !editing {
        return LayerWindow::new().width(1.0).height(1.0).layer(Layer::Bottom).namespace("rexilone-widgets").visible(false).child(Rectangle::new().width(1.0).height(1.0));
    }
    let drag = DRAG.lock().unwrap().as_ref().map(|d| (d.id.clone(), d.now));
    let mut layers: Vec<W> = Vec::new();
    if editing {
        // затемнение и сетка
        let mut grid: Vec<W> = Vec::new();
        let line = Color::rgba(255, 255, 255, 13);
        let mut x = 0.0;
        while x < sw {
            grid.push(bx(Rectangle::new().width(1.0).height(sh).fill(line).translate(x, 0.0)));
            x += 40.0;
        }
        let mut y = 0.0;
        while y < sh {
            grid.push(bx(Rectangle::new().width(sw).height(1.0).fill(line).translate(0.0, y)));
            y += 40.0;
        }
        layers.push(bx(Rectangle::new().width(sw).height(sh).fill(Color::rgba(0, 0, 0, 115)).child(Stack::new(grid))));
    }
    for id in &mine {
        let cfg = all.get(id).clone();
        let bg = cfg.get("background").bool_or(true);
        let k = cfg.get("size").num_or(1.0) as f32;
        let body = widget(t, id, &cfg, bg);
        let (bw, bh) = ui::size_of(body.as_ref());
        let pad = if bg { 20.0 } else { 0.0 };
        let (cw, ch) = (bw + pad * 2.0, bh + pad * 2.0);
        let mut card = Rectangle::new().width(cw).height(ch);
        if bg {
            card = card.radius(20.0).fill(t.panel).border(1.0, crate::theme::alpha(t.p.line, 0.5)).padding(pad);
        }
        let card = card.child(Column::new(vec![body]));
        let (w, h) = (cw * k, ch * k);
        let (mut x, mut y) = (cfg.get("x").num_or(80.0) as f32, cfg.get("y").num_or(80.0) as f32);
        if let Some((did, pos)) = &drag {
            if did == id {
                (x, y) = *pos;
            }
        }
        let x = x.clamp(0.0, (sw - w).max(0.0));
        let y = y.clamp(0.0, (sh - h).max(0.0));
        // масштаб — от центра: сдвигаем, чтобы угол остался на месте
        let scaled = Rectangle::new().width(cw).height(ch).scale(k).translate((w - cw) / 2.0, (h - ch) / 2.0).child(card);
        let mut item: Vec<W> = vec![bx(scaled)];
        if editing {
            let dragging = drag.as_ref().is_some_and(|(d, _)| d == id);
            let hid = format!("desk-edit:{id}");
            let hov = ui::hovered::<DESK>(&hid);
            let tag = ui::bold(t, t.t(&name_of(id, &cfg)), t.p.bg).size(t.fs - 3.0);
            let (tw, _) = ui::size_of(&tag);
            let frame = Rectangle::new()
                .width(w + 12.0)
                .height(h + 12.0)
                .translate(-6.0, -6.0)
                .radius(22.0)
                .fill(if hov { Color::rgba(255, 255, 255, 10) } else { Color::TRANSPARENT })
                .border(2.0, if dragging { t.p.accent } else { crate::theme::alpha(t.p.accent, 0.6) })
                .cursor(amane::Grab)
                .child(Rectangle::new().width(tw + 16.0).height(22.0).radius(7.0).fill(t.p.accent).translate(12.0, -12.0).align_child(Center, Center).child(tag));
            let (id1, id2) = (id.clone(), id.clone());
            let (x0, y0) = (x, y);
            let (mw, mh) = ((sw - w).max(0.0), (sh - h).max(0.0));
            let frame = ui::track::<DESK>(frame, hid)
                .on_drag(move |p| {
                    let mut d = DRAG.lock().unwrap();
                    match d.as_mut() {
                        Some(g) if g.id == id1 => {
                            g.now = ((g.start.0 + p.x - g.grab.0).clamp(0.0, mw), (g.start.1 + p.y - g.grab.1).clamp(0.0, mh));
                        }
                        _ => *d = Some(Drag { id: id1.clone(), grab: (p.x, p.y), start: (x0, y0), now: (x0, y0) }),
                    }
                    drop(d);
                    // перерисовать: отметка наведения та же
                    let h = ui::Hover::<DESK>::read().id.clone();
                    ui::Hover::<DESK>::write().id = h;
                })
                .on_click(move |_| {
                    // отпустили — примагнитить к сетке 20 px и сохранить
                    let d = DRAG.lock().unwrap().take();
                    if let Some(g) = d.filter(|g| g.id == id2) {
                        save_pos(&g.id, snap(g.now.0), snap(g.now.1));
                    }
                });
            item.push(bx(frame));
        }
        layers.push(bx(Rectangle::new().width(w).height(h).translate(x, y).child(Stack::new(item))));
    }
    if editing {
        // панель «Готово»
        let label = ui::text(t, format!("{}  {} · {}", ui::glyph(0xF0B92), t.t("Drag widgets to move them"), m.name), t.p.fg);
        let (lw, _) = ui::size_of(&label);
        let dh = ui::hovered::<DESK>("desk:done");
        let done = ui::bold(t, t.t("Done"), t.p.bg);
        let (dw, _) = ui::size_of(&done);
        let bar = Row::new(children![
            label,
            ui::on_left(ui::track::<DESK>(Rectangle::new().width(dw + 26.0).height(34.0).radius(10.0).fill(if dh { t.p.muted } else { t.p.accent }).cursor(Pointer).align_child(Center, Center).child(done), "desk:done"), || Desk::write().editing = false)
        ])
        .gap(14.0)
        .align(Center);
        let bw = lw + dw + 26.0 + 14.0 + 32.0;
        layers.push(bx(Rectangle::new().width(bw).height(52.0).radius(16.0).fill(t.p.surface).border(1.0, t.p.line).translate((sw - bw) / 2.0, 48.0).align_child(Center, Center).child(bar)));
    }
    LayerWindow::new()
        .width(amane::Full)
        .height(amane::Full)
        .layer(if editing { Layer::Overlay } else { Layer::Bottom })
        .space(Zone::Ignore)
        .namespace("rexilone-widgets")
        .keyboard(if editing { Keyboard::OnDemand } else { Keyboard::None })
        .on_key(|k| {
            if k == Key::Escape {
                Desk::write().editing = false
            }
        })
        .child(Rectangle::new().width(Parent).height(Parent).child(Stack::new(layers)))
}

#[cfg(test)]
mod tests {
    #[test]
    fn grid_and_quotes() {
        assert_eq!(super::snap(29.0), 20.0);
        assert_eq!(super::snap(31.0), 40.0);
        assert_eq!(super::quote_index(14, 0), 0);
        assert_eq!(super::quote_index(15, 1), 2);
    }
}
