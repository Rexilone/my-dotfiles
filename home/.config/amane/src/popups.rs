// меню под баром (Popup.qml): календарь, звук, сеть, уведомления, центр управления.
// Клик мимо карточки или Esc закрывают меню.

use std::time::Duration;

use amane::{
    Animation, Audio, Bluetooth, Brightness, Center, Column, End, Full, Key, Keyboard, Layer, LayerWindow, Media,
    Monitor, Network, Notifications, Padding, Parent, Rectangle, Row, Service, Shadow, SpaceBetween, Start, Text,
    TextInput, Weight, Widget, Zone, children,
};

use crate::clock::{self, Clock};
use crate::json::Json;
use crate::look::{self, Tk};
use crate::notifs::{self, NotifState};
use crate::settings::{self, Settings};
use crate::ui::{self, POPUP, ic};

pub struct Popups {
    pub open: String,
    // последнее открытое: меню дорисовывается им, пока гаснет после закрытия
    pub shown: String,
    pub output: String,
    // календарь: сдвиг месяца от текущего
    pub month: i32,
    // сеть: к какой сети вводим пароль
    pub ask_ssid: String,
    pub password: String,
    pub anim: Animation,
    pub notif_scroll: f32,
}

impl Service for Popups {
    fn new() -> Self {
        Popups {
            open: String::new(),
            shown: String::new(),
            output: String::new(),
            month: 0,
            ask_ssid: String::new(),
            password: String::new(),
            anim: crate::look::anim(0.0, 220),
            notif_scroll: 0.0,
        }
    }

    fn interval() -> Duration {
        Duration::from_secs(3600)
    }
}

// открыть на мониторе с фокусом (вызовы из бара передают свой монитор)
pub fn toggle(name: &str) {
    let out = crate::niri::Niri::read().s.focused_output().to_string();
    toggle_at(name, &out);
}

pub fn toggle_at(name: &str, output: &str) {
    let mut p = Popups::write();
    if p.open == name && p.output == output {
        p.open.clear();
        crate::look::go(&mut p.anim, 0.0);
    } else {
        // другое меню на том же мониторе — сразу, без повторного появления
        let switching = !p.open.is_empty() && p.output == output;
        p.open = name.to_string();
        p.shown = name.to_string();
        p.output = output.to_string();
        p.month = 0;
        p.ask_ssid.clear();
        p.notif_scroll = 0.0;
        if !switching {
            // появление — после первого кадра (look::appear)
            p.anim = crate::look::anim(0.0, 220);
        }
    }
    drop(p);
    if name == "network" {
        Network::scan();
    }
}

pub fn close() {
    let mut p = Popups::write();
    if !p.open.is_empty() {
        p.open.clear();
        crate::look::go(&mut p.anim, 0.0);
    }
}

// после закрытия меню (чтобы оно не попало, например, на скриншот)
fn after_close(cmd: &'static str) {
    close();
    amane::spawn(&format!("sleep 0.25; {cmd}"));
}

pub fn view(m: &Monitor) -> LayerWindow {
    let t = look::tk();
    let p = Popups::read();
    let on_output = p.output == m.name;
    let here = !p.open.is_empty() && on_output;
    let name = p.shown.clone();
    let k = if on_output { p.anim.value() } else { 0.0 };
    drop(p);
    look::appear("popup", here, || {
        let mut x = Popups::write();
        if !x.open.is_empty() {
            look::go(&mut x.anim, 1.0);
        }
    });

    let (card_w, body): (f32, Box<dyn Widget>) = if !here && k <= 0.01 {
        (10.0, Box::new(ui::spacer(1.0, 1.0)))
    } else {
        match name.as_str() {
            "calendar" => (300.0, Box::new(calendar(&t))),
            "output" => (340.0, Box::new(mixer(&t, false))),
            "input" => (340.0, Box::new(mixer(&t, true))),
            "network" => (320.0, Box::new(network(&t))),
            "notifications" => (380.0, Box::new(center(&t))),
            "control" => (380.0, Box::new(control(&t))),
            _ => (10.0, Box::new(ui::spacer(1.0, 1.0))),
        }
    };
    let (_, body_h) = size_of_box(&*body);
    let pad = 14.0;
    let card = Rectangle::new()
        .width(card_w + pad * 2.0)
        .height(body_h + pad * 2.0)
        .radius(18.0)
        .fill(t.panel)
        .border(1.0, t.p.surface_hi2)
        .shadow(Shadow::drop("#000000").opacity(0.44).blur(32.0).offset(0.0, 10.0))
        .padding(pad)
        .opacity(k)
        .scale(0.97 + 0.03 * k)
        .translate(0.0, -12.0 * (1.0 - k))
        .on_click(|_| {})
        .child(Column::new(vec![body]));
    let calendar_like = name == "calendar";
    LayerWindow::new()
        .width(Full)
        .height(Full)
        .layer(Layer::Top)
        .space(Zone::Respect)
        .namespace("rexilone-popup")
        .keyboard(if here { Keyboard::OnDemand } else { Keyboard::None })
        .on_key(|key| {
            if key == Key::Escape {
                close()
            }
        })
        .visible(here || k > 0.01)
        .child(
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .padding(Padding { top: 8.0, right: 10.0, bottom: 0.0, left: 10.0 })
                .align_child(if calendar_like { amane::Align::Center } else { amane::Align::End }, Start)
                .on_click(|_| close())
                .child(card),
        )
}

fn size_of_box(w: &dyn Widget) -> (f32, f32) {
    let f = |s: amane::Size| match s {
        amane::Size::Fixed(v) => v,
        amane::Size::Parent => 0.0,
    };
    (f(w.width()), f(w.height()))
}

fn title(t: &Tk, s: &str) -> Text {
    ui::bold(t, s, t.p.fg).size(t.fs + 1.0)
}

// ── календарь

// дни месяца сеткой по 7: (число, этот ли месяц); всегда 6 недель — меню не прыгает
pub fn month_grid(year: i64, month: u32, monday_first: bool) -> Vec<(u32, bool)> {
    let first = clock::civil(days_from_civil(year, month, 1) * 86400, 0).weekday; // 0 = пн
    let lead = if monday_first { first } else { (first + 1) % 7 };
    let (py, pm) = if month == 1 { (year - 1, 12) } else { (year, month - 1) };
    let prev_len = days_in(py, pm);
    let len = days_in(year, month);
    let mut out = Vec::new();
    for i in 0..lead {
        out.push((prev_len - lead + 1 + i, false));
    }
    for d in 1..=len {
        out.push((d, true));
    }
    let mut d = 1;
    while out.len() < 42 {
        out.push((d, false));
        d += 1;
    }
    out
}

pub fn days_in(year: i64, month: u32) -> u32 {
    match month {
        2 if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

pub fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m as i64 + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

pub fn shift_month(year: i64, month: u32, by: i32) -> (i64, u32) {
    let m = year * 12 + month as i64 - 1 + by as i64;
    (m.div_euclid(12), (m.rem_euclid(12) + 1) as u32)
}

fn calendar(t: &Tk) -> Column {
    let now = Clock::read().now();
    let shift = Popups::read().month;
    let (y, mo) = shift_month(now.year, now.month, shift);
    let monday = settings::load().get("weekStartsMonday").bool_or(true);
    let cell = 300.0 / 7.0;

    let head = clock::format("MMMM yyyy", &clock::Civil { year: y, month: mo, day: 1, ..now }, t.c.ru());
    let big = clock::format("HH:mm", &now, t.c.ru());
    let date = clock::format("dddd, d MMMM", &now, t.c.ru());
    let arrow = |id: &'static str, code: u32, by: i32| {
        let hov = ui::hovered::<POPUP>(id);
        ui::on_left(
            ui::track::<POPUP>(
                Rectangle::new().width(28.0).height(28.0).radius(8.0).fill(if hov { t.p.surface_hi } else { amane::Color::TRANSPARENT }).align_child(Center, Center).child(ui::icon(t, code, t.icon, t.p.fg)),
                id,
            ),
            move || {
                let mut p = Popups::write();
                p.month = if by == 0 { 0 } else { p.month + by };
            },
        )
    };
    let mut rows: Vec<Box<dyn Widget>> = Vec::new();
    rows.push(Box::new(ui::bold(t, big, t.p.fg).size(t.fs * 2.6)));
    rows.push(Box::new(ui::text(t, date, t.p.muted)));
    rows.push(Box::new(ui::spacer(1.0, 8.0)));
    rows.push(Box::new(
        Row::new(children![
            ui::on_left(ui::wrap(ui::bold(t, head, t.p.fg)), || Popups::write().month = 0),
            Row::new(children![arrow("cal:prev", 0xF0141, -1), arrow("cal:next", 0xF0142, 1)]).gap(4.0)
        ])
        .width(300.0)
        .justify(SpaceBetween)
        .align(Center),
    ));
    let names_en = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"];
    let names_ru = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"];
    let mut week: Vec<Box<dyn Widget>> = Vec::new();
    for i in 0..7 {
        let d = if monday { i } else { (i + 6) % 7 };
        let n = if t.c.ru() { names_ru[d] } else { names_en[d] };
        week.push(Box::new(Rectangle::new().width(cell).height(26.0).align_child(Center, Center).child(ui::text(t, n, t.p.dim).size(t.fs - 2.0))));
    }
    rows.push(Box::new(Row::new(week)));
    let grid = month_grid(y, mo, monday);
    for w in 0..6 {
        let mut line: Vec<Box<dyn Widget>> = Vec::new();
        for (d, inside) in &grid[w * 7..w * 7 + 7] {
            let today = *inside && shift == 0 && *d == now.day;
            let color = if today { t.p.bg } else if *inside { t.p.fg } else { t.p.faint };
            let txt = ui::text(t, d.to_string(), color);
            let txt = if today { txt.weight(Weight::Bold) } else { txt };
            let c = Rectangle::new().width(cell).height(34.0).align_child(Center, Center).child(
                Rectangle::new().width(32.0).height(32.0).radius(Full).fill(if today { t.p.accent } else { amane::Color::TRANSPARENT }).align_child(Center, Center).child(txt),
            );
            line.push(Box::new(c));
        }
        rows.push(Box::new(Row::new(line)));
    }
    Column::new(rows).gap(2.0)
}

// ── звук

fn mixer(t: &Tk, input: bool) -> Column {
    let cur = crate::pw::Pw::read().current(input).map(|n| n.desc).unwrap_or_default();
    Column::new(children![
        ui::menu_header::<POPUP>(t, 340.0, if input { ic::MIC } else { ic::VOL_HIGH }, if input { "Microphone" } else { "Sound" }, &cur, "sound"),
        crate::mixer::mixer::<POPUP>(t, 340.0, input, true)
    ])
    .gap(10.0)
}

// ── сеть

fn network(t: &Tk) -> Column {
    let nt = crate::net::Net::read();
    let status = match nt.kind {
        crate::net::Kind::Ethernet => format!("{} · {}", t.tr("Ethernet", "Проводная сеть"), nt.iface),
        crate::net::Kind::Wifi => format!("Wi-Fi · {}", if nt.ssid.is_empty() { &nt.iface } else { &nt.ssid }),
        crate::net::Kind::None => t.tr("Not connected", "Нет подключения").to_string(),
    };
    let details: Vec<(String, String)> = [
        (t.tr("Address", "Адрес"), nt.ip.clone()),
        (t.tr("Speed", "Скорость"), nt.speed.clone()),
    ]
    .into_iter()
    .filter(|(_, v)| !v.is_empty())
    .map(|(k, v)| (k.to_string(), v))
    .collect();
    drop(nt);
    let n = Network::read();
    // список сетей Wi-Fi — через NetworkManager (если он есть)
    let nm = n.wifi_enabled() || !n.access_points().is_empty();
    let wifi_on = n.wifi_enabled();
    let mut rows: Vec<Box<dyn Widget>> = Vec::new();
    let head: Box<dyn Widget> = if nm {
        Box::new(Row::new(children![ui::text(t, "Wi-Fi", t.p.fg).size(t.fs - 1.0), ui::switch::<POPUP>(t, "net:wifi", wifi_on, move || Network::set_wifi(!wifi_on))]).gap(8.0).align(Center))
    } else {
        Box::new(ui::spacer(1.0, 1.0))
    };
    rows.push(Box::new(
        Row::new(vec![
            Box::new(Column::new(children![title(t, t.tr("Network", "Сеть")), ui::text(t, status, t.p.muted).size(t.fs - 1.0)]).gap(2.0)) as Box<dyn Widget>,
            head,
        ])
        .width(320.0)
        .justify(SpaceBetween)
        .align(Center),
    ));
    for (k, v) in details {
        rows.push(Box::new(
            Row::new(children![ui::text(t, k, t.p.dim).size(t.fs - 1.0), ui::text(t, v, t.p.fg).size(t.fs - 1.0)])
                .width(320.0)
                .justify(SpaceBetween),
        ));
    }
    rows.push(Box::new(ui::spacer(1.0, 8.0)));
    let ask = Popups::read().ask_ssid.clone();
    let mut aps: Vec<&amane::AccessPoint> = n.access_points().iter().filter(|a| !a.ssid().is_empty()).collect();
    aps.sort_by(|a, b| b.active().cmp(&a.active()).then(b.strength().cmp(&a.strength())));
    aps.dedup_by(|a, b| a.ssid() == b.ssid());
    for ap in aps.into_iter().take(8) {
        let ssid = ap.ssid().to_string();
        let id = format!("ap:{ssid}");
        let hov = ui::hovered::<POPUP>(&id);
        let lock = if ap.secured() { format!("  {}", ui::glyph(ic::LOCK)) } else { String::new() };
        let label = format!("{}{}", ssid, lock);
        let right = if ap.active() { t.tr("connected", "подключено").to_string() } else { format!("{}%", ap.strength()) };
        let (secured, saved, active) = (ap.secured(), ap.saved(), ap.active());
        let s2 = ssid.clone();
        let row = Rectangle::new()
            .width(320.0)
            .height(34.0)
            .radius(8.0)
            .fill(if active { t.p.surface_hi } else if hov { t.p.surface } else { amane::Color::TRANSPARENT })
            .padding(Padding { top: 0.0, right: 10.0, bottom: 0.0, left: 10.0 })
            .child(
                Row::new(children![
                    Rectangle::new().width(Parent).height(34.0).align_child(Start, Center).child(ui::text(t, label, t.p.fg).elide()),
                    ui::text(t, right, t.p.dim).size(t.fs - 2.0)
                ])
                .width(Parent)
                .height(34.0)
                .align(Center),
            );
        let row = ui::on_left(ui::track::<POPUP>(row, id), move || {
            if active {
                Network::disconnect();
            } else if secured && !saved {
                let mut p = Popups::write();
                p.ask_ssid = s2.clone();
                p.password.clear();
            } else {
                Network::connect(&s2, None);
            }
        });
        rows.push(Box::new(row));
        if ask == ssid {
            let s3 = ssid.clone();
            let field = Rectangle::new()
                .width(320.0)
                .height(36.0)
                .radius(8.0)
                .fill(t.p.surface_hi)
                .border(1.0, theme_alpha(t.p.accent, 0.55))
                .padding(Padding { top: 0.0, right: 10.0, bottom: 0.0, left: 10.0 })
                .align_child(Start, Center)
                .child(
                    TextInput::new("wifi-password")
                        .password()
                        .focused()
                        .size(t.fs)
                        .color(t.p.fg)
                        .placeholder(t.tr("Password — Enter to connect", "Пароль — Enter, чтобы подключиться"))
                        .on_submit(move |pw| {
                            Network::connect(&s3, Some(&pw));
                            TextInput::set_text("wifi-password", "");
                            Popups::write().ask_ssid.clear();
                        }),
                );
            rows.push(Box::new(field));
        }
    }
    if nm && n.access_points().is_empty() && wifi_on {
        rows.push(Box::new(ui::text(t, t.tr("Searching for networks…", "Ищу сети…"), t.p.dim).size(t.fs - 1.0)));
    }
    drop(n);
    rows.push(Box::new(ui::spacer(1.0, 8.0)));
    rows.push(Box::new(ui::button::<POPUP>(t, "net:editor", t.tr("Connection settings", "Параметры подключений"), false, || after_close("nm-connection-editor"))));
    Column::new(rows).gap(2.0)
}

fn theme_alpha(c: amane::Color, a: f32) -> amane::Color {
    crate::theme::alpha(c, a)
}

// ── уведомления

fn center(t: &Tk) -> Column {
    let dnd = NotifState::read().dnd;
    let list = Notifications::read();
    let count = list.list().len();
    let head = Row::new(children![
        title(t, t.tr("Notifications", "Уведомления")),
        Row::new(children![
            ui::text(t, t.tr("Do not disturb", "Не беспокоить"), t.p.muted).size(t.fs - 1.0),
            ui::switch::<POPUP>(t, "nc:dnd", dnd, notifs::toggle_dnd),
            ui::round_btn::<POPUP>(t, "nc:clear", ic::TRASH, Notifications::clear)
        ])
        .gap(8.0)
        .align(Center)
    ])
    .width(380.0)
    .justify(SpaceBetween)
    .align(Center);
    let mut cards: Vec<Box<dyn Widget>> = Vec::new();
    let mut total = 0.0;
    for n in list.list().iter().rev() {
        let c = notifs::card::<POPUP>(t, n, 380.0, false, Notifications::dismiss);
        total += c.height + 8.0;
        cards.push(Box::new(c.widget));
    }
    drop(list);
    let max_h = 520.0;
    let view_h = total.min(max_h).max(if count == 0 { 80.0 } else { 0.0 });
    let body: Rectangle = if count == 0 {
        Rectangle::new().width(380.0).height(view_h).align_child(Center, Center).child(ui::text(t, t.tr("No notifications", "Уведомлений нет"), t.p.dim))
    } else {
        let off = Popups::read().notif_scroll.clamp(0.0, (total - max_h).max(0.0));
        let limit = (total - max_h).max(0.0);
        Rectangle::new()
            .width(380.0)
            .height(view_h)
            .clip()
            .on_scroll(move |s| {
                let mut p = Popups::write();
                p.notif_scroll = (p.notif_scroll + s.y * 40.0).clamp(0.0, limit);
            })
            .child(Column::new(cards).gap(8.0).translate_hack(-off))
    };
    Column::new(children![head, ui::spacer(1.0, 10.0), body])
}

// Column не умеет translate — двигаем обёрткой
trait TranslateHack {
    fn translate_hack(self, y: f32) -> Rectangle;
}

impl TranslateHack for Column {
    fn translate_hack(self, y: f32) -> Rectangle {
        let (w, h) = ui::size_of(&self);
        Rectangle::new().width(w).height(h).translate(0.0, y).child(self)
    }
}

// ── центр управления

fn tile(t: &Tk, id: &str, code: u32, label: &str, sub: &str, on: bool, f: impl Fn() + 'static) -> Rectangle {
    let hov = ui::hovered::<POPUP>(id);
    let fg = if on { t.p.bg } else { t.p.fg };
    let w = (380.0 - 3.0 * 8.0) / 4.0;
    let r = Rectangle::new()
        .width(w)
        .height(76.0)
        .radius(14.0)
        .fill(if on { t.p.accent } else if hov { t.p.surface_hi } else { t.p.surface })
        .padding(12.0)
        .child(
            Column::new(children![
                ui::icon(t, code, t.icon + 3.0, fg),
                ui::spacer(1.0, 10.0),
                Rectangle::new().width(w - 24.0).height(t.fs).child(ui::bold(t, label, fg).size(t.fs - 2.0).elide()),
                Rectangle::new().width(w - 24.0).height(t.fs - 2.0).child(ui::text(t, sub, if on { theme_alpha(t.p.bg, 0.7) } else { t.p.dim }).size(t.fs - 4.0).elide())
            ])
            .gap(2.0),
        );
    ui::on_left(ui::track::<POPUP>(r, id), f)
}

pub fn toggle_dark() {
    let s = Settings::read().c.scheme.clone();
    if s == "light" {
        let last = notifs::load_state().get("lastDark").str_or("dark");
        settings::save_key("scheme", Json::Str(last));
    } else {
        notifs::save_state("lastDark", Json::Str(s));
        settings::save_key("scheme", Json::Str("light".into()));
    }
}

fn control(t: &Tk) -> Column {
    let user = std::env::var("USER").unwrap_or_default();
    let now = Clock::read().now();
    let initial = user.chars().next().map(|c| c.to_uppercase().collect::<String>()).unwrap_or_else(|| "?".into());
    let avatar = Rectangle::new().width(40.0).height(40.0).radius(Full).fill(t.p.accent).align_child(Center, Center).child(ui::bold(t, initial, t.p.bg).size(18.0));
    let who = Column::new(children![
        Rectangle::new().width(200.0).height(t.fs + 4.0).child(ui::bold(t, user, t.p.fg).size(t.fs + 1.0).elide()),
        ui::text(t, clock::format("dddd, d MMMM", &now, t.c.ru()), t.p.dim).size(t.fs - 2.0)
    ])
    .gap(1.0);
    let head = Row::new(children![
        Row::new(children![avatar, who]).gap(12.0).align(Center),
        Row::new(children![
            ui::round_btn::<POPUP>(t, "cc:lock", ic::LOCK, || after_close("pgrep -x swaylock >/dev/null || swaylock -f -c 151515")),
            ui::round_btn::<POPUP>(t, "cc:power", ic::POWEROFF, || {
                close();
                crate::power::toggle(&[]);
            })
        ])
        .gap(8.0)
    ])
    .width(380.0)
    .justify(SpaceBetween)
    .align(Center);

    let dnd = NotifState::read().dnd;
    // сеть — как в баре (без NetworkManager тоже); клик — меню сети
    let (net_on, net_icon, net_label, net_sub) = {
        let n = crate::net::Net::read();
        match n.kind {
            crate::net::Kind::Ethernet => (true, ic::ETHERNET, t.tr("Ethernet", "Сеть").to_string(), n.iface.clone()),
            crate::net::Kind::Wifi => (true, ic::WIFI, "Wi-Fi".to_string(), if n.ssid.is_empty() { n.iface.clone() } else { n.ssid.clone() }),
            crate::net::Kind::None => (false, ic::OFFLINE, t.tr("Network", "Сеть").to_string(), t.tr("Offline", "Нет сети").to_string()),
        }
    };
    let bt = Bluetooth::read();
    let (bt_ok, bt_on) = (bt.available(), bt.powered());
    let bt_dev = bt.devices().iter().find(|d| d.connected()).map(|d| d.name().to_string());
    drop(bt);
    let light = Settings::read().c.scheme == "light";
    let scheme = Settings::read().c.scheme.clone();
    let on_off = |b: bool| if b { t.tr("On", "Вкл") } else { t.tr("Off", "Выкл") };
    let tiles1 = Row::new(children![
        tile(t, "cc:dnd", if dnd { ic::BELL_OFF } else { ic::BELL }, t.tr("Focus", "Не беспокоить"), on_off(dnd), dnd, notifs::toggle_dnd),
        tile(t, "cc:net", net_icon, &net_label, &net_sub, net_on, || {
            let out = Popups::read().output.clone();
            toggle_at("network", &out);
        }),
        tile(
            t,
            "cc:bt",
            0xF00AF,
            "Bluetooth",
            &if !bt_ok { t.tr("No adapter", "Нет адаптера").to_string() } else { bt_dev.unwrap_or_else(|| on_off(bt_on).to_string()) },
            bt_on,
            move || if bt_ok { Bluetooth::set_powered(!bt_on) }
        ),
        tile(t, "cc:dark", 0xF0594, t.tr("Dark", "Тёмная"), &scheme, !light, toggle_dark)
    ])
    .gap(8.0);
    let tiles2 = Row::new(children![
        tile(t, "cc:snip", 0xF0104, t.tr("Snip", "Снимок"), t.tr("Region", "Область"), false, || after_close("niri msg action screenshot")),
        tile(t, "cc:clip", ic::CLIPBOARD, t.tr("Clipboard", "Буфер"), "Super+V", false, || {
            close();
            crate::clipboard::toggle(&[]);
        }),
        tile(t, "cc:wall", ic::IMAGE, t.tr("Wallpaper", "Обои"), "Super+W", false, || {
            close();
            crate::wallpaper::toggle(&[]);
        }),
        tile(t, "cc:shell", 0xF04E1, "Quickshell", t.tr("Switch shell", "Сменить шелл"), false, || {
            after_close("rexilone-shell use quickshell")
        })
    ])
    .gap(8.0);

    let a = Audio::read();
    let (v, muted) = (a.volume(), a.muted());
    drop(a);
    let vol = Row::new(children![
        ui::round_btn::<POPUP>(t, "cc:mute", ui::volume_icon(false, muted, v), Audio::toggle_mute),
        ui::slider::<POPUP>(t, "cc:vol", 380.0 - 36.0 - 12.0 - 56.0, v as f32 / 150.0, muted, v > 100, |r| {
            let mut nv = (r * 150.0).round() as u8;
            if (nv as i32 - 100).abs() <= 2 {
                nv = 100;
            }
            Audio::set_volume(nv)
        }),
        Rectangle::new().width(44.0).height(20.0).align_child(End, Center).child(ui::text(t, format!("{v}%"), t.p.muted).size(t.fs - 1.0))
    ])
    .gap(12.0)
    .align(Center);
    let mut rows: Vec<Box<dyn Widget>> = vec![Box::new(head), Box::new(ui::spacer(1.0, 4.0)), Box::new(tiles1), Box::new(tiles2), Box::new(vol)];
    let br = Brightness::read();
    if br.present() {
        let b = br.percent();
        rows.push(Box::new(
            Row::new(children![
                Rectangle::new().width(36.0).height(36.0).align_child(Center, Center).child(ui::icon(t, ic::BRIGHTNESS, t.icon, t.p.fg)),
                ui::slider::<POPUP>(t, "cc:br", 380.0 - 36.0 - 12.0 - 56.0, b as f32 / 100.0, false, false, |r| Brightness::set((r * 100.0).round().max(1.0) as u8)),
                Rectangle::new().width(44.0).height(20.0).align_child(End, Center).child(ui::text(t, format!("{b}%"), t.p.muted).size(t.fs - 1.0))
            ])
            .gap(12.0)
            .align(Center),
        ));
    }
    drop(br);
    let m = Media::read();
    if !m.title().is_empty() {
        let playing = m.playing();
        let label = Column::new(children![
            Rectangle::new().width(380.0 - 140.0).height(t.fs + 4.0).child(ui::bold(t, m.title(), t.p.fg).elide()),
            Rectangle::new().width(380.0 - 140.0).height(t.fs).child(ui::text(t, m.artist(), t.p.dim).size(t.fs - 2.0).elide())
        ])
        .gap(2.0);
        let player = Rectangle::new().width(380.0).height(64.0).radius(14.0).fill(t.p.surface).padding(12.0).child(
            Row::new(children![
                label,
                Row::new(children![
                    ui::round_btn::<POPUP>(t, "cc:prev", 0xF04AE, Media::previous),
                    ui::round_btn::<POPUP>(t, "cc:play", if playing { 0xF03E4 } else { 0xF040A }, Media::play_pause),
                    ui::round_btn::<POPUP>(t, "cc:next", 0xF04AD, Media::next)
                ])
                .gap(4.0)
            ])
            .width(Parent)
            .justify(SpaceBetween)
            .align(Center),
        );
        rows.push(Box::new(player));
    }
    Column::new(rows).gap(12.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn month_shifts() {
        assert_eq!(shift_month(2026, 10, 0), (2026, 10));
        assert_eq!(shift_month(2026, 10, 3), (2027, 1));
        assert_eq!(shift_month(2026, 1, -1), (2025, 12));
        assert_eq!(shift_month(2026, 1, -25), (2023, 12));
    }

    #[test]
    fn days_and_leap_years() {
        assert_eq!(days_in(2024, 2), 29);
        assert_eq!(days_in(2026, 2), 28);
        assert_eq!(days_in(1900, 2), 28);
        assert_eq!(days_in(2000, 2), 29);
        assert_eq!(days_in(2026, 4), 30);
        assert_eq!(days_from_civil(1970, 1, 1), 0);
        assert_eq!(days_from_civil(2026, 10, 17) * 86400, 1792195200);
    }

    #[test]
    fn october_2026_grid() {
        // 1 октября 2026 — четверг
        let g = month_grid(2026, 10, true);
        assert_eq!(g.len(), 42);
        assert_eq!(&g[..4], &[(28, false), (29, false), (30, false), (1, true)]);
        assert_eq!(g.iter().filter(|(_, m)| *m).count(), 31);
        // неделя с воскресенья — на день правее
        let s = month_grid(2026, 10, false);
        assert_eq!(s[4], (1, true));
        assert_eq!(s[0], (27, false));
    }

    #[test]
    fn month_starting_monday_has_no_lead() {
        // 1 июня 2026 — понедельник
        let g = month_grid(2026, 6, true);
        assert_eq!(g[0], (1, true));
        let s = month_grid(2026, 6, false);
        assert_eq!(s[0], (31, false));
        assert_eq!(s[1], (1, true));
    }
}
