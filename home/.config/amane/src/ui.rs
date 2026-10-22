// общие куски интерфейса: наведение, текст, иконки, кнопки

use std::time::Duration;

use amane::{Button, Color, Column, Rectangle, Service, Text, Weight, Widget, children};

use crate::look::Tk;

// содержимое прокрутки, сдвинутое вверх на off. Не через translate: clip в amane режет зоны
// клика по месту до сдвига, и то, что прокручено в окно снизу, не нажималось
pub fn scrolled(child: impl Widget + 'static, off: f32) -> Column {
    Column::new(children![Column::new(Vec::new()).height(-off), child])
}

// что под мышью; у каждого окна свой номер W — наведение в одном окне не перерисовывает другие
pub struct Hover<const W: u8> {
    pub id: String,
}

impl<const W: u8> Service for Hover<W> {
    fn new() -> Self {
        Hover { id: String::new() }
    }

    fn interval() -> Duration {
        Duration::from_secs(3600)
    }
}

pub const BAR: u8 = 0;
pub const LAUNCHER: u8 = 1;
pub const CLIP: u8 = 3;
pub const WALL: u8 = 4;
pub const NOTIF: u8 = 5;
pub const POPUP: u8 = 6;
pub const PREFS: u8 = 7;

pub fn hovered<const W: u8>(id: &str) -> bool {
    Hover::<W>::read().id == id
}

pub fn track<const W: u8>(r: Rectangle, id: impl Into<String>) -> Rectangle {
    let id = id.into();
    r.on_hover(move |inside| {
        let cur = Hover::<W>::read().id == id;
        if inside && !cur {
            Hover::<W>::write().id = id.clone();
        } else if !inside && cur {
            Hover::<W>::write().id.clear();
        }
    })
}

pub fn clear_hover<const W: u8>() {
    if !Hover::<W>::read().id.is_empty() {
        Hover::<W>::write().id.clear();
    }
}

pub fn glyph(code: u32) -> String {
    char::from_u32(code).map(String::from).unwrap_or_default()
}

pub fn text(t: &Tk, s: impl Into<String>, color: Color) -> Text {
    Text::new(s).font(&t.font).size(t.fs).color(color)
}

pub fn bold(t: &Tk, s: impl Into<String>, color: Color) -> Text {
    text(t, s, color).weight(Weight::Bold)
}

// значок Nerd Font: по форме букв, чтобы стоял ровно по центру
pub fn icon(t: &Tk, code: u32, size: f32, color: Color) -> Text {
    Text::new(glyph(code)).font(&t.font).size(size).color(color).tight()
}

// ЛКМ — действие (правая и средняя кнопки — отдельно через on_click самого прямоугольника)
pub fn on_left(r: Rectangle, f: impl Fn() + 'static) -> Rectangle {
    r.cursor(amane::Pointer).on_click(move |b| {
        if b == Button::Left {
            f()
        }
    })
}

// glyphs Nerd Font (Material Design), как Icons.qml
pub mod ic {
    pub const ARCH: u32 = 0xF08C7;
    pub const VOL_HIGH: u32 = 0xF057E;
    pub const VOL_MID: u32 = 0xF0580;
    pub const VOL_LOW: u32 = 0xF057F;
    pub const VOL_MUTE: u32 = 0xF075F;
    pub const MIC: u32 = 0xF036C;
    pub const MIC_OFF: u32 = 0xF036D;
    pub const ETHERNET: u32 = 0xF0200;
    pub const WIFI: u32 = 0xF05A9;
    pub const OFFLINE: u32 = 0xF0318;
    pub const BELL: u32 = 0xF009A;
    pub const BELL_OFF: u32 = 0xF009B;
    pub const CLOSE: u32 = 0xF0156;
    pub const SEARCH: u32 = 0xF0349;
    pub const LOCK: u32 = 0xF033E;
    pub const CLIPBOARD: u32 = 0xF014D;
    pub const TRASH: u32 = 0xF0A7A;
    pub const TUNE: u32 = 0xF062E;
    pub const BRIGHTNESS: u32 = 0xF00E0;
    pub const LOGOUT: u32 = 0xF0343;
    pub const SUSPEND: u32 = 0xF0904;
    pub const REBOOT: u32 = 0xF0709;
    pub const POWEROFF: u32 = 0xF0425;
    pub const IMAGE: u32 = 0xF02E9;
    pub const SHUFFLE: u32 = 0xF049D;
}

pub fn volume_icon(input: bool, muted: bool, volume: u8) -> u32 {
    if input {
        return if muted { ic::MIC_OFF } else { ic::MIC };
    }
    if muted || volume == 0 {
        ic::VOL_MUTE
    } else if volume < 34 {
        ic::VOL_LOW
    } else if volume < 67 {
        ic::VOL_MID
    } else {
        ic::VOL_HIGH
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn volume_icons_like_quickshell() {
        assert_eq!(volume_icon(false, false, 0), ic::VOL_MUTE);
        assert_eq!(volume_icon(false, true, 80), ic::VOL_MUTE);
        assert_eq!(volume_icon(false, false, 20), ic::VOL_LOW);
        assert_eq!(volume_icon(false, false, 50), ic::VOL_MID);
        assert_eq!(volume_icon(false, false, 100), ic::VOL_HIGH);
        assert_eq!(volume_icon(true, false, 0), ic::MIC);
        assert_eq!(volume_icon(true, true, 50), ic::MIC_OFF);
    }

    #[test]
    fn glyphs() {
        assert_eq!(glyph(ic::ARCH).chars().count(), 1);
        assert_eq!(glyph(0xD800), "");
    }
}

// размер виджета, если он фиксированный (Row/Column из фиксированных детей измеряются сами)
pub fn size_of(w: &(impl amane::Widget + ?Sized)) -> (f32, f32) {
    let f = |s: amane::Size| match s {
        amane::Size::Fixed(v) => v,
        amane::Size::Parent => 0.0,
    };
    (f(w.width()), f(w.height()))
}

// прямоугольник ровно по размеру содержимого — чтобы повесить на него клик или фон
pub fn wrap(w: impl amane::Widget + 'static) -> Rectangle {
    let (x, y) = size_of(&w);
    Rectangle::new().width(x).height(y).child(w)
}

pub fn spacer(w: f32, h: f32) -> Rectangle {
    Rectangle::new().width(w).height(h)
}

// ползунок (Slider.qml): дорожка 4 px, заполнение акцентом, ручка; тянуть мышью и крутить колесом
pub fn slider<const W: u8>(
    t: &Tk,
    id: &str,
    width: f32,
    ratio: f32,
    muted: bool,
    over: bool,
    set: impl Fn(f32) + Clone + 'static,
) -> Rectangle {
    let ratio = ratio.clamp(0.0, 1.0);
    let hov = hovered::<W>(id);
    let knob = if hov { 12.0 } else { 10.0 };
    let fill = if muted { t.p.dim } else if over { t.p.warn } else { t.p.accent };
    let track = Rectangle::new()
        .width(width)
        .height(4.0)
        .radius(2.0)
        .fill(t.p.faint)
        .child(Rectangle::new().width((width * ratio).max(0.0)).height(4.0).radius(2.0).fill(fill));
    let knob = Rectangle::new()
        .width(knob)
        .height(knob)
        .radius(amane::Full)
        .fill(if muted { t.p.dim } else { t.p.fg })
        .translate(width * ratio - knob / 2.0, 0.0);
    let s1 = set.clone();
    let s2 = set.clone();
    let r = Rectangle::new()
        .width(width)
        .height(16.0)
        .align_child(amane::Start, amane::Center)
        .cursor(amane::Pointer)
        .on_drag(move |p| s1((p.x / width).clamp(0.0, 1.0)))
        .on_click(move |_| {})
        .on_scroll(move |s| {
            let d = if s.y < 0.0 { 0.034 } else { -0.034 };
            s2((ratio + d).clamp(0.0, 1.0))
        })
        .child(amane::Stack::new(amane::children![
            Rectangle::new().width(width).height(16.0).align_child(amane::Start, amane::Center).child(track),
            Rectangle::new().width(width).height(16.0).align_child(amane::Start, amane::Center).child(knob),
        ]));
    track_hover::<W>(r, id)
}

fn track_hover<const W: u8>(r: Rectangle, id: &str) -> Rectangle {
    track::<W>(r, id.to_string())
}

// круглая кнопка со значком (RoundBtn в ControlCenter.qml)
pub fn round_btn<const W: u8>(t: &Tk, id: &str, code: u32, f: impl Fn() + 'static) -> Rectangle {
    let hov = hovered::<W>(id);
    let r = Rectangle::new()
        .width(36.0)
        .height(36.0)
        .radius(11.0)
        .fill(if hov { t.p.surface_hi } else { t.p.surface })
        .align_child(amane::Center, amane::Center)
        .child(icon(t, code, t.icon, t.p.fg));
    on_left(track::<W>(r, id.to_string()), f)
}

// кнопка с подписью
pub fn button<const W: u8>(t: &Tk, id: &str, label: &str, accent: bool, f: impl Fn() + 'static) -> Rectangle {
    let hov = hovered::<W>(id);
    let txt = text(t, label, if accent { t.p.bg } else { t.p.fg }).size(t.fs - 1.0);
    let (w, _) = size_of(&txt);
    let fill = match (accent, hov) {
        (true, true) => crate::theme::lighter(t.p.accent, 1.1),
        (true, false) => t.p.accent,
        (false, true) => t.p.surface_hi2,
        (false, false) => t.p.surface_hi,
    };
    let r = Rectangle::new()
        .width(w + 24.0)
        .height(30.0)
        .radius(8.0)
        .fill(fill)
        .align_child(amane::Center, amane::Center)
        .child(txt);
    on_left(track::<W>(r, id.to_string()), f)
}

// переключатель (SSwitch.qml)
pub fn switch<const W: u8>(t: &Tk, id: &str, on: bool, f: impl Fn() + 'static) -> Rectangle {
    let knob = Rectangle::new().width(14.0).height(14.0).radius(amane::Full).fill(if on { t.p.bg } else { t.p.dim }).translate(if on { 19.0 } else { 3.0 }, 0.0);
    let r = Rectangle::new()
        .width(36.0)
        .height(20.0)
        .radius(amane::Full)
        .fill(if on { t.p.accent } else { t.p.surface_hi2 })
        .align_child(amane::Start, amane::Center)
        .child(knob);
    on_left(track::<W>(r, id.to_string()), f)
}

// заголовок меню бара (MenuHeader.qml): значок, название, подпись и шестерёнка в Настройки
pub fn menu_header<const W: u8>(t: &Tk, width: f32, code: u32, title: &str, subtitle: &str, settings_page: &str) -> amane::Row {
    let mut parts: Vec<Box<dyn amane::Widget>> = Vec::new();
    if code != 0 {
        parts.push(Box::new(
            Rectangle::new().width(36.0).height(36.0).radius(11.0).fill(t.p.surface_hi).align_child(amane::Center, amane::Center).child(icon(t, code, t.icon + 2.0, t.p.accent)),
        ));
    }
    let tw = width - if code != 0 { 48.0 } else { 0.0 } - if settings_page.is_empty() { 0.0 } else { 44.0 };
    let mut col: Vec<Box<dyn amane::Widget>> = vec![Box::new(
        Rectangle::new().width(tw).height(t.fs + 5.0).clip().child(bold(t, t.t(title), t.p.fg).size(t.fs + 1.0).elide()),
    )];
    if !subtitle.is_empty() {
        col.push(Box::new(Rectangle::new().width(tw).height(t.fs + 1.0).clip().child(text(t, t.t(subtitle), t.p.dim).size(t.fs - 2.0).elide())));
    }
    parts.push(Box::new(amane::Column::new(col).gap(1.0)));
    if !settings_page.is_empty() {
        let id = format!("gear:{settings_page}");
        let hv = hovered::<W>(&id);
        let page = settings_page.to_string();
        let gear = Rectangle::new()
            .width(32.0)
            .height(32.0)
            .radius(10.0)
            .fill(if hv { t.p.surface_hi2 } else { t.p.surface_hi })
            .align_child(amane::Center, amane::Center)
            .child(icon(t, 0xF0493, t.icon, if hv { t.p.fg } else { t.p.dim }));
        parts.push(Box::new(on_left(track::<W>(gear, id), move || {
            crate::popups::close();
            crate::prefs::ipc(&["page".to_string(), page.clone()]);
        })));
    }
    amane::Row::new(parts).gap(12.0).align(amane::Center)
}
