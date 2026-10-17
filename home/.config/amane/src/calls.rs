// входящий звонок с телефона (PhoneCall.qml) и быстрый ответ на уведомление (PhoneReply.qml):
// карточки сверху на основном мониторе

use std::sync::Mutex;

use amane::{Center, Vertical, Column, Key, Keyboard, Layer, LayerWindow, Monitor, Padding, Rectangle, Row, Service, Shadow, TextInput, Widget, Zone, children};

use crate::json::Json;
use crate::look::{self, Tk};
use crate::rexlink::{self as rl, Rexlink};
use crate::settings::Settings;
use crate::ui::{self, ic};

type W = Box<dyn Widget>;

fn bx(w: impl Widget + 'static) -> W {
    Box::new(w)
}

fn primary() -> String {
    let outs = crate::niri::Niri::read().s.outputs.clone();
    Settings::read().c.primary(&outs)
}

fn hidden() -> LayerWindow {
    LayerWindow::new().width(1.0).height(1.0).layer(Layer::Overlay).namespace("rexilone-call").visible(false).child(Rectangle::new().width(1.0).height(1.0))
}

fn btn(t: &Tk, id: &str, w: f32, icon: u32, label: &str, kind: u8, f: impl Fn() + 'static) -> Rectangle {
    let hov = ui::hovered::<{ ui::NOTIF }>(id);
    let (bg, fg) = match kind {
        1 => (if hov { t.p.muted } else { t.p.fg }, t.p.bg),
        2 => (if hov { t.p.surface_hi2 } else { t.p.surface_hi }, t.p.urgent),
        _ => (if hov { t.p.surface_hi2 } else { t.p.surface_hi }, t.p.fg),
    };
    ui::on_left(
        ui::track::<{ ui::NOTIF }>(
            Rectangle::new()
                .width(w)
                .height(36.0)
                .radius(10.0)
                .fill(bg)
                .cursor(amane::Pointer)
                .align_child(Center, Center)
                .child(Row::new(children![ui::icon(t, icon, t.icon, fg), ui::text(t, t.t(label), fg).size(t.fs - 1.0)]).gap(8.0).align(Center)),
            id,
        ),
        f,
    )
}

// ── входящий звонок
pub fn call_view(m: &Monitor) -> LayerWindow {
    let tk = look::tk();
    let t = &tk;
    let r = Rexlink::read();
    let show = r.ringing() && t.c.module_on("phoneCalls", true) && m.name == primary();
    let call = r.call.clone();
    let dev = r.dev().map(|d| d.name).unwrap_or_default();
    drop(r);
    if !show {
        return hidden();
    }
    amane::request_frame();
    let ms = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0) % 1000;
    let x = if ms < 500 { ms as f32 / 500.0 } else { (1000 - ms) as f32 / 500.0 };
    let pulse = 1.0 + 0.12 * (0.5 - 0.5 * (x * std::f32::consts::PI).cos());
    let (name, number) = (call.get("name").str_or(""), call.get("number").str_or(""));
    let who = if !name.is_empty() { name.clone() } else if !number.is_empty() { number.clone() } else { t.t("Unknown") };
    let sub = format!("{}{} · {}", t.t("Incoming call"), if !name.is_empty() && !number.is_empty() { format!(" · {number}") } else { String::new() }, if dev.is_empty() { t.t("phone") } else { dev });
    let w: f32 = 420.0;
    let iw = w - 36.0;
    let bw = ((iw - 16.0) / 3.0).floor();
    let col = Column::new(children![
        Row::new(children![
            Rectangle::new().width(48.0).height(48.0).radius(24.0).fill(t.p.warn).scale(pulse).align_child(Center, Center).child(ui::icon(t, 0xF03F2, 22.0, t.p.bg)),
            Column::new(children![crate::prefs::w::line(t, &who, t.fs + 4.0, t.p.fg, iw - 62.0, true), crate::prefs::w::line(t, &sub, t.fs - 2.0, t.p.dim, iw - 62.0, false)]).gap(2.0)
        ])
        .gap(14.0)
        .align(Center),
        Row::new(children![
            btn(t, "call:silence", bw, ic::VOL_MUTE, "Silence", 0, || rl::call_action("silence")),
            btn(t, "call:decline", bw, 0xF03F4, "Decline", 2, || rl::call_action("reject")),
            btn(t, "call:answer", bw, 0xF03F2, "Answer", 1, || rl::call_action("accept"))
        ])
        .gap(8.0)
    ])
    .gap(14.0);
    let (_, ch) = ui::size_of(&col);
    let card = Rectangle::new()
        .width(w)
        .height(ch + 32.0)
        .radius(20.0)
        .fill(t.panel)
        .border(1.0, t.p.warn)
        .shadow(Shadow::drop("#000000").opacity(0.5).blur(30.0).offset(0.0, 8.0))
        .padding(Padding { top: 16.0, right: 18.0, bottom: 16.0, left: 18.0 })
        .child(col);
    LayerWindow::new()
        .width(w + 20.0)
        .height(ch + 32.0 + 30.0)
        .anchor_vertical(Vertical::Top)
        .layer(Layer::Overlay)
        .space(Zone::Respect)
        .namespace("rexilone-call")
        .child(Rectangle::new().width(w + 20.0).height(ch + 62.0).padding(Padding { top: 10.0, right: 10.0, bottom: 20.0, left: 10.0 }).child(card))
}

// ── быстрый ответ: запрос приходит из уведомления телефона на рабочем столе
static REPLY: Mutex<(usize, Option<Json>, String)> = Mutex::new((0, None, String::new()));

fn close_reply() {
    let mut r = REPLY.lock().unwrap();
    r.1 = None;
    r.2.clear();
    drop(r);
    TextInput::set_text("phone-quick-reply", "");
    // перерисовать
    let n = Rexlink::read().reply_requests.len();
    if n > 0 {
        let v = Rexlink::read().reply_requests.clone();
        Rexlink::write().reply_requests = v;
    }
}

fn send_reply() {
    let (req, text) = {
        let r = REPLY.lock().unwrap();
        (r.1.clone(), r.2.clone())
    };
    if let Some(q) = req {
        if !text.trim().is_empty() {
            rl::notif_reply(&q.get("key").str_or(""), q.get("action").num_or(0.0) as i64, &text, &q.get("device").str_or(""));
        }
    }
    close_reply();
}

pub fn reply_view(m: &Monitor) -> LayerWindow {
    let tk = look::tk();
    let t = &tk;
    let reqs = Rexlink::read().reply_requests.clone();
    let req = {
        let mut r = REPLY.lock().unwrap();
        // новый запрос — показать его
        if reqs.len() > r.0 {
            r.0 = reqs.len();
            r.1 = reqs.last().cloned();
            r.2.clear();
        } else if reqs.len() < r.0 {
            r.0 = reqs.len();
        }
        r.1.clone()
    };
    let Some(q) = req.filter(|_| m.name == primary()) else {
        return LayerWindow::new().width(1.0).height(1.0).layer(Layer::Overlay).namespace("rexilone-notifications-phone").visible(false).child(Rectangle::new().width(1.0).height(1.0));
    };
    let w: f32 = 460.0;
    let iw = w - 32.0;
    let mut col: Vec<W> = vec![bx(Row::new(children![
        ui::icon(t, 0xF045A, t.icon + 2.0, t.p.accent),
        crate::prefs::w::line(t, &format!("{}   ·   {}", t.t("Reply"), q.get("app").str_or("")), t.fs - 2.0, t.p.dim, iw - 40.0, false)
    ])
    .gap(10.0)
    .align(Center))];
    let title = q.get("title").str_or("");
    if !title.is_empty() {
        col.push(bx(crate::prefs::w::line(t, &title, t.fs, t.p.fg, iw, true)));
    }
    let text = q.get("text").str_or("");
    if !text.is_empty() {
        col.push(bx(crate::prefs::w::para(t, &text.lines().take(3).collect::<Vec<_>>().join("\n"), t.fs - 1.0, t.p.muted, iw)));
    }
    let input = TextInput::new("phone-quick-reply")
        .width(iw - 20.0 - 48.0)
        .size(t.fs - 1.0)
        .color(t.p.fg)
        .placeholder(t.t("Reply… (Enter — send, Esc — cancel)"))
        .focused()
        .on_change(|s| REPLY.lock().unwrap().2 = s)
        .on_submit(|_| send_reply());
    let sh = ui::hovered::<{ ui::NOTIF }>("reply:send");
    col.push(bx(Row::new(children![
        Rectangle::new().width(iw - 46.0).height(38.0).radius(10.0).fill(t.p.surface_hi).border(1.0, t.p.line).padding(Padding { top: 0.0, right: 10.0, bottom: 0.0, left: 12.0 }).align_child(amane::Start, Center).child(input),
        ui::on_left(ui::track::<{ ui::NOTIF }>(Rectangle::new().width(38.0).height(38.0).radius(10.0).fill(if sh { t.p.muted } else { t.p.fg }).cursor(amane::Pointer).align_child(Center, Center).child(ui::icon(t, 0xF048A, t.icon, t.p.bg)), "reply:send"), send_reply)
    ])
    .gap(8.0)
    .align(Center)));
    let c = Column::new(col).gap(10.0);
    let (_, ch) = ui::size_of(&c);
    let card = Rectangle::new()
        .width(w)
        .height(ch + 32.0)
        .radius(18.0)
        .fill(t.panel)
        .border(1.0, t.p.surface_hi2)
        .shadow(Shadow::drop("#000000").opacity(0.5).blur(30.0).offset(0.0, 8.0))
        .padding(16.0)
        .child(c);
    // слой — как у уведомлений телефона: скрывается с демонстрации экрана вместе с ними
    LayerWindow::new()
        .width(w + 20.0)
        .height(ch + 32.0 + 80.0)
        .anchor_vertical(Vertical::Top)
        .layer(Layer::Overlay)
        .space(Zone::Respect)
        .namespace("rexilone-notifications-phone")
        .keyboard(Keyboard::Exclusive)
        .on_key(|k| {
            if k == Key::Escape {
                close_reply()
            }
        })
        .child(Rectangle::new().width(w + 20.0).height(ch + 112.0).padding(Padding { top: 60.0, right: 10.0, bottom: 20.0, left: 10.0 }).child(card))
}
