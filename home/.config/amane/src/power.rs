// меню питания (Super+Shift+E) — как PowerMenu.qml: ←/→ — выбор, Enter — действие, буквы — быстрый выбор;
// выход, перезагрузка и выключение — по второму нажатию

use std::time::Duration;

use amane::{
    Animation, Center, Color, Column, End, Full, Key, Keyboard, Layer, LayerWindow, Parent, Rectangle, Row, Service, Widget,
    Zone, children,
};

use crate::look;
use crate::ui::{self, ic};

pub struct Act {
    pub name: &'static str,
    pub name_ru: &'static str,
    pub key: char,
    pub key_ru: char,
    pub icon: u32,
    pub confirm: bool,
    pub cmd: &'static str,
}

pub const ACTIONS: [Act; 5] = [
    Act { name: "Lock", name_ru: "Блокировка", key: 'l', key_ru: 'д', icon: ic::LOCK, confirm: false, cmd: "swaylock" },
    Act { name: "Suspend", name_ru: "Сон", key: 's', key_ru: 'ы', icon: ic::SUSPEND, confirm: false, cmd: "swaylock -f && systemctl suspend" },
    Act { name: "Logout", name_ru: "Выход", key: 'e', key_ru: 'у', icon: ic::LOGOUT, confirm: true, cmd: "niri msg action quit --skip-confirmation" },
    Act { name: "Reboot", name_ru: "Перезагрузка", key: 'r', key_ru: 'к', icon: ic::REBOOT, confirm: true, cmd: "systemctl reboot" },
    Act { name: "Shutdown", name_ru: "Выключение", key: 'p', key_ru: 'з', icon: ic::POWEROFF, confirm: true, cmd: "systemctl poweroff" },
];

pub struct Power {
    pub open: bool,
    pub output: String,
    pub current: usize,
    pub armed: Option<usize>,
    pub uptime: f64,
    pub anim: Animation,
}

impl Service for Power {
    fn new() -> Self {
        Power { open: false, output: String::new(), current: 0, armed: None, uptime: 0.0, anim: crate::look::anim(0.0, 220) }
    }

    fn interval() -> Duration {
        Duration::from_secs(30)
    }

    fn update(&mut self) -> bool {
        if !self.open {
            return false;
        }
        self.uptime = read_uptime();
        true
    }
}

fn read_uptime() -> f64 {
    std::fs::read_to_string("/proc/uptime").ok().and_then(|s| s.split_whitespace().next()?.parse().ok()).unwrap_or(0.0)
}

pub fn format_uptime(sec: f64, ru: bool) -> String {
    let s = sec as u64;
    let (d, h, m) = (s / 86400, s % 86400 / 3600, s % 3600 / 60);
    let u = if ru { ["д", "ч", "м"] } else { ["d", "h", "m"] };
    let mut parts = Vec::new();
    if d > 0 {
        parts.push(format!("{d}{}", u[0]));
    }
    if d > 0 || h > 0 {
        parts.push(format!("{h}{}", u[1]));
    }
    parts.push(format!("{m}{}", u[2]));
    parts.join(" ")
}

// что делать по нажатию: Some(команда) — выполнить, None — только «взвести» подтверждение
pub fn press(i: usize, armed: &mut Option<usize>) -> Option<&'static str> {
    let a = &ACTIONS[i];
    if a.confirm && *armed != Some(i) {
        *armed = Some(i);
        return None;
    }
    *armed = None;
    Some(a.cmd)
}

pub fn by_key(c: char) -> Option<usize> {
    let c = c.to_lowercase().next()?;
    ACTIONS.iter().position(|a| a.key == c || a.key_ru == c)
}

pub fn toggle(_: &[String]) -> String {
    let open = !Power::read().open;
    set_open(open);
    String::from(if open { "opened" } else { "closed" })
}

pub fn ipc(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("open") => set_open(true),
        Some("hide") | Some("close") => set_open(false),
        _ => return toggle(args),
    }
    String::from("ok")
}

pub fn set_open(open: bool) {
    let mut p = Power::write();
    if p.open == open {
        return;
    }
    p.open = open;
    if open {
        p.output = crate::focus_output();
        p.current = 0;
        p.armed = None;
        p.uptime = read_uptime();
        p.anim = crate::look::anim(0.0, 220);
        // появление — после первого кадра (look::appear)
    } else {
        crate::look::go(&mut p.anim, 0.0);
    }
}

fn activate(i: usize) {
    let mut p = Power::write();
    p.current = i;
    let cmd = press(i, &mut p.armed);
    drop(p);
    if let Some(cmd) = cmd {
        set_open(false);
        amane::spawn(&format!("sleep 0.2; {cmd}"));
    }
}

fn select(i: usize) {
    let mut p = Power::write();
    if p.current != i {
        p.current = i;
        if p.armed != Some(i) {
            p.armed = None;
        }
    }
}

fn on_key(k: Key) {
    let n = ACTIONS.len();
    let cur = Power::read().current;
    match k {
        Key::Escape => set_open(false),
        Key::Right | Key::Tab | Key::Down => select((cur + 1) % n),
        Key::Left | Key::Up => select((cur + n - 1) % n),
        Key::Enter | Key::Space => activate(cur),
        Key::Character(c) => {
            if let Some(i) = by_key(c) {
                activate(i)
            }
        }
        _ => {}
    }
}

pub fn view(m: &amane::Monitor) -> LayerWindow {
    let t = look::tk();
    let p = Power::read();
    let here = p.output == m.name;
    let k = if here { p.anim.value() } else { 0.0 };
    let (open, cur, armed, up) = (p.open && here, p.current, p.armed, p.uptime);
    look::appear("power", open, || {
        let mut x = Power::write();
        if x.open {
            look::go(&mut x.anim, 1.0);
        }
    });
    drop(p);

    let mut buttons: Vec<Box<dyn Widget>> = Vec::new();
    for (i, a) in ACTIONS.iter().enumerate() {
        let selected = cur == i;
        let is_armed = armed == Some(i);
        let color = if is_armed { t.p.urgent } else if selected { t.p.fg } else { t.p.dim };
        let label = if is_armed { t.tr("Confirm?", "Точно?") } else { t.tr(a.name, a.name_ru) };
        let mut b = Rectangle::new()
            .width(104.0)
            .height(112.0)
            .radius(t.radius)
            .fill(if is_armed { crate::theme::alpha(t.p.urgent, 0.18) } else if selected { t.p.surface_hi2 } else { Color::TRANSPARENT })
            .align_child(Center, Center)
            .cursor(amane::Pointer)
            .on_hover(move |inside| {
                if inside {
                    select(i)
                }
            })
            .on_click(move |_| activate(i))
            .child(
                Column::new(children![
                    Rectangle::new().width(104.0).height(34.0).align_child(Center, Center).child(ui::icon(&t, a.icon, 30.0, color).tight()),
                    Rectangle::new().width(104.0).height(t.fs + 4.0).align_child(Center, Center).child(ui::text(&t, label, color)),
                    Rectangle::new().width(104.0).height(t.fs).align_child(Center, Center).child(ui::text(&t, a.key.to_uppercase().to_string(), t.p.faint).size(t.fs - 2.0))
                ])
                .gap(10.0)
                .align(Center),
            );
        if is_armed {
            b = b.border(1.0, t.p.urgent);
        }
        buttons.push(Box::new(b));
    }
    let row = Row::new(buttons).gap(10.0);
    let (rw, _) = ui::size_of(&row);
    let head = Rectangle::new().width(rw).height(crate::prefs::w::line_h(t.fs) + 4.0).align_child(Center, End).child(ui::text(
        &t,
        format!("{}  {} {}", ui::glyph(0xF0954), t.tr("up", "работает"), format_uptime(up, t.c.ru())),
        t.p.dim,
    ));
    let content = Column::new(children![head, row]).gap(12.0);
    let (cw, ch) = ui::size_of(&content);
    let card = Rectangle::new()
        .width(cw + 32.0)
        .height(ch + 32.0)
        .radius(t.radius + 4.0)
        .fill(t.panel)
        .border(1.0, t.p.faint)
        .opacity(k)
        .scale(0.94 + 0.06 * k)
        .align_child(Center, Center)
        .on_click(|_| {})
        .child(content);

    LayerWindow::new()
        .width(Full)
        .height(Full)
        .layer(Layer::Overlay)
        .space(Zone::Ignore)
        .namespace("rexilone-power")
        .keyboard(if open { Keyboard::Exclusive } else { Keyboard::None })
        .on_key(on_key)
        .visible(open || k > 0.01)
        .child(
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .fill(Color::rgba(0, 0, 0, (0.5 * k * 255.0) as u8))
                .align_child(Center, Center)
                .on_click(|_| set_open(false))
                .child(card),
        )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uptime_text() {
        assert_eq!(format_uptime(59.0, false), "0m");
        assert_eq!(format_uptime(3.0 * 3600.0 + 120.0, false), "3h 2m");
        assert_eq!(format_uptime(2.0 * 86400.0 + 300.0, true), "2д 0ч 5м");
    }

    #[test]
    fn dangerous_actions_need_second_press() {
        let mut armed = None;
        assert_eq!(press(0, &mut armed), Some("swaylock"));
        assert_eq!(press(4, &mut armed), None);
        assert_eq!(armed, Some(4));
        assert_eq!(press(4, &mut armed), Some("systemctl poweroff"));
        assert_eq!(armed, None);
        // взвели одно — нажали другое: снова подтверждение
        assert_eq!(press(3, &mut armed), None);
        assert_eq!(press(4, &mut armed), None);
        assert_eq!(armed, Some(4));
    }

    #[test]
    fn letters_in_both_layouts() {
        assert_eq!(by_key('r'), Some(3));
        assert_eq!(by_key('R'), Some(3));
        assert_eq!(by_key('к'), Some(3));
        assert_eq!(by_key('з'), Some(4));
        assert_eq!(by_key('x'), None);
    }
}
