// уведомления: всплывающие справа вверху и «Не беспокоить» (Notifs.qml, NotificationPopups.qml)

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use amane::{
    Animation, Button, Center, Color, Column, Horizontal, Image, Layer, LayerWindow, Margin, Notification,
    Notifications, Padding, Parent, Rectangle, Row, Service, Start, Urgency, Vertical, Weight, Widget,
    children,
};

use crate::json::Json;
use crate::look::{self, Tk};
use crate::niri::Niri;
use crate::settings::Settings;
use crate::ui::{self, NOTIF, ic};

pub const WIDTH: f32 = 380.0;

#[derive(Debug, Clone, PartialEq)]
pub struct Popup {
    pub id: u32,
    pub received: SystemTime,
    pub shown: SystemTime,
}

pub struct NotifState {
    pub dnd: bool,
    pub popups: Vec<Popup>,
    // уже показанные (id + время прихода: замена уведомления показывается снова)
    seen: HashSet<(u32, SystemTime)>,
    pub hover: Option<u32>,
}

fn state_file() -> std::path::PathBuf {
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| crate::settings::home().join(".local/state"));
    base.join("rexilone/amane.json")
}

pub fn load_state() -> Json {
    std::fs::read_to_string(state_file()).ok().and_then(|t| Json::parse(&t)).unwrap_or(Json::Obj(Vec::new()))
}

pub fn save_state(key: &str, v: Json) {
    let mut j = load_state();
    j.set(key, v);
    let f = state_file();
    if let Some(d) = f.parent() {
        let _ = std::fs::create_dir_all(d);
    }
    let _ = std::fs::write(f, j.pretty());
}

// что показывать всплывающим сейчас: новые — добавить, старые — убрать по таймауту
pub fn step(
    popups: &[Popup],
    seen: &mut HashSet<(u32, SystemTime)>,
    list: &[(u32, SystemTime, bool)],
    now: SystemTime,
    timeout: Duration,
    dnd: bool,
    hover: Option<u32>,
) -> Vec<Popup> {
    let alive: HashSet<u32> = list.iter().map(|(id, _, _)| *id).collect();
    let critical: HashSet<u32> = list.iter().filter(|(_, _, c)| *c).map(|(id, _, _)| *id).collect();
    let mut out: Vec<Popup> = popups
        .iter()
        .filter(|p| alive.contains(&p.id))
        // замена с тем же id — показать заново
        .filter(|p| list.iter().any(|(id, r, _)| *id == p.id && *r == p.received))
        .filter(|p| {
            critical.contains(&p.id)
                || hover == Some(p.id)
                || now.duration_since(p.shown).unwrap_or_default() < timeout
        })
        .cloned()
        .collect();
    for (id, received, crit) in list {
        if seen.insert((*id, *received)) && (!dnd || *crit) {
            out.retain(|p| p.id != *id);
            out.push(Popup { id: *id, received: *received, shown: now });
        }
    }
    seen.retain(|(id, _)| alive.contains(id));
    out
}

impl Service for NotifState {
    fn new() -> Self {
        // уведомления, пришедшие до запуска шелла, всплывающими не показываем
        let seen = Notifications::read().list().iter().map(|n| (n.id(), n.received())).collect();
        NotifState { dnd: load_state().get("dnd").bool_or(false), popups: Vec::new(), seen, hover: None }
    }

    fn interval() -> Duration {
        Duration::from_millis(250)
    }

    fn update(&mut self) -> bool {
        let list: Vec<(u32, SystemTime, bool)> = Notifications::read()
            .list()
            .iter()
            .map(|n| (n.id(), n.received(), n.urgency() == Urgency::Critical))
            .collect();
        let timeout = Duration::from_secs(Settings::read().c.popup_timeout);
        let next = step(&self.popups, &mut self.seen, &list, SystemTime::now(), timeout, self.dnd, self.hover);
        let changed = next != self.popups;
        self.popups = next;
        changed
    }
}

pub fn toggle_dnd() {
    let mut s = NotifState::write();
    s.dnd = !s.dnd;
    if s.dnd {
        let crit: HashSet<u32> = Notifications::read()
            .list()
            .iter()
            .filter(|n| n.urgency() == Urgency::Critical)
            .map(|n| n.id())
            .collect();
        s.popups.retain(|p| crit.contains(&p.id));
    }
    save_state("dnd", Json::Bool(s.dnd));
}

pub fn hide_popup(id: u32) {
    NotifState::write().popups.retain(|p| p.id != id);
}

// «сейчас», «5 мин», «3 ч», «17 окт»
pub fn time_ago(t: &Tk, at: SystemTime, now: SystemTime) -> String {
    let min = now.duration_since(at).unwrap_or_default().as_secs() / 60;
    if min < 1 {
        return t.tr("now", "сейчас").into();
    }
    if min < 60 {
        return format!("{min}{}", t.tr("m", " мин"));
    }
    let h = min / 60;
    if h < 24 {
        return format!("{h}{}", t.tr("h", " ч"));
    }
    let unix = at.duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    let off = crate::clock::Clock::read().offset;
    crate::clock::format("d MMM", &crate::clock::civil(unix, off), t.c.ru())
}

// простая разметка тела (<b>, <a href>, &amp;) → текст
pub fn plain(body: &str) -> String {
    let mut out = String::new();
    let mut in_tag = false;
    for c in body.chars() {
        match c {
            '<' => in_tag = true,
            '>' if in_tag => in_tag = false,
            c if !in_tag => out.push(c),
            _ => {}
        }
    }
    out.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&#39;", "'").replace("&amp;", "&")
}

pub struct Card {
    pub widget: Rectangle,
    pub height: f32,
}

// карточка (NotificationCard.qml): значок, «приложение · время», заголовок, текст, кнопки
pub fn card<const W: u8>(t: &Tk, n: &Notification, width: f32, bordered: bool, on_close: fn(u32)) -> Card {
    let id = n.id();
    let hid = format!("n:{id}");
    let hov = ui::hovered::<W>(&hid);
    let icon_path = crate::icons::resolve(n.image()).or_else(|| crate::icons::resolve(n.icon()));
    let inner_w = width - 24.0 - if icon_path.is_some() { 48.0 } else { 0.0 };
    let now = SystemTime::now();

    let mut col: Vec<Box<dyn Widget>> = Vec::new();
    let header_txt = [n.app_name().to_string(), time_ago(t, n.received(), now)]
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" · ");
    let head_h = (t.fs * 1.4).ceil();
    let close_id = format!("nclose:{id}");
    let close = ui::track::<W>(
        Rectangle::new().width(head_h).height(head_h).align_child(Center, Center).child(ui::icon(
            t,
            ic::CLOSE,
            t.fs,
            if ui::hovered::<W>(&close_id) { t.p.fg } else { t.p.dim },
        )),
        close_id,
    )
    .cursor(amane::Pointer)
    .on_click(move |_| on_close(id));
    col.push(Box::new(
        Row::new(children![
            Rectangle::new().width(Parent).height(head_h).align_child(Start, Center).child(ui::text(t, header_txt, t.p.dim).size(t.fs - 2.0).elide()),
            close
        ])
        .width(inner_w)
        .height(head_h)
        .align(Center),
    ));
    let mut h = head_h;
    if !n.summary().is_empty() {
        let s = ui::text(t, n.summary(), t.p.fg).weight(Weight::Bold).wrap().max_lines(2).elide();
        let sh = s.height_in(inner_w);
        h += 3.0 + sh;
        col.push(Box::new(Rectangle::new().width(inner_w).height(sh).child(s)));
    }
    let body = plain(n.body());
    if !body.is_empty() {
        let b = ui::text(t, body, theme_alpha(t.p.fg, 0.8)).size(t.fs - 1.0).wrap().max_lines(5).elide();
        let bh = b.height_in(inner_w);
        h += 3.0 + bh;
        col.push(Box::new(Rectangle::new().width(inner_w).height(bh).child(b)));
    }
    if !n.actions().is_empty() {
        let mut buttons: Vec<Box<dyn Widget>> = Vec::new();
        for a in n.actions() {
            let key = a.key().to_string();
            let bid = format!("na:{id}:{key}");
            let label = ui::text(t, a.label(), t.p.fg).size(t.fs - 1.0);
            let w = crate::bar::width_of(&label) + 20.0;
            let b = ui::track::<W>(
                Rectangle::new()
                    .width(w)
                    .height(24.0)
                    .radius(6.0)
                    .fill(if ui::hovered::<W>(&bid) { t.p.faint } else { t.p.surface_hi })
                    .align_child(Center, Center)
                    .child(label),
                bid,
            )
            .cursor(amane::Pointer)
            .on_click(move |_| Notifications::invoke(id, &key));
            buttons.push(Box::new(b));
        }
        h += 4.0 + 3.0 + 24.0;
        col.push(Box::new(Rectangle::new().width(inner_w).height(28.0).padding(Padding { top: 4.0, right: 0.0, bottom: 0.0, left: 0.0 }).child(Row::new(buttons).gap(6.0))));
    }
    let content = Column::new(col).gap(3.0);
    let body_row: Rectangle = match icon_path {
        Some(p) => Rectangle::new().width(width - 24.0).height(h).child(
            Row::new(children![
                Rectangle::new().width(36.0).height(36.0).radius(8.0).fill(Image::contain(p)),
                Rectangle::new().width(12.0).height(1.0),
                content
            ]),
        ),
        None => Rectangle::new().width(width - 24.0).height(h).child(content),
    };
    let height = h + 24.0;
    let border = if n.urgency() == Urgency::Critical { t.p.urgent } else { t.p.faint };
    let has_default = n.has_default_action();
    let mut r = Rectangle::new()
        .width(width)
        .height(height)
        .radius(t.radius)
        .fill(if hov { t.p.surface_hi } else { t.panel })
        .padding(12.0)
        .child(body_row);
    if bordered {
        r = r.border(1.0, border);
    }
    let r = r
        .on_hover(move |inside| {
            if inside {
                ui::Hover::<W>::write().id = format!("n:{id}");
                if W == NOTIF {
                    NotifState::write().hover = Some(id);
                }
            } else {
                if ui::Hover::<W>::read().id.starts_with(&format!("n:{id}")) {
                    ui::Hover::<W>::write().id.clear();
                }
                if W == NOTIF && NotifState::read().hover == Some(id) {
                    NotifState::write().hover = None;
                }
            }
        })
        .on_click(move |b| {
            if b == Button::Left && has_default {
                Notifications::click(id);
            }
            on_close(id);
        });
    Card { widget: if has_default { r.cursor(amane::Pointer) } else { r }, height }
}

fn theme_alpha(c: Color, a: f32) -> Color {
    crate::theme::alpha(c, a)
}

thread_local! {
    // выезд справа у каждой карточки
    static SLIDE: RefCell<HashMap<u32, Animation>> = RefCell::new(HashMap::new());
    // было ли окно уведомлений показано прошлым кадром
    static SHOWN: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

fn close_popup(id: u32) {
    Notifications::dismiss(id);
    hide_popup(id);
}

// окно всплывающих уведомлений — на главном мониторе
pub fn view(m: &amane::Monitor) -> LayerWindow {
    let t = look::tk();
    let main = {
        let n = Niri::read();
        let c = Settings::read();
        c.c.bar_on(&n.s.outputs).first().cloned().unwrap_or_default()
    };
    let on_main = main.is_empty() || main == m.name;
    let center_open = crate::popups::Popups::read().open == "notifications";
    let ids: Vec<u32> = if on_main { NotifState::read().popups.iter().map(|p| p.id).collect() } else { Vec::new() };
    let shown = on_main && !ids.is_empty() && !center_open;
    let mut cards: Vec<Box<dyn Widget>> = Vec::new();
    let mut total = 0.0;
    if on_main {
        // окно только что показывается — карточки сразу на месте (первый кадр нового окна не должен двигаться)
        let was = SHOWN.get();
        SHOWN.set(shown);
        let notes = Notifications::read();
        SLIDE.with_borrow_mut(|m| m.retain(|id, _| ids.contains(id)));
        for id in &ids {
            let Some(n) = notes.list().iter().find(|n| n.id() == *id) else { continue };
            let c = card::<NOTIF>(&t, n, WIDTH, true, close_popup);
            let x = SLIDE.with_borrow_mut(|m| {
                let a = m.entry(*id).or_insert_with(|| {
                    let mut a = crate::look::anim(if was { WIDTH } else { 0.0 }, 280);
                    crate::look::go(&mut a, 0.0);
                    a
                });
                a.value()
            });
            if total > 0.0 {
                total += 8.0;
            }
            total += c.height;
            cards.push(Box::new(c.widget.translate(x, 0.0)));
        }
    }
    LayerWindow::new()
        .width(WIDTH)
        .height(total.max(1.0))
        .anchor_vertical(Vertical::Top)
        .anchor_horizontal(Horizontal::Right)
        .margin(Margin { top: 8, right: 8, bottom: 0, left: 0 })
        .layer(Layer::Overlay)
        .namespace("rexilone-notifications")
        .visible(shown)
        .child(Column::new(cards).gap(8.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(s: u64) -> SystemTime {
        UNIX_EPOCH + Duration::from_secs(1_000_000 + s)
    }

    #[test]
    fn new_notifications_pop_and_expire() {
        let mut seen = HashSet::new();
        let t5 = Duration::from_secs(5);
        let list = vec![(1, at(0), false)];
        let p = step(&[], &mut seen, &list, at(0), t5, false, None);
        assert_eq!(p.iter().map(|p| p.id).collect::<Vec<_>>(), vec![1]);
        // ещё раз — не дублируется
        let p = step(&p, &mut seen, &list, at(1), t5, false, None);
        assert_eq!(p.len(), 1);
        // под мышью не исчезает
        let p = step(&p, &mut seen, &list, at(9), t5, false, Some(1));
        assert_eq!(p.len(), 1);
        // время вышло
        let p = step(&p, &mut seen, &list, at(9), t5, false, None);
        assert!(p.is_empty());
        // закрыли — забываем
        let p = step(&p, &mut seen, &[], at(10), t5, false, None);
        assert!(p.is_empty() && seen.is_empty());
    }

    #[test]
    fn dnd_lets_only_critical_through() {
        let mut seen = HashSet::new();
        let list = vec![(1, at(0), false), (2, at(0), true)];
        let p = step(&[], &mut seen, &list, at(0), Duration::from_secs(5), true, None);
        assert_eq!(p.iter().map(|p| p.id).collect::<Vec<_>>(), vec![2]);
        // критичное не уходит по таймауту
        let p = step(&p, &mut seen, &list, at(100), Duration::from_secs(5), true, None);
        assert_eq!(p.len(), 1);
    }

    #[test]
    fn replaced_notification_pops_again() {
        let mut seen = HashSet::new();
        let t5 = Duration::from_secs(5);
        let p = step(&[], &mut seen, &[(7, at(0), false)], at(0), t5, false, None);
        let p = step(&p, &mut seen, &[(7, at(0), false)], at(6), t5, false, None);
        assert!(p.is_empty());
        let p = step(&p, &mut seen, &[(7, at(6), false)], at(6), t5, false, None);
        assert_eq!(p.len(), 1);
        assert_eq!(p[0].shown, at(6));
    }

    #[test]
    fn markup_to_text() {
        assert_eq!(plain("<b>Hi</b> &amp; <a href=\"x\">link</a> &lt;3"), "Hi & link <3");
        assert_eq!(plain("a < b"), "a ");
        assert_eq!(plain(""), "");
    }
}
