// окно по клику на часы (Dashboard.qml): вкладки Календарь / Плеер / Погода / Система

use std::sync::Mutex;
use std::time::Duration;

use amane::{Arc, Button, Canvas, Cap, Center, Column, End, Image, Media, Padding, Pointer, Rectangle, Row, Service, Shape, Stack, Start, TextInput, Weight, Widget, children};

use crate::clock::{self, Clock};
use crate::look::Tk;
use crate::notes::{self, Notes};
use crate::popups::{self, Popups};
use crate::sysstats::{self, SysStats};
use crate::ui::{self, POPUP, ic};
use crate::weather::{self, Weather};

type W = Box<dyn Widget>;

fn bx(w: impl Widget + 'static) -> W {
    Box::new(w)
}

pub const WIDTH: f32 = 620.0;

const TABS: [(u32, &str); 4] = [(0xF00ED, "Calendar"), (0xF075A, "Media"), (0xF0595, "Weather"), (0xF061A, "System")];

fn size(w: &dyn Widget) -> (f32, f32) {
    ui::size_of(w)
}

// плитка дашборда: тёмный скруглённый фон с отступами
fn tile(t: &Tk, w: f32, pad: f32, body: impl Widget + 'static) -> Rectangle {
    let (_, h) = size(&body);
    Rectangle::new().width(w).height(h + pad * 2.0).radius(16.0).fill(t.p.surface).padding(pad).child(body)
}

// шестерёнка: закрыть меню и открыть Настройки на последней странице
pub fn open_settings() {
    popups::close();
    let page = crate::prefs::Prefs::read().page;
    crate::prefs::show(page);
}

pub fn set_tab(i: usize) {
    let mut p = Popups::write();
    p.dash = i.min(3);
}

pub fn view(t: &Tk) -> Column {
    let cur = Popups::read().dash;
    // подсветка вкладки едет к выбранной (260 мс, OutCubic в Quickshell)
    let pos = crate::look::smooth("dash:tab", cur as f32, 0.07);
    // ── вкладки
    let tw = (WIDTH - 8.0 - 44.0) / 4.0;
    let mut tabs: Vec<W> = Vec::new();
    for (i, (icon, label)) in TABS.iter().enumerate() {
        let id = format!("dash:tab{i}");
        let sel = cur == i;
        let hov = ui::hovered::<POPUP>(&id);
        let c = if sel { t.p.fg } else if hov { t.p.muted } else { t.p.dim };
        let lab = ui::text(t, t.t(label), c).size(t.fs - 1.0);
        let lab = if sel { lab.weight(Weight::Bold) } else { lab };
        let r = Rectangle::new()
            .width(tw)
            .height(32.0)
            .radius(9.0)
            .cursor(Pointer)
            .align_child(Center, Center)
            .child(Row::new(children![ui::icon(t, *icon, t.icon, c), lab]).gap(8.0).align(Center));
        tabs.push(bx(ui::on_left(ui::track::<POPUP>(r, id), move || set_tab(i))));
    }
    let gh = ui::hovered::<POPUP>("dash:gear");
    let gear = ui::on_left(
        ui::track::<POPUP>(
            Rectangle::new()
                .width(36.0)
                .height(32.0)
                .radius(9.0)
                .fill(if gh { t.p.surface_hi2 } else { amane::Color::TRANSPARENT })
                .cursor(Pointer)
                .align_child(Center, Center)
                .child(Rectangle::new().width(24.0).height(24.0).rotate(if gh { 60.0 } else { 0.0 }).align_child(Center, Center).child(ui::icon(t, 0xF0493, t.icon + 1.0, if gh { t.p.fg } else { t.p.dim }))),
            "dash:gear",
        ),
        open_settings,
    );
    let bar = Rectangle::new()
        .width(WIDTH)
        .height(40.0)
        .radius(12.0)
        .fill(t.p.surface)
        .padding(Padding { top: 4.0, right: 4.0, bottom: 4.0, left: 4.0 })
        .on_scroll(move |s| set_tab(if s.y < 0.0 { cur.saturating_sub(1) } else { (cur + 1).min(3) }))
        .child(Stack::new(children![
            Rectangle::new().width(tw).height(32.0).radius(9.0).fill(t.p.surface_hi2).translate(pos * tw, 0.0),
            Row::new(vec![bx(Row::new(tabs)), bx(Rectangle::new().width(WIDTH - 8.0 - 4.0 * tw - 36.0).height(32.0)), bx(gear)])
        ]));
    let page: W = match cur {
        1 => bx(media_page(t)),
        2 => bx(weather_page(t)),
        3 => bx(system_page(t)),
        _ => bx(calendar_page(t)),
    };
    // страница въезжает на 40 px и проявляется, высота меняется плавно
    let (_, ph) = ui::size_of(page.as_ref());
    let h = crate::look::smooth("dash:height", ph, 0.07);
    let d = cur as f32 - pos;
    let page = Rectangle::new().width(WIDTH).height(h).clip().child(Rectangle::new().width(WIDTH).height(ph).translate(d.clamp(-1.0, 1.0) * 40.0, 0.0).opacity(1.0 - d.abs().min(1.0)).child(Column::new(vec![page])));
    Column::new(vec![bx(bar), bx(page)]).gap(12.0)
}

// ═════════ календарь + заметки выбранного дня

fn selected() -> (i64, u32, u32) {
    let now = Clock::read().now();
    Popups::read().sel.unwrap_or((now.year, now.month, now.day))
}

fn calendar_page(t: &Tk) -> Row {
    let cal = tile(t, 7.0 * 32.0 + 32.0, 16.0, calendar(t));
    let (cw, ch) = size(&cal);
    let nw = WIDTH - cw - 10.0;
    let notes = Rectangle::new().width(nw).height(ch).radius(16.0).fill(t.p.surface).padding(16.0).child(notes_panel(t, nw - 32.0, ch - 32.0));
    Row::new(children![cal, notes]).gap(10.0)
}

fn calendar(t: &Tk) -> Column {
    let now = Clock::read().now();
    let shift = Popups::read().month;
    let (y, mo) = popups::shift_month(now.year, now.month, shift);
    let monday = Settings_monday();
    let cell = 32.0;
    let sel = selected();
    let n = Notes::read();
    let head = clock::format("MMMM yyyy", &clock::Civil { year: y, month: mo, day: 1, ..now }, t.c.ru());
    let arrow = |id: &'static str, s: &'static str, by: i32| {
        let hov = ui::hovered::<POPUP>(id);
        ui::on_left(
            ui::track::<POPUP>(Rectangle::new().width(26.0).height(26.0).radius(8.0).fill(if hov { t.p.surface_hi2 } else { amane::Color::TRANSPARENT }).cursor(Pointer).align_child(Center, Center).child(ui::text(t, s, t.p.fg).size(t.icon + 2.0)), id),
            move || Popups::write().month += by,
        )
    };
    let mut rows: Vec<W> = vec![bx(Row::new(children![
        Rectangle::new().width(7.0 * cell - 56.0).height(26.0).padding(Padding { top: 0.0, right: 0.0, bottom: 0.0, left: 4.0 }).align_child(Start, Center).child(ui::bold(t, cap(&head), t.p.fg).size(t.fs + 1.0)),
        arrow("dash:prev", "‹", -1),
        arrow("dash:next", "›", 1)
    ])
    .gap(2.0)
    .align(Center))];
    let names = if monday { ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"] } else { ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"] };
    rows.push(bx(Row::new(names.iter().map(|d| bx(Rectangle::new().width(cell).height(22.0).align_child(Center, Center).child(ui::text(t, t.t(d), t.p.faint).size(t.fs - 2.0)))).collect::<Vec<_>>())));
    let grid = popups::month_grid(y, mo, monday);
    for wk in 0..6 {
        let mut line: Vec<W> = Vec::new();
        for (i, (d, inside)) in grid[wk * 7..wk * 7 + 7].iter().enumerate() {
            let idx = wk * 7 + i;
            let (dy, dm) = if *inside { (y, mo) } else if idx < 7 { popups::shift_month(y, mo, -1) } else { popups::shift_month(y, mo, 1) };
            let date = (dy, dm, *d);
            let today = date == (now.year, now.month, now.day);
            let is_sel = date == sel;
            let has = n.has(&notes::key(dy, dm, *d));
            let id = format!("dash:day{idx}");
            let hov = ui::hovered::<POPUP>(&id);
            let color = if today { t.p.bg } else if *inside { t.p.fg } else { t.p.faint };
            let txt = ui::text(t, d.to_string(), color).size(t.fs - 1.0);
            let txt = if today || is_sel { txt.weight(Weight::Bold) } else { txt };
            let mut bg = Rectangle::new().width(cell - 4.0).height(cell - 4.0).radius(9.0).fill(if today { t.p.accent } else if hov { t.p.surface_hi2 } else { amane::Color::TRANSPARENT });
            if is_sel && !today {
                bg = bg.border(1.5, t.p.fg);
            }
            let mut inner: Vec<W> = vec![bx(Rectangle::new().width(cell - 4.0).height(cell - 4.0 - if has { 4.0 } else { 0.0 }).align_child(Center, Center).child(txt))];
            if has {
                inner.push(bx(Rectangle::new().width(cell - 4.0).height(cell - 4.0).padding(Padding { top: 0.0, right: 0.0, bottom: 4.0, left: 0.0 }).align_child(Center, End).child(Rectangle::new().width(4.0).height(4.0).radius(2.0).fill(if today { t.p.bg } else { t.p.warn }))));
            }
            let c = Rectangle::new().width(cell).height(cell).cursor(Pointer).align_child(Center, Center).child(bg.child(Stack::new(inner)));
            let inside = *inside;
            line.push(bx(ui::on_left(ui::track::<POPUP>(c, id), move || {
                let mut p = Popups::write();
                p.sel = Some(date);
                if !inside {
                    p.month += if idx < 7 { -1 } else { 1 };
                }
            })));
        }
        rows.push(bx(Row::new(line)));
    }
    drop(n);
    Column::new(rows).gap(8.0)
}

#[allow(non_snake_case)]
fn Settings_monday() -> bool {
    crate::settings::Settings::read().raw.get("weekStartsMonday").bool_or(true)
}

fn cap(s: &str) -> String {
    let mut c = s.chars();
    c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
}

static NOTE: Mutex<String> = Mutex::new(String::new());
static NOTE_TIME: Mutex<String> = Mutex::new(String::new());

fn submit() {
    let (y, m, d) = selected();
    let text = NOTE.lock().unwrap().clone();
    if text.trim().is_empty() {
        return;
    }
    let time = NOTE_TIME.lock().unwrap().clone();
    notes::add(&notes::key(y, m, d), &text, &time);
    NOTE.lock().unwrap().clear();
    NOTE_TIME.lock().unwrap().clear();
    TextInput::set_text("dash-note", "");
    TextInput::set_text("dash-note-time", "");
}

fn notes_panel(t: &Tk, w: f32, h: f32) -> Column {
    let (y, m, d) = selected();
    let now = Clock::read().now();
    let k = notes::key(y, m, d);
    let items = Notes::read().list(&k);
    let date = clock::Civil { year: y, month: m, day: d, weekday: weekday(y, m, d), ..now };
    let mut head: Vec<W> = vec![bx(ui::bold(t, cap(&clock::format("dddd, d MMMM", &date, t.c.ru())), t.p.fg).size(t.fs + 1.0))];
    if (y, m, d) == (now.year, now.month, now.day) {
        let l = ui::text(t, t.t("today"), t.p.dim).size(t.fs - 3.0);
        let (lw, _) = size(&l);
        head.push(bx(Rectangle::new().width(lw + 12.0).height(18.0).radius(6.0).fill(t.p.surface_hi2).align_child(Center, Center).child(l)));
    }
    let head = Row::new(head).gap(8.0).align(Center);
    // список
    let list_h = h - 26.0 - 40.0 - 20.0;
    let mut list: Vec<W> = Vec::new();
    if items.is_empty() {
        list.push(bx(Rectangle::new().width(w).height(list_h).padding(Padding { top: 40.0, right: 0.0, bottom: 0.0, left: 0.0 }).align_child(Center, Start).child(
            Column::new(children![ui::text(t, t.tr("No notes", "Заметок нет"), t.p.faint).size(t.fs - 1.0), ui::text(t, t.tr("add one below", "добавьте ниже"), t.p.faint).size(t.fs - 1.0)]).gap(2.0).align(Center),
        )));
    }
    for n in &items {
        let id = n.get("id").str_or("");
        let time = n.get("time").str_or("");
        let done = !time.is_empty() && n.get("notified").bool_or(false);
        let hid = format!("note:{id}");
        let hov = ui::hovered::<POPUP>(&hid);
        let xid = format!("notex:{id}");
        let xh = ui::hovered::<POPUP>(&xid);
        let mut row: Vec<W> = Vec::new();
        let mut used = 20.0 + 18.0 + 8.0;
        if !time.is_empty() {
            let chip = Row::new(children![ui::icon(t, 0xF009A, t.fs - 3.0, if done { t.p.dim } else { t.p.bg }), ui::bold(t, time.clone(), if done { t.p.dim } else { t.p.bg }).size(t.fs - 2.0)]).gap(4.0).align(Center);
            let (cw, _) = size(&chip);
            row.push(bx(Rectangle::new().width(cw + 12.0).height(20.0).radius(6.0).fill(if done { t.p.surface_hi2 } else { t.p.fg }).align_child(Center, Center).child(chip)));
            used += cw + 12.0 + 8.0;
        }
        let tw = w - used;
        let body = crate::prefs::w::para(t, &n.get("text").str_or(""), t.fs - 1.0, if done { t.p.dim } else { t.p.fg }, tw);
        let (_, bh) = size(&body);
        row.push(bx(body));
        let (k2, id2) = (k.clone(), id.clone());
        row.push(bx(ui::on_left(
            ui::track::<POPUP>(Rectangle::new().width(18.0).height(18.0).cursor(Pointer).opacity(if hov || xh { 1.0 } else { 0.0 }).align_child(Center, Center).child(ui::icon(t, ic::CLOSE, t.fs, if xh { t.p.urgent } else { t.p.dim })), xid),
            move || notes::remove(&k2, &id2),
        )));
        let r = Rectangle::new().width(w).height(bh.max(20.0) + 16.0).radius(10.0).fill(if hov { t.p.surface_hi2 } else { t.p.surface_hi }).padding(Padding { top: 8.0, right: 10.0, bottom: 8.0, left: 10.0 }).child(Row::new(row).gap(8.0));
        list.push(bx(ui::track::<POPUP>(r, hid)));
    }
    let list = amane::ScrollArea::new("dash-notes", Column::new(list).gap(6.0)).width(w).height(list_h.max(150.0));
    // ввод: текст + необязательное время
    let has_text = !NOTE.lock().unwrap().trim().is_empty();
    let has_time = !NOTE_TIME.lock().unwrap().is_empty();
    let ah = ui::hovered::<POPUP>("dash:add");
    let input = TextInput::new("dash-note")
        .width(w - 12.0 - 6.0 - 78.0 - 28.0 - 16.0)
        .size(t.fs - 1.0)
        .color(t.p.fg)
        .placeholder(t.t("Add a note…"))
        .on_change(|s| *NOTE.lock().unwrap() = s)
        .on_submit(|_| submit());
    let time = TextInput::new("dash-note-time")
        .width(42.0)
        .size(t.fs - 1.0)
        .color(t.p.fg)
        .placeholder(t.t("time"))
        .on_change(|s| *NOTE_TIME.lock().unwrap() = s.chars().filter(|c| c.is_ascii_digit() || *c == ':').take(5).collect())
        .on_submit(|_| submit());
    let field = Rectangle::new().width(w).height(40.0).radius(10.0).fill(t.p.surface_hi).padding(Padding { top: 0.0, right: 6.0, bottom: 0.0, left: 12.0 }).child(
        Row::new(children![
            input,
            Rectangle::new()
                .width(78.0)
                .height(28.0)
                .radius(7.0)
                .fill(if has_time { t.p.surface_hi2 } else { amane::Color::TRANSPARENT })
                .align_child(Center, Center)
                .child(Row::new(children![ui::icon(t, 0xF009A, t.fs - 2.0, if has_time { t.p.fg } else { t.p.dim }), time]).gap(5.0).align(Center)),
            ui::on_left(
                ui::track::<POPUP>(
                    Rectangle::new().width(28.0).height(28.0).radius(7.0).fill(if ah { t.p.muted } else { t.p.fg }).opacity(if has_text { 1.0 } else { 0.3 }).cursor(Pointer).align_child(Center, Center).child(ui::bold(t, "+", t.p.bg).size(t.fs + 3.0)),
                    "dash:add"
                ),
                submit
            )
        ])
        .gap(8.0)
        .height(40.0)
        .align(Center),
    );
    Column::new(children![head, list, field]).gap(10.0)
}

fn weekday(y: i64, m: u32, d: u32) -> u32 {
    clock::civil(popups::days_from_civil(y, m, d) * 86400, 0).weekday
}

// ═════════ плеер (MPRIS)

fn fmt(sec: f64) -> String {
    if !sec.is_finite() || sec < 0.0 {
        return "0:00".into();
    }
    let s = sec.floor() as i64;
    format!("{}:{:02}", s / 60, s % 60)
}

// обложка: файл как есть, http — скачать в кэш один раз
pub fn art_path(url: &str) -> Option<String> {
    if url.is_empty() {
        return None;
    }
    if let Some(p) = url.strip_prefix("file://") {
        return Some(p.replace("%20", " "));
    }
    if url.starts_with('/') {
        return Some(url.to_string());
    }
    if !url.starts_with("http") {
        return None;
    }
    let dir = crate::settings::home().join(".cache/amane/art");
    let f = dir.join(format!("{}.img", crate::md5::hex(url.as_bytes())));
    if f.exists() {
        return Some(f.to_string_lossy().to_string());
    }
    static BUSY: Mutex<Vec<String>> = Mutex::new(Vec::new());
    let mut b = BUSY.lock().unwrap();
    if !b.contains(&url.to_string()) {
        b.push(url.to_string());
        let (u, f2) = (url.to_string(), f.clone());
        std::thread::spawn(move || {
            let _ = std::fs::create_dir_all(f2.parent().unwrap());
            let tmp = f2.with_extension("part");
            amane::output(&format!("curl -fsSL --max-time 10 -o {} {}", crate::niri::sh_quote(&tmp.to_string_lossy()), crate::niri::sh_quote(&u)));
            let _ = std::fs::rename(&tmp, &f2);
            amane::request_frame();
        });
    }
    None
}

fn media_page(t: &Tk) -> Rectangle {
    tile(t, WIDTH, 18.0, media_body::<POPUP>(t, WIDTH - 36.0, 150.0))
}

// плеер: обложка, трек, перемотка, кнопки (и в окне часов, и виджетом на рабочем столе)
pub fn media_body<const H: u8>(t: &Tk, w: f32, art_size: f32) -> Rectangle {
    let m = Media::read();
    let players = m.players();
    let idx = Popups::read().player;
    let player = if players.is_empty() {
        None
    } else {
        let playing = players.iter().position(|p| p.playing());
        let i = if idx > 0 { idx % players.len() } else { playing.unwrap_or(0) };
        Some(&players[i])
    };
    let Some(p) = player else {
        drop(m);
        return Rectangle::new().width(w).height(art_size).align_child(Center, Center).child(Column::new(children![ui::icon(t, 0xF075A, 30.0, t.p.faint), ui::text(t, t.t("Nothing playing"), t.p.dim).size(t.fs - 1.0)]).gap(8.0).align(Center));
    };
    let n = players.len();
    let cur_i = players.iter().position(|x| x.name() == p.name()).unwrap_or(0);
    let name = p.name().to_string();
    let (title, artist, playing) = (p.title().to_string(), p.artist().to_string(), p.playing());
    let (pos, len) = (p.position().as_secs_f64(), p.length().as_secs_f64());
    let art = art_path(p.art_url());
    let identity = p.identity().to_string();
    drop(m);
    let cover = Rectangle::new().width(art_size).height(art_size).radius(14.0).fill(t.p.surface_hi).clip().align_child(Center, Center);
    let cover = match art {
        Some(a) => cover.fill(Image::cover(a).thumbnail(300, 300)),
        None => cover.child(ui::icon(t, 0xF075A, 34.0, t.p.faint)),
    };
    let iw = w - art_size - 14.0;
    let src = format!("{}{}", identity.to_uppercase(), if n > 1 { format!("  ·  {n} {}", t.tr("PLAYERS", "ПЛЕЕРА")) } else { String::new() });
    let sh = n > 1 && ui::hovered::<H>("dash:src");
    let src = ui::on_left(ui::track::<H>(Rectangle::new().width(iw).height(16.0).child(ui::text(t, src, if sh { t.p.fg } else { t.p.faint }).size(t.fs - 3.0)), "dash:src"), move || {
        if n > 1 {
            Popups::write().player = cur_i + 1;
        }
    });
    let mut col: Vec<W> = vec![
        bx(src),
        bx(crate::prefs::w::line(t, &if title.is_empty() { t.t("Unknown") } else { title }, t.fs + 1.0, t.p.fg, iw, true)),
        bx(crate::prefs::w::line(t, &artist, t.fs - 1.0, t.p.dim, iw, false)),
    ];
    if len > 0.0 {
        static SEEK_X: Mutex<f32> = Mutex::new(0.0);
        let n2 = name.clone();
        let bar = Rectangle::new()
            .width(iw)
            .height(18.0)
            .cursor(Pointer)
            .align_child(Start, Center)
            .on_move(|p| *SEEK_X.lock().unwrap() = p.x)
            .on_click(move |_| {
                let x = *SEEK_X.lock().unwrap();
                let target = (x / iw).clamp(0.0, 1.0) as f64 * len;
                seek(&n2, ((target - pos) * 1_000_000.0) as i64);
            })
            .child(Rectangle::new().width(iw).height(4.0).radius(2.0).fill(t.p.surface_hi2).child(Rectangle::new().width(iw * (pos / len).min(1.0) as f32).height(4.0).radius(2.0).fill(t.p.fg)));
        col.push(bx(Rectangle::new().width(iw).height(6.0)));
        col.push(bx(bar));
    }
    let ctrl = |id: &'static str, icon: u32, primary: bool, f: fn()| {
        let hov = ui::hovered::<H>(id);
        let s = if primary { 34.0 } else { 28.0 };
        let fill = if primary { if hov { t.p.muted } else { t.p.fg } } else if hov { t.p.surface_hi2 } else { amane::Color::TRANSPARENT };
        ui::on_left(
            ui::track::<H>(Rectangle::new().width(s).height(s).radius(s / 2.0).fill(fill).cursor(Pointer).align_child(Center, Center).child(ui::icon(t, icon, if primary { t.icon + 1.0 } else { t.icon }, if primary { t.p.bg } else { t.p.fg })), id),
            f,
        )
    };
    let times = ui::text(t, if len > 0.0 { format!("{} / {}", fmt(pos), fmt(len)) } else { String::new() }, t.p.faint).size(t.fs - 3.0);
    let (tw, _) = size(&times);
    let ctrls = Row::new(children![ctrl("dash:prev-t", 0xF04AE, false, Media::previous), ctrl("dash:play", if playing { 0xF03E4 } else { 0xF040A }, true, Media::play_pause), ctrl("dash:next-t", 0xF04AD, false, Media::next)]).gap(4.0).align(Center);
    let (cw, _) = size(&ctrls);
    col.push(bx(Row::new(children![times, Rectangle::new().width((iw - tw - cw).max(0.0)).height(1.0), ctrls]).align(Center)));
    let info = Column::new(col).gap(2.0);
    let (_, ih) = size(&info);
    Rectangle::new().width(w).height(art_size).child(Row::new(vec![bx(cover), bx(Rectangle::new().width(iw).height(art_size).align_child(Start, Center).child(Column::new(vec![bx(info)]).height(ih)))]).gap(14.0))
}

// перемотка: смещение в микросекундах от текущей позиции
fn seek(player: &str, offset_us: i64) {
    let p = player.to_string();
    std::thread::spawn(move || {
        amane::Bus::session().call(&p, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Seek", &[amane::Argument::Long(offset_us)]);
    });
}

// ═════════ погода

static CITY_Q: Mutex<String> = Mutex::new(String::new());

fn weather_page(t: &Tk) -> Column {
    let w = WIDTH - 36.0;
    let wt = Weather::read();
    let body: W = if !wt.configured() {
        bx(Rectangle::new().width(w).height(90.0).align_child(Center, Center).child(Column::new(children![ui::icon(t, 0xF0595, 30.0, t.p.faint), ui::text(t, t.t("Find your city below"), t.p.dim).size(t.fs - 1.0)]).gap(6.0).align(Center)))
    } else {
        let mut left: Vec<W> = Vec::new();
        let region = wt.region();
        left.push(bx(crate::prefs::w::line(t, &format!("{} {}{}", ui::glyph(0xF034E), wt.city(), if region.is_empty() { String::new() } else { format!("  ·  {region}") }), t.fs - 1.0, t.p.dim, w - 270.0, false)));
        if let Some(c) = &wt.current {
            let (icon, text) = weather::info(c.code, c.is_day);
            left.push(bx(Row::new(children![
                ui::icon(t, icon, 52.0, t.p.fg),
                Column::new(children![ui::bold(t, format!("{}°", c.temp), t.p.fg).size(40.0), ui::text(t, t.t(text), t.p.dim)])
            ])
            .gap(14.0)
            .align(Center)));
            let feels = format!("{} {}°    {} {}%    {} {} {}", t.tr("feels", "ощущается"), c.feels, ui::glyph(0xF058E), c.humidity, ui::glyph(0xF059D), c.wind, t.tr("m/s", "м/с"));
            left.push(bx(ui::text(t, feels, t.p.dim).size(t.fs - 2.0)));
        } else {
            left.push(bx(ui::bold(t, "—", t.p.fg).size(40.0)));
        }
        let now_ms = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as f64).unwrap_or(0.0);
        let ago = weather::ago(wt.updated_at(), now_ms, t.c.ru());
        let status = if wt.loading {
            t.tr("updating…", "обновляю…").to_string()
        } else if !wt.error.is_empty() {
            format!("{} {ago}", t.tr("offline · showing data from", "нет сети · данные от"))
        } else if wt.updated_at() > 0.0 {
            format!("{} {ago}", t.tr("updated", "обновлено"))
        } else {
            String::new()
        };
        left.push(bx(ui::text(t, status, if wt.error.is_empty() { t.p.faint } else { t.p.warn }).size(t.fs - 3.0)));
        let mut days: Vec<W> = Vec::new();
        for d in wt.daily.iter().skip(1).take(4) {
            let p: Vec<i64> = d.date.split('-').filter_map(|x| x.parse().ok()).collect();
            let wd = if p.len() == 3 { weekday(p[0], p[1] as u32, p[2] as u32) } else { 0 };
            let names = if t.c.ru() { ["пн", "вт", "ср", "чт", "пт", "сб", "вс"] } else { ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] };
            days.push(bx(Rectangle::new().width(60.0).height(104.0).radius(12.0).fill(t.p.surface_hi).align_child(Center, Center).child(
                Column::new(children![
                    ui::text(t, names[wd as usize % 7], t.p.dim).size(t.fs - 2.0),
                    ui::icon(t, weather::info(d.code, true).0, 22.0, t.p.fg),
                    ui::bold(t, format!("{}°", d.max), t.p.fg).size(t.fs - 1.0),
                    ui::text(t, format!("{}°", d.min), t.p.dim).size(t.fs - 2.0)
                ])
                .gap(7.0)
                .align(Center),
            )));
        }
        let dr = Row::new(days).gap(6.0);
        let (dw, _) = size(&dr);
        let lc = Column::new(left).gap(6.0);
        bx(Row::new(vec![bx(Rectangle::new().width(w - dw - 20.0).height(size(&lc).1.max(104.0)).align_child(Start, Center).child(lc)), bx(dr)]).gap(20.0).align(Center))
    };
    let results = wt.results.clone();
    let searching = wt.searching;
    let configured = wt.configured();
    drop(wt);
    // поиск города
    let sw = WIDTH - 24.0;
    let q = CITY_Q.lock().unwrap().clone();
    let input = TextInput::new("dash-city")
        .width(sw - 24.0 - 20.0 - t.icon - 20.0)
        .size(t.fs - 1.0)
        .color(t.p.fg)
        .placeholder(t.t(if configured { "Change city…" } else { "Search city, e.g. London" }))
        .on_change(|s| {
            *CITY_Q.lock().unwrap() = s.clone();
            // поиск — через 350 мс после последней буквы
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_millis(350));
                if *CITY_Q.lock().unwrap() == s {
                    weather::search(&s);
                }
            });
        })
        .on_submit(|_| {
            let r = Weather::read().results.first().cloned();
            if let Some(r) = r {
                pick(&r);
            }
        });
    let mut col: Vec<W> = vec![bx(Rectangle::new().width(sw).height(38.0).radius(10.0).fill(t.p.surface_hi).padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 12.0 }).child(
        Row::new(children![ui::icon(t, ic::SEARCH, t.icon, t.p.dim), input, ui::text(t, if searching { "…" } else { "" }, t.p.dim)]).gap(10.0).height(38.0).align(Center),
    ))];
    let typed = q.trim().chars().count() >= 2;
    if typed && !searching && results.is_empty() {
        col.push(bx(Rectangle::new().width(sw).height(20.0).padding(Padding { top: 0.0, right: 0.0, bottom: 0.0, left: 4.0 }).child(ui::text(t, t.t("Nothing found"), t.p.dim).size(t.fs - 1.0))));
    }
    if typed {
        for (i, r) in results.iter().enumerate() {
            let id = format!("dash:city{i}");
            let hov = ui::hovered::<POPUP>(&id);
            let pop = if r.population >= 1e6 {
                format!("{:.1}M {}", r.population / 1e6, t.tr("people", "чел."))
            } else if r.population >= 1e3 {
                format!("{}k {}", (r.population / 1e3).round(), t.tr("people", "чел."))
            } else if r.population > 0.0 {
                format!("{} {}", r.population, t.tr("people", "чел."))
            } else {
                String::new()
            };
            let pl = ui::text(t, pop, t.p.faint).size(t.fs - 3.0);
            let (pw, _) = size(&pl);
            let sub = [r.admin1.clone(), r.country.clone()].into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join(", ");
            let tw = sw - 24.0 - t.icon - 20.0 - pw;
            let rr = Rectangle::new().width(sw).height(44.0).radius(10.0).fill(if hov { t.p.surface_hi2 } else { amane::Color::TRANSPARENT }).cursor(Pointer).padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 12.0 }).child(
                Row::new(children![
                    ui::icon(t, 0xF034E, t.icon, t.p.dim),
                    Column::new(children![crate::prefs::w::line(t, &t.t(&r.name), t.fs - 1.0, t.p.fg, tw, true), crate::prefs::w::line(t, &sub, t.fs - 2.0, t.p.dim, tw, false)]).gap(1.0),
                    pl
                ])
                .gap(10.0)
                .height(44.0)
                .align(Center),
            );
            let r2 = r.clone();
            col.push(bx(ui::on_left(ui::track::<POPUP>(rr, id), move || pick(&r2))));
        }
    }
    Column::new(children![tile(t, WIDTH, 18.0, Column::new(vec![body])), tile(t, WIDTH, 12.0, Column::new(col).gap(8.0))]).gap(10.0)
}

fn pick(r: &weather::Place) {
    weather::choose(r);
    CITY_Q.lock().unwrap().clear();
    TextInput::set_text("dash-city", "");
}

// ═════════ система: кольца CPU / GPU / RAM

pub fn ring(t: &Tk, value: f32, label: &str, sub: &str, battery: bool) -> Column {
    let size = 108.0;
    let v = crate::look::smooth(&format!("ring:{label}:{battery}"), value.clamp(0.0, 1.0), 0.3);
    let arc_c = if battery {
        if v <= 0.15 { t.p.urgent } else if v <= 0.3 { t.p.warn } else { t.p.accent }
    } else if v > 0.9 {
        t.p.urgent
    } else if v > 0.75 {
        t.p.warn
    } else {
        t.p.accent
    };
    let r = (size - 8.0) / 2.0;
    let mut shapes: Vec<Box<dyn Shape>> = vec![Box::new(Arc::new().center(size / 2.0, size / 2.0).radius(r).start(-135.0).sweep(270.0).stroke(8.0, t.p.surface_hi2).cap(Cap::Round))];
    if v > 0.005 {
        shapes.push(Box::new(Arc::new().center(size / 2.0, size / 2.0).radius(r).start(-135.0).sweep(270.0 * v).stroke(8.0, arc_c).cap(Cap::Round)));
    }
    let canvas = Canvas::new().width(size).height(size).shapes(shapes);
    Column::new(children![
        Rectangle::new().width(size).height(size).child(Stack::new(children![
            canvas,
            Rectangle::new().width(size).height(size).align_child(Center, Center).child(ui::bold(t, format!("{}%", (value * 100.0).round()), t.p.fg).size(t.fs + 7.0))
        ])),
        ui::bold(t, t.t(label), t.p.fg),
        ui::text(t, t.t(sub), t.p.dim).size(t.fs - 2.0)
    ])
    .gap(2.0)
    .align(Center)
}

fn system_page(t: &Tk) -> Rectangle {
    sysstats::need();
    let s = SysStats::read().clone();
    let gpu_sub = format!("{}°C · {:.1}/{} GB", s.gpu_temp.round(), s.vram_used / 1073741824.0, (s.vram_total / 1073741824.0).round());
    let ram = if s.ram_total > 0.0 { (s.ram_used / s.ram_total) as f32 } else { 0.0 };
    let row = Row::new(children![
        ring(t, s.cpu, "CPU", &format!("{}°C", s.cpu_temp.round()), false),
        ring(t, s.gpu, "GPU", &gpu_sub, false),
        ring(t, ram, "RAM", &format!("{} / {} GB", sysstats::gb(s.ram_used), sysstats::gb(s.ram_total)), false)
    ])
    .gap(56.0);
    let (rw, rh) = size(&row);
    let _ = Button::Left;
    tile(t, WIDTH, 22.0, Rectangle::new().width(WIDTH - 44.0).height(rh).align_child(Center, Start).child(Row::new(vec![bx(row)]).width(rw)))
}
