// меню телефона в баре (PhoneMenu.qml): состояние, быстрые действия, медиа и уведомления с телефона

use std::sync::Mutex;

use amane::{Center, Column, End, Padding, Pointer, Rectangle, Row, ScrollArea, Service, Start, TextInput, Weight, Widget, children};

use crate::json::Json;
use crate::look::Tk;
use crate::popups;
use crate::rexlink::{self as rl, Rexlink};
use crate::ui::{self, POPUP, ic};

type W = Box<dyn Widget>;

fn bx(w: impl Widget + 'static) -> W {
    Box::new(w)
}

pub const WIDTH: f32 = 400.0;

// быстрый ответ: какое уведомление и какое действие
static REPLY: Mutex<(String, i64, String)> = Mutex::new((String::new(), -1, String::new()));

pub fn ago(ms: f64, now: f64) -> String {
    if ms <= 0.0 {
        return String::new();
    }
    let min = ((now - ms) / 60000.0).floor() as i64;
    if min < 1 {
        "now".into()
    } else if min < 60 {
        format!("{min}m")
    } else if min < 1440 {
        format!("{}h", min / 60)
    } else {
        format!("{}d", min / 1440)
    }
}

fn act(t: &Tk, w: f32, id: &'static str, icon: u32, label: &str, on: bool, f: impl Fn() + 'static) -> Rectangle {
    let hov = ui::hovered::<POPUP>(id);
    let r = Rectangle::new()
        .width(w)
        .height(62.0)
        .radius(12.0)
        .fill(if on { t.p.accent } else if hov { t.p.surface_hi } else { t.p.surface })
        .cursor(Pointer)
        .align_child(Center, Center)
        .child(Column::new(children![ui::icon(t, icon, t.icon + 2.0, if on { t.p.bg } else { t.p.fg }), ui::text(t, t.t(label), if on { t.p.bg } else { t.p.muted }).size(t.fs - 3.0)]).gap(5.0).align(Center));
    ui::on_left(ui::track::<POPUP>(r, id), f)
}

fn send_reply() {
    let (key, i, text) = REPLY.lock().unwrap().clone();
    if !text.trim().is_empty() {
        rl::notif_reply(&key, i, &text, "");
    }
    *REPLY.lock().unwrap() = (String::new(), -1, String::new());
    TextInput::set_text("phone-reply", "");
    popups::Popups::write().notif_scroll += 0.0;
}

pub fn view(t: &Tk) -> Column {
    let w = WIDTH;
    let r = Rexlink::read();
    let dev = r.dev();
    let (connected, installed, online) = (r.connected, r.installed, r.online());
    let s = r.status.clone();
    let media = r.media.clone();
    let notifs = r.notifs.arr().to_vec();
    let cam_on = r.camera.get("running").bool_or(false);
    let devices = r.devices.arr().to_vec();
    let current = r.current.clone();
    drop(r);
    let ringing = dev.as_ref().is_some_and(|d| d.raw.get("ringing").bool_or(false));
    let mut col: Vec<W> = Vec::new();

    // ── заголовок; несколько устройств — переключатель
    let sub = if !connected {
        t.t("Rexlink isn't running")
    } else if let Some(d) = &dev {
        format!("{}  ·  {}", d.model, t.t(if online { "connected" } else { "offline" }))
    } else {
        t.t("No paired devices")
    };
    let title = dev.as_ref().map(|d| d.name.clone()).unwrap_or_else(|| "Rexlink".into());
    let mut head: Vec<W> = Vec::new();
    let multi = devices.len() > 1;
    head.push(bx(ui::menu_header::<POPUP>(t, w - if multi { 48.0 } else { 0.0 }, rl::kind_icon(&dev.as_ref().map(|d| d.kind.clone()).unwrap_or_default()), &title, &sub, "phone")));
    if multi {
        // следующее устройство по кругу
        let ids: Vec<String> = devices.iter().map(|d| d.get("id").str_or("")).collect();
        let next = ids.iter().position(|i| *i == current).map(|p| ids[(p + 1) % ids.len()].clone()).unwrap_or_default();
        let hov = ui::hovered::<POPUP>("phone:next-dev");
        head.push(bx(ui::on_left(
            ui::track::<POPUP>(
                Rectangle::new().width(40.0).height(32.0).radius(10.0).fill(if hov { t.p.surface_hi2 } else { t.p.surface_hi }).cursor(Pointer).align_child(Center, Center).child(ui::icon(t, 0xF04E1, t.icon, t.p.fg)),
                "phone:next-dev",
            ),
            move || rl::select(&next),
        )));
    }
    col.push(bx(Row::new(head).gap(8.0).align(Center)));

    // Rexlink не запущен
    if !connected {
        let mut row: Vec<W> = vec![bx(Rectangle::new().width(w - 28.0 - if installed { 80.0 } else { 0.0 }).height(32.0).align_child(Start, Center).child(ui::text(t, t.t(if installed { "Start Rexlink to connect your phone" } else { "Rexlink is not installed" }), t.p.dim).size(t.fs - 1.0)))];
        if installed {
            row.push(bx(ui::button::<POPUP>(t, "phone:start", &t.t("Start"), true, rl::start)));
        }
        col.push(bx(Rectangle::new().width(w).height(60.0).radius(12.0).fill(t.p.surface).padding(14.0).child(Row::new(row).align(Center))));
    }

    if connected && online {
        // ── состояние
        let lvl = s.get("battery").num().map(|x| x as i64);
        let charging = s.get("charging").bool_or(false);
        let wifi = s.get("wifi").clone();
        let cell = s.get("cell").clone();
        let net_wifi = s.get("net").str() == Some("wifi");
        let wl = if net_wifi { format!("{} {} · {}/4", ui::glyph(ic::WIFI), Some(wifi.get("ssid").str_or("")).filter(|x| !x.is_empty()).unwrap_or("Wi-Fi".into()), wifi.get("level").num_or(0.0)) } else { format!("{} {}", ui::glyph(ic::WIFI), t.t("off")) };
        let cl = format!("{} {} {} · {}/4", ui::glyph(0xF08BD), Some(cell.get("operator").str_or("")).filter(|x| !x.is_empty()).unwrap_or("—".into()), cell.get("gen").str_or(""), cell.get("level").num_or(0.0));
        let right = Column::new(children![ui::text(t, wl, if net_wifi { t.p.fg } else { t.p.dim }).size(t.fs - 2.0), ui::text(t, cl, t.p.dim).size(t.fs - 2.0)]).gap(3.0).align(End);
        let (rw, _) = ui::size_of(&right);
        let temp = s.get("temp").num().map(|x| format!("{x}°C")).unwrap_or_else(|| "—°C".into());
        let batt = Row::new(children![
            ui::icon(t, rl::battery_icon(lvl.unwrap_or(-1), charging), 26.0, if lvl.unwrap_or(100) <= 15 && !charging { t.p.urgent } else { t.p.accent }),
            Column::new(children![
                ui::bold(t, format!("{}%", lvl.map(|x| x.to_string()).unwrap_or_else(|| "—".into())), t.p.fg).size(t.fs + 5.0),
                ui::text(t, if charging { t.t("charging") } else { temp }, t.p.dim).size(t.fs - 3.0)
            ])
        ])
        .gap(8.0)
        .align(Center);
        let (bw, _) = ui::size_of(&batt);
        col.push(bx(Rectangle::new().width(w).height(70.0).radius(12.0).fill(t.p.surface).padding(Padding { top: 0.0, right: 16.0, bottom: 0.0, left: 16.0 }).child(
            Row::new(vec![bx(batt), bx(Rectangle::new().width((w - 32.0 - bw - rw).max(0.0)).height(10.0)), bx(right)]).height(70.0).align(Center),
        )));

        // ── быстрые действия
        let aw = ((w - 16.0) / 3.0).floor();
        let r1 = Row::new(children![
            act(t, aw, "phone:find", 0xF08D3, "Find", ringing, || rl::ring("")),
            act(t, aw, "phone:files", 0xF0552, "Send files", false, || {
                popups::close();
                rl::show("files");
            }),
            act(t, aw, "phone:clip", ic::CLIPBOARD, "Get clipboard", false, || rl::clipboard_pull(""))
        ])
        .gap(8.0);
        let r2 = Row::new(children![
            act(t, aw, "phone:screen", 0xF0379, "Screen", false, || {
                popups::close();
                rl::screen_start("");
                rl::show("screen");
            }),
            act(t, aw, "phone:cam", 0xF0100, if cam_on { "Webcam on" } else { "Webcam" }, cam_on, move || if cam_on { rl::camera_stop() } else { rl::camera_start("") }),
            act(t, aw, "phone:sms", 0xF0369, "Messages", false, || {
                popups::close();
                rl::show("messages");
            })
        ])
        .gap(8.0);
        col.push(bx(Column::new(children![r1, r2]).gap(8.0)));

        // ── медиа на телефоне
        let mt = media.get("title").str_or("");
        if !mt.is_empty() {
            let playing = media.get("playing").bool_or(false);
            let sub = [media.get("artist").str_or(""), media.get("app").str_or("")].into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join(" · ");
            let btn = |id: &'static str, a: &'static str, icon: u32| {
                let hov = ui::hovered::<POPUP>(id);
                ui::on_left(ui::track::<POPUP>(Rectangle::new().width(32.0).height(32.0).radius(16.0).fill(if hov { t.p.surface_hi2 } else { amane::Color::TRANSPARENT }).cursor(Pointer).align_child(Center, Center).child(ui::icon(t, icon, t.icon, t.p.fg)), id), move || rl::media_action(a, "", 0.0))
            };
            let tw = w - 22.0 - t.icon - 1.0 - 32.0 * 3.0 - 10.0 * 4.0;
            col.push(bx(Rectangle::new().width(w).height(58.0).radius(12.0).fill(t.p.surface).padding(Padding { top: 0.0, right: 8.0, bottom: 0.0, left: 14.0 }).child(
                Row::new(children![
                    ui::icon(t, 0xF075A, t.icon + 1.0, t.p.accent),
                    Column::new(children![crate::prefs::w::line(t, &mt, t.fs - 1.0, t.p.fg, tw, true), crate::prefs::w::line(t, &sub, t.fs - 3.0, t.p.dim, tw, false)]).width(tw),
                    btn("phone:prev", "prev", 0xF04AE),
                    btn("phone:play", "toggle", if playing { 0xF03E4 } else { 0xF040A }),
                    btn("phone:next", "next", 0xF04AD)
                ])
                .gap(10.0)
                .height(58.0)
                .align(Center),
            )));
        }

        // ── уведомления с телефона
        col.push(bx(ui::bold(t, format!("{} · {}", t.t("PHONE NOTIFICATIONS"), notifs.len()), t.p.dim).size(t.fs - 2.0)));
        if notifs.is_empty() {
            col.push(bx(ui::text(t, t.t("Nothing new"), t.p.faint).size(t.fs - 1.0)));
        } else {
            let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as f64).unwrap_or(0.0);
            let reply = REPLY.lock().unwrap().clone();
            let mut cards: Vec<W> = Vec::new();
            let iw = w - 24.0;
            for n in &notifs {
                let key = n.get("key").str_or("");
                let hid = format!("pn:{key}");
                let hov = ui::hovered::<POPUP>(&hid);
                let mut c: Vec<W> = Vec::new();
                let mut top: Vec<W> = vec![bx(crate::prefs::w::line(t, &format!("{}  ·  {}", n.get("app").str_or(""), ago(n.get("time").num_or(0.0), now)), t.fs - 3.0, t.p.dim, iw - 20.0, false))];
                if n.get("clearable").bool() != Some(false) {
                    let xid = format!("pnx:{key}");
                    let xh = ui::hovered::<POPUP>(&xid);
                    let k = key.clone();
                    top.push(bx(ui::on_left(ui::track::<POPUP>(Rectangle::new().width(16.0).height(16.0).cursor(Pointer).align_child(Center, Center).child(ui::icon(t, ic::CLOSE, t.fs - 1.0, if xh { t.p.urgent } else { t.p.dim })), xid), move || rl::notif_dismiss(&k, ""))));
                }
                c.push(bx(Row::new(top).gap(4.0).align(Center)));
                let title = n.get("title").str_or("");
                if !title.is_empty() {
                    c.push(bx(crate::prefs::w::line(t, &title, t.fs - 1.0, t.p.fg, iw, true)));
                }
                let body = n.get("text").str_or("");
                if !body.is_empty() {
                    let lines: Vec<&str> = body.lines().take(3).collect();
                    c.push(bx(crate::prefs::w::para(t, &lines.join("\n"), t.fs - 2.0, t.p.muted, iw)));
                }
                let replying = reply.0 == key;
                let actions = n.get("actions").arr().to_vec();
                if !actions.is_empty() && !replying {
                    let mut row: Vec<W> = Vec::new();
                    for a in &actions {
                        let i = a.get("i").num_or(0.0) as i64;
                        let is_reply = a.get("reply").bool_or(false);
                        let k = key.clone();
                        row.push(bx(ui::button::<POPUP>(t, &format!("pna:{key}:{i}"), &t.t(&a.get("title").str_or("")), false, move || {
                            if is_reply {
                                *REPLY.lock().unwrap() = (k.clone(), i, String::new());
                            } else {
                                rl::notif_action(&k, i, "");
                            }
                        })));
                    }
                    c.push(bx(Rectangle::new().width(iw).height(32.0).align_child(Start, End).child(Row::new(row).gap(6.0))));
                }
                if replying {
                    let input = TextInput::new("phone-reply").width(iw - 20.0 - 80.0).size(t.fs - 1.0).color(t.p.fg).focused().on_change(|s| REPLY.lock().unwrap().2 = s).on_submit(|_| send_reply());
                    c.push(bx(Row::new(children![
                        Rectangle::new().width(iw - 80.0).height(32.0).radius(8.0).fill(t.p.surface_hi).border(1.0, t.p.line).padding(Padding { top: 0.0, right: 10.0, bottom: 0.0, left: 10.0 }).align_child(Start, Center).child(input),
                        ui::button::<POPUP>(t, "phone-send", &t.t("Send"), true, send_reply)
                    ])
                    .gap(6.0)
                    .align(Center)));
                }
                let cc = Column::new(c).gap(3.0);
                let (_, ch) = ui::size_of(&cc);
                cards.push(bx(ui::track::<POPUP>(Rectangle::new().width(w).height(ch + 20.0).radius(12.0).fill(if hov { t.p.surface_hi } else { t.p.surface }).padding(Padding { top: 10.0, right: 12.0, bottom: 10.0, left: 12.0 }).child(cc), hid)));
            }
            let list = Column::new(cards).gap(6.0);
            let (_, lh) = ui::size_of(&list);
            col.push(bx(ScrollArea::new("phone-notifs", list).width(w).height(lh.min(360.0))));
        }
    }
    let _ = (Json::Null, Weight::Bold);
    Column::new(col).gap(10.0)
}

#[cfg(test)]
mod tests {
    #[test]
    fn short_ago() {
        let now = 10_000_000_000.0;
        assert_eq!(super::ago(now - 1000.0, now), "now");
        assert_eq!(super::ago(now - 5.0 * 60_000.0, now), "5m");
        assert_eq!(super::ago(now - 3.0 * 3_600_000.0, now), "3h");
        assert_eq!(super::ago(now - 2.0 * 86_400_000.0, now), "2d");
    }
}
