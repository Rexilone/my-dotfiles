// страницы Настроек: номер → содержимое (заголовок + карточки)

mod about;
mod autostart;
pub mod binds;
mod bluetooth;
mod boot;
mod display;
mod network;
mod notifications;
mod peripherals;
mod personalization;
pub mod phone;
mod plugins;
mod powerpage;
mod sound;
mod time;
mod updates;
mod system;

use super::w::{self, W, bx};
use super::{PAGES, Prefs, header};
use crate::look::Tk;

// что отдаёт страница: подстраница (вкладка) для «Раздел › Подстраница», подзаголовок, карточки
pub struct Out {
    pub crumb: String,
    pub subtitle: String,
    pub items: Vec<W>,
}

impl Out {
    pub fn new(items: Vec<W>) -> Out {
        Out { crumb: String::new(), subtitle: String::new(), items }
    }
}

// вкладка страницы (пусто — главная)
pub fn tab(page: usize) -> String {
    Prefs::get(&format!("tab:{page}"))
}

pub fn set_tab(page: usize, tab: &str) {
    Prefs::set(&format!("tab:{page}"), tab);
}

// высота области страницы: переписка и экран устройства — во всю высоту окна
static PANEL_H: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);

pub fn set_panel_h(h: f32) {
    PANEL_H.store(h.to_bits(), std::sync::atomic::Ordering::Relaxed);
}

fn fill_h() -> f32 {
    (f32::from_bits(PANEL_H.load(std::sync::atomic::Ordering::Relaxed)) - 140.0).max(420.0)
}

pub fn build(page: usize, t: &Tk, width: f32) -> Vec<W> {
    let p = &PAGES[page];
    if page != 5 {
        phone::leave();
    }
    let out = match page {
        0 => system::page(t, width),
        1 => display::page(t, width),
        2 => sound::page(t, width),
        3 => network::page(t, width),
        4 => bluetooth::page(t, width),
        5 => phone::page(t, width, fill_h()),
        7 => personalization::page(t, width),
        10 => peripherals::page(t, width),
        11 => binds::page(t, width),
        12 => autostart::page(t, width),
        13 => time::page(t, width),
        14 => powerpage::page(t, width),
        15 => notifications::page(t, width),
        16 => about::page(t, width),
        17 => plugins::page(t, width),
        18 => updates::page(t, width),
        19 => boot::page(t, width),
        _ => Out::new(vec![bx(w::Card::new(0xF0026, "Coming soon", "This page is being moved to amane").build(t, width))]),
    };
    let mut v: Vec<W> = vec![header(t, p.name, &out.crumb, &out.subtitle, width, move || set_tab(page, ""))];
    v.extend(out.items);
    v
}
