// цвета и размеры — те же, что в Quickshell (services/Theme.qml, WallColors.qml)

use amane::Color;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Palette {
    pub name: &'static str,
    pub bg: Color,
    pub surface: Color,
    pub surface_hi: Color,
    pub surface_hi2: Color,
    pub line: Color,
    pub fg: Color,
    pub fg_hover: Color,
    pub fg_pressed: Color,
    pub muted: Color,
    pub dim: Color,
    pub faint: Color,
    pub urgent: Color,
    pub warn: Color,
    pub accent: Color,
    pub rec: Color,
}

fn hexes(name: &'static str, h: [&str; 15]) -> Palette {
    let c = |i: usize| parse_hex(h[i]).unwrap_or(Color::rgb(255, 0, 255));
    Palette {
        name,
        bg: c(0),
        surface: c(1),
        surface_hi: c(2),
        surface_hi2: c(3),
        line: c(4),
        fg: c(5),
        fg_hover: c(6),
        fg_pressed: c(7),
        muted: c(8),
        dim: c(9),
        faint: c(10),
        urgent: c(11),
        warn: c(12),
        accent: c(13),
        rec: c(14),
    }
}

impl Palette {
    // неизвестная схема — тёмная, как в Quickshell
    pub fn scheme(name: &str) -> Palette {
        match name {
            "light" => hexes("Light", [
                "#f3f3f3", "#e8e8e8", "#dfdfdf", "#d4d4d4", "#c2c2c2", "#1f1f1f", "#3a3a3a", "#555555", "#474747",
                "#858585", "#c6c6c6", "#c0463f", "#b7791f", "#1f1f1f", "#d64545",
            ]),
            "nord" => hexes("Nord", [
                "#1e222a", "#252a33", "#2e3440", "#3b4252", "#4c566a", "#d8dee9", "#e5e9f0", "#b8c0cc", "#a3adbd",
                "#6c7689", "#3b4252", "#bf616a", "#ebcb8b", "#88c0d0", "#bf616a",
            ]),
            "gruvbox" => hexes("Gruvbox", [
                "#1d2021", "#242627", "#2c2e2f", "#353230", "#504945", "#ebdbb2", "#fbf1c7", "#d5c4a1", "#bdae93",
                "#7c6f64", "#3c3836", "#fb4934", "#fabd2f", "#fe8019", "#fb4934",
            ]),
            "rose" => hexes("Rosé", [
                "#191724", "#1f1d2e", "#26233a", "#2d2a44", "#403d52", "#e0def4", "#eeecfb", "#c4c1da", "#908caa",
                "#6e6a86", "#312e47", "#eb6f92", "#f6c177", "#c4a7e7", "#eb6f92",
            ]),
            _ => hexes("Dark", [
                "#151515", "#1b1b1b", "#222222", "#2a2a2a", "#3a3a3a", "#d4d4d4", "#e6e6e6", "#bdbdbd", "#a0a0a0",
                "#6b6b6b", "#333333", "#c96a6a", "#d7a65f", "#d4d4d4", "#e05d5d",
            ]),
        }
    }

    // схема «под обои»: из оттенка главного цвета обоев (WallColors.build)
    pub fn from_wallpaper(main: Color) -> Palette {
        let (h, s, _) = to_hsl(main);
        let s = s.clamp(0.35, 0.75);
        let c = |s, l| hsl(h, s, l);
        Palette {
            name: "Wallpaper",
            bg: c(0.16, 0.075),
            surface: c(0.15, 0.105),
            surface_hi: c(0.14, 0.135),
            surface_hi2: c(0.13, 0.17),
            line: c(0.12, 0.25),
            fg: c(0.18, 0.87),
            fg_hover: c(0.2, 0.93),
            fg_pressed: c(0.15, 0.76),
            muted: c(0.1, 0.66),
            dim: c(0.08, 0.46),
            faint: c(0.1, 0.22),
            urgent: Color::rgb(0xd9, 0x70, 0x6f),
            warn: Color::rgb(0xe0, 0xb0, 0x60),
            accent: c(s, 0.68),
            rec: Color::rgb(0xe0, 0x5d, 0x5d),
        }
    }

    pub fn is_light(&self) -> bool {
        to_hsl(self.bg).2 > 0.5
    }
}

// «#rgb», «#rrggbb», «#rrggbbaa»
pub fn parse_hex(s: &str) -> Option<Color> {
    let h = s.strip_prefix('#')?;
    let n = |i: usize, len: usize| u8::from_str_radix(h.get(i..i + len)?, 16).ok();
    match h.len() {
        3 => Some(Color::rgb(n(0, 1)? * 17, n(1, 1)? * 17, n(2, 1)? * 17)),
        6 => Some(Color::rgb(n(0, 2)?, n(2, 2)?, n(4, 2)?)),
        8 => Some(Color::rgba(n(0, 2)?, n(2, 2)?, n(4, 2)?, n(6, 2)?)),
        _ => None,
    }
}

pub fn alpha(c: Color, a: f32) -> Color {
    Color::rgba(c.red(), c.green(), c.blue(), (a.clamp(0.0, 1.0) * 255.0).round() as u8)
}

// t = 0 — a, t = 1 — b
pub fn mix(a: Color, b: Color, t: f32) -> Color {
    let l = |x: u8, y: u8| (x as f32 + (y as f32 - x as f32) * t).round().clamp(0.0, 255.0) as u8;
    Color::rgba(l(a.red(), b.red()), l(a.green(), b.green()), l(a.blue(), b.blue()), l(a.alpha(), b.alpha()))
}

// как Qt.lighter: светлота в HSV × k
pub fn lighter(c: Color, k: f32) -> Color {
    let f = |x: u8| ((x as f32) * k).round().clamp(0.0, 255.0) as u8;
    Color::rgba(f(c.red()), f(c.green()), f(c.blue()), c.alpha())
}

// HSL ровно как в Qt (QColor хранит его в 16-битных целых: оттенок в сотых градуса),
// чтобы цвета «под обои» совпадали с Quickshell до единицы
const USHRT: f32 = 65535.0;

fn q_round(x: f32) -> i32 {
    if x >= 0.0 { (x + 0.5) as i32 } else { (x - 0.5) as i32 }
}

fn qt_div_257(x: i32) -> u8 {
    ((x - (x >> 8) + 0x80) >> 8).clamp(0, 255) as u8
}

// оттенок 0..1, насыщенность и светлота 0..1 (как Qt.hsla)
pub fn hsl(h: f32, s: f32, l: f32) -> Color {
    let hue = q_round(h * 36000.0);
    let sat = q_round(s * USHRT);
    let light = q_round(l * USHRT);
    if sat == 0 {
        let v = qt_div_257(light);
        return Color::rgb(v, v, v);
    }
    let h = if hue == 36000 { 0.0 } else { hue as f32 / 36000.0 };
    let s = sat as f32 / USHRT;
    let l = light as f32 / USHRT;
    let temp2 = if l < 0.5 { l * (1.0 + s) } else { l + s - (l * s) };
    let temp1 = (2.0 * l) - temp2;
    let mut out = [0u8; 3];
    for (i, t) in [h + (1.0 / 3.0), h, h - (1.0 / 3.0)].into_iter().enumerate() {
        let t = if t < 0.0 { t + 1.0 } else if t > 1.0 { t - 1.0 } else { t };
        let six = t * 6.0;
        let v = if six < 1.0 {
            temp1 + (temp2 - temp1) * six
        } else if t * 2.0 < 1.0 {
            temp2
        } else if t * 3.0 < 2.0 {
            temp1 + (temp2 - temp1) * (2.0 / 3.0 - t) * 6.0
        } else {
            temp1
        };
        out[i] = qt_div_257(q_round(v * USHRT));
    }
    Color::rgb(out[0], out[1], out[2])
}

// (оттенок 0..1, насыщенность, светлота) как hslHueF/hslSaturationF/lightnessF в Qt
pub fn to_hsl(c: Color) -> (f32, f32, f32) {
    let ch = |v: u8| (v as i32 * 0x101) as f32 / USHRT;
    let (r, g, b) = (ch(c.red()), ch(c.green()), ch(c.blue()));
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;
    let delta2 = max + min;
    let lightness = q_round(0.5 * delta2 * USHRT) as f32 / USHRT;
    if delta.abs() <= 0.000000000001 {
        return (0.0, 0.0, lightness);
    }
    let sat = if 0.5 * delta2 < 0.5 { q_round((delta / delta2) * USHRT) } else { q_round((delta / (2.0 - delta2)) * USHRT) };
    let mut hue = if r == max {
        (g - b) / delta
    } else if g == max {
        2.0 + (b - r) / delta
    } else {
        4.0 + (r - g) / delta
    };
    hue *= 60.0;
    if hue < 0.0 {
        hue += 360.0;
    }
    let hue = q_round(hue * 100.0);
    (hue as f32 / 36000.0, sat as f32 / USHRT, lightness)
}

// самый заметный насыщенный цвет из гистограммы ImageMagick (`-colors 8 -format %c histogram:info:-`)
pub fn histogram_main(text: &str) -> Option<Color> {
    let mut best = None;
    let mut best_score = -1.0f32;
    for line in text.lines() {
        let Some((count, rest)) = line.trim_start().split_once(':') else { continue };
        let Ok(count) = count.trim().parse::<f32>() else { continue };
        let Some(pos) = rest.find('#') else { continue };
        let Some(c) = rest.get(pos..pos + 7).and_then(parse_hex) else { continue };
        let (_, s, l) = to_hsl(c);
        let score = count * (0.15 + s) * if l > 0.12 && l < 0.9 { 1.0 } else { 0.2 };
        if score > best_score {
            best_score = score;
            best = Some(c);
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex_forms() {
        assert_eq!(parse_hex("#151515"), Some(Color::rgb(0x15, 0x15, 0x15)));
        assert_eq!(parse_hex("#fff"), Some(Color::rgb(255, 255, 255)));
        assert_eq!(parse_hex("#00000080"), Some(Color::rgba(0, 0, 0, 0x80)));
        assert_eq!(parse_hex("151515"), None);
        assert_eq!(parse_hex("#12345"), None);
        assert_eq!(parse_hex("#zzzzzz"), None);
    }

    #[test]
    fn hsl_round_trip() {
        for hex in ["#d4d4d4", "#88c0d0", "#fe8019", "#c4a7e7", "#151515", "#ff0000"] {
            let c = parse_hex(hex).unwrap();
            let (h, s, l) = to_hsl(c);
            let back = hsl(h, s, l);
            for (a, b) in [(c.red(), back.red()), (c.green(), back.green()), (c.blue(), back.blue())] {
                assert!((a as i32 - b as i32).abs() <= 1, "{hex}");
            }
        }
    }

    #[test]
    fn schemes_match_quickshell() {
        let d = Palette::scheme("dark");
        assert_eq!(d.bg, Color::rgb(0x15, 0x15, 0x15));
        assert_eq!(d.accent, Color::rgb(0xd4, 0xd4, 0xd4));
        assert_eq!(Palette::scheme("nord").accent, Color::rgb(0x88, 0xc0, 0xd0));
        assert_eq!(Palette::scheme("что-то"), d);
        assert!(Palette::scheme("light").is_light());
        assert!(!d.is_light());
    }

    #[test]
    fn wallpaper_palette_is_dark_with_hue() {
        let p = Palette::from_wallpaper(Color::rgb(0x30, 0x60, 0xc0));
        let (h_bg, _, l_bg) = to_hsl(p.bg);
        let (h_acc, s_acc, l_acc) = to_hsl(p.accent);
        assert!(l_bg < 0.1);
        assert!((l_acc - 0.68).abs() < 0.02);
        assert!(s_acc >= 0.34);
        assert!((h_bg - h_acc).abs() < 0.03);
        assert!((h_acc - to_hsl(Color::rgb(0x30, 0x60, 0xc0)).0).abs() < 0.02);
    }

    #[test]
    fn histogram_picks_saturated_over_grey() {
        let text = "     9000: (20,20,20) #141414 srgb(20,20,20)\n      2500: (40,90,200) #285AC8 srgb(40,90,200)\n       100: (250,250,250) #FAFAFA srgb(250,250,250)\nмусор\n";
        assert_eq!(histogram_main(text), Some(Color::rgb(0x28, 0x5a, 0xc8)));
        assert_eq!(histogram_main(""), None);
    }

    #[test]
    fn mix_and_alpha() {
        let a = Color::rgb(0, 0, 0);
        let b = Color::rgb(200, 100, 50);
        assert_eq!(mix(a, b, 0.5), Color::rgb(100, 50, 25));
        assert_eq!(alpha(b, 0.5).alpha(), 128);
        assert_eq!(lighter(Color::rgb(100, 100, 100), 1.1), Color::rgb(110, 110, 110));
    }
}
