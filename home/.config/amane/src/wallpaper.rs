// обои (Super+W) — как WallpaperSwitcher.qml: карусель из ~/Pictures/Wallpapers, выбранная по центру;
// ←/→ — выбор, Enter — поставить (awww), Esc — закрыть

use std::time::Duration;

use amane::{
    Animation, Center, Color, Column, End, Full, Gradient, Image, Key, Keyboard, Layer, LayerWindow, Margin, Padding,
    Parent, Rectangle, Row, Service, SpaceBetween, Stack, Start, TextInput, Vertical, Widget, Zone, children,
};

use crate::look::{self, Look};
use crate::niri::sh_quote;
use crate::ui::{self, WALL, ic};

const CARD_W: f32 = 336.0;
const CARD_H: f32 = 189.0;
const GAP: f32 = 16.0;

#[derive(Debug, Clone, PartialEq)]
pub struct Wall {
    pub path: String,
    pub thumb: String,
    pub size: String,
    pub name: String,
}

pub struct Walls {
    pub open: bool,
    pub output: String,
    pub items: Vec<Wall>,
    pub loading: bool,
    pub query: String,
    pub sel: usize,
    pub want_scan: bool,
    pub anim: Animation,
    pub slide: Animation,
}

pub fn dir() -> String {
    crate::settings::home().join("Pictures/Wallpapers").to_string_lossy().to_string()
}

pub fn cache() -> String {
    let base = std::env::var_os("XDG_CACHE_HOME").map(std::path::PathBuf::from).unwrap_or_else(|| crate::settings::home().join(".cache"));
    base.join("rexilone/wallthumbs").to_string_lossy().to_string()
}

// список + миниатюры (делаются один раз) + размеры — тот же скрипт, что в Wallpapers.qml
pub const SCAN: &str = r#"
dir="$1"; cache="$2"; mkdir -p "$cache"
find -L "$dir" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
    -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) | sort -f | while IFS= read -r f; do
    h=$(printf '%s' "$f" | md5sum | cut -c1-16)
    t="$cache/$h.jpg"; d="$cache/$h.txt"
    if [ ! -s "$t" ] || [ "$f" -nt "$t" ]; then
        magick "$f[0]" -thumbnail 640x360^ -gravity center -extent 640x360 -quality 88 "$t" < /dev/null 2>/dev/null
        magick identify -format '%wx%h' "$f[0]" < /dev/null > "$d" 2>/dev/null
    fi
    printf '%s\t%s\t%s\n' "$f" "$t" "$(cat "$d" 2>/dev/null)"
done"#;

pub fn parse(text: &str) -> Vec<Wall> {
    text.lines()
        .filter_map(|l| {
            let mut it = l.split('\t');
            let path = it.next()?.to_string();
            let thumb = it.next()?.to_string();
            let size = it.next().unwrap_or("").to_string();
            let file = path.rsplit('/').next().unwrap_or(&path);
            let name = file.rsplit_once('.').map(|(n, _)| n).unwrap_or(file).to_string();
            (!path.is_empty()).then_some(Wall { path, thumb, size, name })
        })
        .collect()
}

pub fn filter<'a>(items: &'a [Wall], q: &str) -> Vec<&'a Wall> {
    let q = q.trim().to_lowercase();
    items.iter().filter(|w| q.is_empty() || w.name.to_lowercase().contains(&q)).collect()
}

// команда сканирования целиком (для cmd::get)
pub fn scan_cmd() -> String {
    let q = sh_quote;
    format!("sh -c {} sh {} {}", q(SCAN), q(&dir()), q(&cache()))
}

pub fn apply(path: &str) {
    amane::spawn(&format!(
        "awww img {} --transition-type grow --transition-pos top --transition-duration 1.2 --transition-fps 180",
        sh_quote(path)
    ));
}

impl Service for Walls {
    fn new() -> Self {
        Walls {
            open: false,
            output: String::new(),
            items: Vec::new(),
            loading: false,
            query: String::new(),
            sel: 0,
            want_scan: false,
            anim: crate::look::anim(0.0, 280),
            slide: crate::look::anim(0.0, 280),
        }
    }

    // миниатюры делаются без блокировки: вид в это время рисуется дальше
    fn listen() {
        loop {
            std::thread::sleep(Duration::from_millis(100));
            if !Walls::read().want_scan {
                continue;
            }
            Walls::write().want_scan = false;
            let out = std::process::Command::new("sh").arg("-c").arg(SCAN).arg("sh").arg(dir()).arg(cache()).output();
            let items = out.map(|o| parse(&String::from_utf8_lossy(&o.stdout))).unwrap_or_default();
            // выбор — на текущих обоях
            let cur = Look::read().wallpaper.clone();
            let mut w = Walls::write();
            w.sel = items.iter().position(|i| i.path == cur).unwrap_or(0);
            w.slide = crate::look::anim(w.sel as f32, 280);
            w.items = items;
            w.loading = false;
        }
    }
}

pub fn toggle(_: &[String]) -> String {
    let open = !Walls::read().open;
    set_open(open);
    String::from(if open { "opened" } else { "closed" })
}

pub fn ipc(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("open") => set_open(true),
        Some("hide") | Some("close") => set_open(false),
        Some("random") => random(),
        _ => return toggle(args),
    }
    String::from("ok")
}

pub fn set_open(open: bool) {
    let mut w = Walls::write();
    if w.open == open {
        return;
    }
    w.open = open;
    if open {
        w.output = crate::focus_output();
        w.query.clear();
        w.want_scan = true;
        w.loading = true;
        w.anim = crate::look::anim(0.0, 280);
        // появление — после первого кадра (look::appear)
        TextInput::set_text("wallpaper", "");
    } else {
        crate::look::go(&mut w.anim, 0.0);
    }
}

fn select(i: usize) {
    let mut w = Walls::write();
    let n = filter(&w.items, &w.query).len();
    if n == 0 {
        return;
    }
    w.sel = i.min(n - 1);
    let s = w.sel as f32;
    crate::look::go(&mut w.slide, s);
}

fn apply_selected() {
    let w = Walls::read();
    let path = filter(&w.items, &w.query).get(w.sel).map(|w| w.path.clone());
    drop(w);
    if let Some(p) = path {
        apply(&p);
        set_open(false);
    }
}

pub fn random() {
    let cur = Look::read().wallpaper.clone();
    let w = Walls::read();
    let mut others: Vec<String> = w.items.iter().filter(|i| i.path != cur).map(|i| i.path.clone()).collect();
    drop(w);
    if others.is_empty() {
        // список ещё не читали — выбрать прямо из папки
        others = parse(&amane::output(&format!(
            "find -L {} -maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sed 's/$/\\t-\\t/'",
            sh_quote(&dir())
        )))
        .into_iter()
        .map(|w| w.path)
        .filter(|p| *p != cur)
        .collect();
    }
    if !others.is_empty() {
        let n = (crate::clock::unix_now() as usize).wrapping_mul(2654435761) % others.len();
        apply(&others[n]);
    }
}

fn on_key(k: Key) {
    let sel = Walls::read().sel;
    match k {
        Key::Escape => set_open(false),
        Key::Enter => apply_selected(),
        Key::Right | Key::Tab | Key::Down => select(sel + 1),
        Key::Left | Key::Up => select(sel.saturating_sub(1)),
        _ => {}
    }
}

fn head_button(t: &look::Tk, id: &str, code: u32, label: &str, f: impl Fn() + 'static) -> Rectangle {
    let hov = ui::hovered::<WALL>(id);
    let c = if hov { t.p.fg } else { t.p.dim };
    let mut parts: Vec<Box<dyn Widget>> = vec![Box::new(ui::icon(t, code, t.icon - 1.0, c))];
    if !label.is_empty() {
        parts.push(Box::new(ui::text(t, label, c).size(t.fs - 1.0)));
    }
    let row = Row::new(parts).gap(7.0).align(Center);
    let (w, _) = ui::size_of(&row);
    let r = Rectangle::new().width(w + 20.0).height(32.0).radius(10.0).fill(if hov { t.p.surface_hi } else { t.p.surface }).align_child(Center, Center).child(row);
    ui::on_left(ui::track::<WALL>(r, id), f)
}

pub fn view(m: &amane::Monitor) -> LayerWindow {
    let t = look::tk();
    let w = Walls::read();
    let here = w.output == m.name;
    let k = if here { w.anim.value() } else { 0.0 };
    let open = w.open && here;
    look::appear("wallpaper", open, || {
        let mut x = Walls::write();
        if x.open {
            look::go(&mut x.anim, 1.0);
        }
    });
    let list = filter(&w.items, &w.query);
    let current = Look::read().wallpaper.clone();
    let (sw, _) = amane::window_size();
    let panel_w = (sw - 80.0).clamp(400.0, 1180.0);
    let inner = panel_w - 36.0;

    let count = if w.loading { t.tr("loading…", "загрузка…").to_string() } else { list.len().to_string() };
    let search = Rectangle::new()
        .width(260.0)
        .height(32.0)
        .radius(10.0)
        .fill(t.p.surface)
        .padding(Padding { top: 0.0, right: 10.0, bottom: 0.0, left: 10.0 })
        .child(
            Row::new(children![
                ui::icon(&t, ic::SEARCH, t.icon - 1.0, t.p.dim),
                Rectangle::new().width(260.0 - 20.0 - 8.0 - t.icon).height(32.0).align_child(Start, Center).child(
                    TextInput::new("wallpaper")
                        .size(t.fs - 1.0)
                        .color(t.p.fg)
                        .placeholder(t.tr("Search…", "Поиск…"))
                        .on_change(|text| {
                            let mut w = Walls::write();
                            w.query = text;
                            w.sel = 0;
                            w.slide = crate::look::anim(0.0, 280);
                        })
                        .on_submit(|_| apply_selected())
                )
            ])
            .gap(8.0)
            .height(32.0)
            .align(Center),
        );
    let left = Row::new(children![
        ui::icon(&t, 0xF0E09, t.icon + 3.0, t.p.fg),
        ui::bold(&t, t.tr("Wallpapers", "Обои"), t.p.fg).size(t.fs + 2.0),
        ui::text(&t, count, t.p.faint).size(t.fs - 1.0)
    ])
    .gap(10.0)
    .align(Center);
    let right = Row::new(children![
        search,
        head_button(&t, "random", ic::SHUFFLE, t.tr("Random", "Случайные"), || {
            random();
            set_open(false);
        }),
        head_button(&t, "folder", 0xF024B, "", || {
            amane::spawn(&format!("xdg-open {}", sh_quote(&dir())));
            set_open(false);
        })
    ])
    .gap(10.0)
    .align(Center);
    let head = Row::new(children![left, right]).width(inner).justify(SpaceBetween).align(Center);

    // ── карусель: выбранная по центру, сдвиг плавный
    let strip_h = 230.0;
    let carousel: Box<dyn Widget> = if list.is_empty() {
        let msg = if w.loading {
            String::new()
        } else if w.items.is_empty() {
            format!("{} {}", t.tr("No images in", "Нет картинок в"), dir())
        } else {
            t.tr("Nothing found", "Ничего не найдено").to_string()
        };
        Box::new(Rectangle::new().width(inner).height(strip_h).align_child(Center, Center).child(ui::text(&t, msg, t.p.dim)))
    } else {
        let pos = w.slide.value();
        let mut cards: Vec<Box<dyn Widget>> = Vec::new();
        for (i, wall) in list.iter().enumerate() {
            let x = inner / 2.0 - CARD_W / 2.0 + (i as f32 - pos) * (CARD_W + GAP);
            if x < -CARD_W * 1.5 || x > inner + CARD_W * 0.5 {
                continue; // за краем — не рисуем
            }
            let cur = i == w.sel;
            let id = format!("w:{}", wall.path);
            let hov = ui::hovered::<WALL>(&id);
            let active = wall.path == current;
            let mut layers: Vec<Box<dyn Widget>> = vec![Box::new(
                Rectangle::new().width(CARD_W).height(CARD_H).radius(14.0).fill(Image::cover(&wall.thumb)).clip().align_child(Start, End).child(
                    Rectangle::new()
                        .width(CARD_W)
                        .height(64.0)
                        .fill(Gradient::linear(180.0, [(0.0, "#00000000"), (1.0, "#cc000000")]))
                        .opacity(if cur { 1.0 } else { 0.0 })
                        .padding(12.0)
                        .align_child(Start, End)
                        .child(
                            Row::new(children![
                                Rectangle::new().width(CARD_W - 110.0).height(t.fs + 2.0).child(ui::bold(&t, wall.name.clone(), amane::Color::WHITE).size(t.fs - 1.0).elide()),
                                Rectangle::new().width(86.0).height(t.fs + 2.0).align_child(End, Center).child(ui::text(&t, wall.size.clone(), theme_alpha(amane::Color::WHITE, 0.8)).size(t.fs - 3.0))
                            ]),
                        ),
                ),
            )];
            if cur {
                layers.push(Box::new(Rectangle::new().width(CARD_W + 8.0).height(CARD_H + 8.0).radius(18.0).border(2.0, t.p.accent).translate(-4.0, -4.0)));
            }
            if active {
                let lbl = ui::bold(&t, t.tr("current", "сейчас"), t.p.bg).size(t.fs - 3.0);
                let lw = crate::bar::width_of(&lbl);
                layers.push(Box::new(
                    Rectangle::new()
                        .width(lw + 16.0 + 11.0)
                        .height(22.0)
                        .radius(8.0)
                        .fill(t.p.accent)
                        .translate(10.0, 10.0)
                        .align_child(Center, Center)
                        .child(Row::new(children![Rectangle::new().width(6.0).height(6.0).radius(Full).fill(t.p.bg), lbl]).gap(5.0).align(Center)),
                ));
            }
            let scale = if cur { 1.06 } else { 0.9 };
            let opacity = if cur { 1.0 } else if hov { 0.85 } else { 0.5 };
            let path = wall.path.clone();
            let card = Rectangle::new()
                .width(CARD_W)
                .height(CARD_H)
                .translate(x, (strip_h - CARD_H) / 2.0)
                .scale(scale)
                .opacity(opacity)
                .cursor(amane::Pointer)
                .on_click(move |_| {
                    if Walls::read().sel == i {
                        apply(&path);
                        set_open(false);
                    } else {
                        select(i);
                    }
                })
                .child(Stack::new(layers));
            cards.push(Box::new(ui::track::<WALL>(card, id)));
        }
        Box::new(
            Rectangle::new()
                .width(inner)
                .height(strip_h)
                .clip()
                .on_scroll(|s| {
                    let sel = Walls::read().sel;
                    if s.y > 0.0 { select(sel + 1) } else { select(sel.saturating_sub(1)) }
                })
                .child(Stack::new(cards).width(inner).height(strip_h)),
        )
    };
    // точки-страницы под каруселью
    let n = list.len();
    let mut dots: Vec<Box<dyn Widget>> = Vec::new();
    if n > 1 && n <= 40 {
        for i in 0..n {
            dots.push(Box::new(Rectangle::new().width(if i == w.sel { 16.0 } else { 6.0 }).height(6.0).radius(3.0).fill(if i == w.sel { t.p.accent } else { t.p.faint })));
        }
    }
    drop(w);
    let mut col: Vec<Box<dyn Widget>> = vec![Box::new(head), carousel];
    if !dots.is_empty() {
        col.push(Box::new(Rectangle::new().width(inner).height(6.0).align_child(Center, Center).child(Row::new(dots).gap(6.0))));
    }
    let content = Column::new(col).gap(14.0);
    let (_, ch) = ui::size_of(&content);
    let panel_h = ch + 36.0;
    let bar_h = t.bar_h;
    let y = (bar_h + 12.0) * k + (-panel_h - 20.0) * (1.0 - k);
    let panel = Rectangle::new()
        .width(panel_w)
        .height(panel_h)
        .radius(22.0)
        .fill(t.panel)
        .border(1.0, t.p.surface_hi2)
        .padding(18.0)
        .opacity(k)
        .translate(0.0, y)
        .on_click(|_| {})
        .child(content);
    LayerWindow::new()
        .width(Full)
        .height(Full)
        .anchor_vertical(Vertical::Top)
        .margin(Margin { top: 0, right: 0, bottom: 0, left: 0 })
        .layer(Layer::Overlay)
        .space(Zone::Ignore)
        .namespace("rexilone-wallpaper")
        .keyboard(if open { Keyboard::Exclusive } else { Keyboard::None })
        .on_key(on_key)
        .visible(open || k > 0.01)
        .child(
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .fill(Color::rgba(0, 0, 0, (0.3 * k * 255.0) as u8))
                .align_child(Center, Start)
                .on_click(|_| set_open(false))
                .child(panel),
        )
}

fn theme_alpha(c: Color, a: f32) -> Color {
    crate::theme::alpha(c, a)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_scan() {
        let w = parse("/w/Forest Night.jpg\t/c/1.jpg\t3840x2160\n/w/a.b.png\t/c/2.jpg\t\n\n");
        assert_eq!(w.len(), 2);
        assert_eq!(w[0].name, "Forest Night");
        assert_eq!(w[0].size, "3840x2160");
        assert_eq!(w[1].name, "a.b");
        assert_eq!(filter(&w, "forest").len(), 1);
        assert_eq!(filter(&w, "").len(), 2);
    }
}
