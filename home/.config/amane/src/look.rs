// текущая тема: схема из настроек или цвета обоев (как Theme.qml + WallColors.qml)

use std::thread;
use std::time::Duration;

use amane::{Color, Service};

use crate::settings::{Config, Settings};
use crate::theme::{self, Palette};

pub struct Look {
    pub p: Palette,
    pub wallpaper: String,
}

// обои с основного монитора, иначе с первого: строки `awww query` вида «DP-1: … image: /путь»
pub fn wallpaper_from_query(text: &str, primary: &str) -> String {
    let lines: Vec<&str> = text.lines().collect();
    let line = lines.iter().find(|l| !primary.is_empty() && l.contains(primary)).or(lines.first());
    line.and_then(|l| l.split_once("image: ")).map(|(_, p)| p.trim().to_string()).unwrap_or_default()
}

fn wallpaper_palette(path: &str) -> Option<Palette> {
    let q = crate::niri::sh_quote(&format!("{path}[0]"));
    let hist = amane::output(&format!("magick {q} -resize 96x96 -colors 8 -format %c histogram:info:- </dev/null 2>/dev/null"));
    theme::histogram_main(&hist).map(Palette::from_wallpaper)
}

impl Service for Look {
    fn new() -> Self {
        Look { p: Palette::scheme(&Settings::read().c.scheme), wallpaper: String::new() }
    }

    fn listen() {
        let mut cached: Option<(String, Palette)> = None;
        loop {
            let (scheme, primary) = {
                let s = Settings::read();
                (s.c.scheme.clone(), s.c.primary_output.clone())
            };
            let wall = wallpaper_from_query(&amane::output("awww query 2>/dev/null"), &primary);
            let p = if scheme == "wallpaper" && !wall.is_empty() {
                match &cached {
                    Some((path, p)) if *path == wall => Some(*p),
                    _ => {
                        let p = wallpaper_palette(&wall);
                        if let Some(p) = p {
                            cached = Some((wall.clone(), p));
                        }
                        p
                    }
                }
            } else if scheme == "wallpaper" {
                None // обои ещё не известны — оставить прежние цвета
            } else {
                Some(Palette::scheme(&scheme))
            };
            {
                let cur = Look::read();
                let changed_p = p.is_some_and(|p| p != cur.p);
                let changed_w = cur.wallpaper != wall;
                drop(cur);
                if changed_p || changed_w {
                    let mut w = Look::write();
                    if let Some(p) = p {
                        w.p = p;
                    }
                    w.wallpaper = wall;
                }
            }
            thread::sleep(Duration::from_secs(2));
        }
    }
}

// всё, что нужно виду, одним значением: цвета и размеры под масштаб интерфейса
#[derive(Clone)]
pub struct Tk {
    pub p: Palette,
    pub c: Config,
    pub font: String,
    pub fs: f32,
    pub icon: f32,
    pub bar_h: f32,
    pub radius: f32,
    pub panel: Color,
}

pub const RADIUS: f32 = 10.0;
pub const PADDING: f32 = 12.0;

impl Tk {
    pub fn new(p: Palette, c: Config) -> Tk {
        let scale = c.ui_scale;
        let a = if c.transparency { c.opacity } else { 1.0 };
        Tk {
            p,
            font: c.font.clone(),
            fs: (13.0 * scale).round(),
            icon: (15.0 * scale).round(),
            bar_h: c.bar_height,
            radius: RADIUS,
            panel: theme::alpha(p.bg, a),
            c,
        }
    }

    pub fn tr<'a>(&self, en: &'a str, ru: &'a str) -> &'a str {
        self.c.tr(en, ru)
    }

    // по словарю (как I18n.tr в Quickshell)
    pub fn t(&self, en: &str) -> String {
        crate::i18n::tr(self.c.ru(), en)
    }
}

// читается в каждом виде: подписывает окно и на схему, и на настройки
pub fn tk() -> Tk {
    let p = Look::read().p;
    let c = Settings::read().c.clone();
    Tk::new(p, c)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wallpaper_query() {
        let q = "HDMI-A-2: 1440x900, scale: 1, currently displaying: image: /w/b.png\nDP-1: 1920x1080, scale: 1, currently displaying: image: /w/a b.jpg\n";
        assert_eq!(wallpaper_from_query(q, "DP-1"), "/w/a b.jpg");
        assert_eq!(wallpaper_from_query(q, ""), "/w/b.png");
        assert_eq!(wallpaper_from_query(q, "eDP-1"), "/w/b.png");
        assert_eq!(wallpaper_from_query("DP-1: color: 000000", "DP-1"), "");
        assert_eq!(wallpaper_from_query("", "DP-1"), "");
    }

    #[test]
    fn sizes_follow_scale_and_transparency() {
        let mut c = Config::default();
        c.ui_scale = 1.5;
        c.transparency = true;
        c.opacity = 0.5;
        let t = Tk::new(Palette::scheme("dark"), c);
        assert_eq!(t.fs, 20.0);
        assert_eq!(t.icon, 23.0);
        assert_eq!(t.panel.alpha(), 128);
        let t = Tk::new(Palette::scheme("dark"), Config::default());
        assert_eq!(t.panel.alpha(), 255);
    }
}

// анимация с длительностью; REXILONE_NO_ANIM=1 — без анимаций (проверка на скрытом вложенном niri, где кадры редки)
pub fn anim(from: f32, ms: u64) -> amane::Animation {
    let ms = if no_anim() { 0 } else { ms };
    amane::Animation::new(from).duration(std::time::Duration::from_millis(ms.max(1)))
}

pub fn no_anim() -> bool {
    std::env::var_os("REXILONE_NO_ANIM").is_some_and(|v| v == "1")
}

// к цели — плавно, а с REXILONE_NO_ANIM=1 сразу
pub fn go(a: &mut amane::Animation, target: f32) {
    if no_anim() {
        *a = amane::Animation::new(target).duration(std::time::Duration::from_millis(1));
    } else {
        a.to(target);
    }
}

// Только что показанное окно рисует первый кадр без движения, а анимация появления начинается после него:
// если первый кадр нового окна уже движется, niri не присылает следующий кадр и окно застывает прозрачным.
// Вызывается из вида; start срабатывает один раз на каждое открытие.
pub fn appear(key: &'static str, open: bool, start: fn()) {
    thread_local! {
        static STARTED: std::cell::RefCell<std::collections::HashSet<&'static str>> = Default::default();
    }
    if !open {
        STARTED.with_borrow_mut(|s| s.remove(key));
        return;
    }
    // до настройки окна (размер 0) кадра ещё нет
    if amane::window_size().0 <= 0.0 {
        return;
    }
    if STARTED.with_borrow_mut(|s| s.insert(key)) {
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(16));
            start();
        });
    }
}
