// Персонализация: цвета (в т.ч. под обои), обои, прозрачность, шрифты, размер, бар, виджеты
// (PersonalizationPage.qml, BarPanel.qml, WidgetsPanel.qml)

use amane::{Center, Color, Column, End, Image, Padding, Rectangle, Row, Service, Stack, Start, Weight, children};

use super::super::Prefs;
use super::super::w::{self, Btn, Card, Slide, W, act, bx};
use super::{Out, set_tab, tab};
use crate::json::Json;
use crate::look::{Look, Tk};
use crate::niri::Niri;
use crate::settings::{self, Settings};
use crate::theme::Palette;
use crate::ui;
use crate::wallpaper;

const PAGE: usize = 7;

fn set(key: &str, v: Json) {
    settings::save_key(key, v);
}

fn fonts() -> (Vec<String>, Vec<String>) {
    let out = crate::cmd::get(
        "fonts",
        "fc-list : family | cut -d, -f1 | sort -uf; echo '@mono'; fc-list :spacing=mono family | cut -d, -f1 | sort -uf",
    )
    .unwrap_or_default();
    let (all, mono) = out.split_once("@mono").unwrap_or((&out, ""));
    let clean = |t: &str| t.lines().map(|x| x.trim().to_string()).filter(|x| !x.is_empty() && !x.starts_with('.')).collect::<Vec<_>>();
    (clean(all), clean(mono))
}

pub fn walls() -> Vec<wallpaper::Wall> {
    wallpaper::parse(&crate::cmd::get("walls", &wallpaper::scan_cmd()).unwrap_or_default())
}

fn file_name(p: &str) -> String {
    p.rsplit('/').next().unwrap_or(p).to_string()
}

const SCHEMES: [&str; 6] = ["dark", "light", "nord", "gruvbox", "rose", "wallpaper"];

pub fn page(t: &Tk, w: f32) -> Out {
    let raw = Settings::read().raw.clone();
    let tb = tab(PAGE);
    let cur_wall = Look::read().wallpaper.clone();
    let opacity = raw.get("opacity").num_or(0.85);
    let transparency = raw.get("transparency").bool_or(false);
    let blur = raw.get("blur").bool_or(true);
    let font = t.c.font.clone();
    let mono = raw.get("monoFont").str_or("JetBrainsMono Nerd Font");
    let widgets_on = raw.get("widgets").obj().iter().filter(|(_, v)| v.get("enabled").bool_or(false)).count();
    let style_name = match t.c.bar_style.as_str() {
        "flat" => "Solid",
        "floating" => "Floating",
        "pills" => "Pills",
        s => s,
    };
    let sections: [(&str, &str, u32, String); 7] = [
        ("colors", "Colors", 0xF03D8, format!("{}   ·   {}", t.t(t.p.name), t.t("dark, light, Nord, Gruvbox, Rosé, from wallpaper"))),
        ("wallpaper", "Wallpaper", 0xF0E09, if cur_wall.is_empty() { t.t("Pick a picture for the desktop") } else { file_name(&cur_wall) }),
        (
            "transparency",
            "Transparency",
            0xF05CC,
            if transparency {
                format!("{}   ·   {}%{}", t.t("On"), (opacity * 100.0).round(), if blur { format!(", {}", t.t("blur")) } else { String::new() })
            } else {
                t.t("Off")
            },
        ),
        ("fonts", "Fonts", 0xF06D6, {
            let mut v = vec![font.clone()];
            if mono != font {
                v.push(mono.clone());
            }
            v.join("   ·   ")
        }),
        ("size", "Text size", 0xF0284, format!("{}%   ·   {}", (t.c.ui_scale * 100.0).round(), t.t("bar and menus"))),
        ("bar", "Bar", 0xF0570, format!("{}   ·   {}", t.t(style_name), t.t("clock, modules, tray"))),
        ("widgets", "Widgets", 0xF0B92, format!("{} {}   ·   {}", widgets_on, t.tr("on the desktop", "на рабочем столе"), t.t("clock, weather, phone…"))),
    ];
    let crumb = sections.iter().find(|s| s.0 == tb).map(|s| s.1.to_string()).unwrap_or_default();
    let mut items: Vec<W> = Vec::new();
    match tb.as_str() {
        "" => {
            items.push(bx(preview(t, w, &cur_wall)));
            items.push(bx(w::gap(8.0)));
            for (key, label, icon, desc) in &sections {
                let key = key.to_string();
                items.push(bx(Card::new(*icon, label, desc).id(label).click(move || set_tab(PAGE, &key)).build(t, w)));
            }
        }
        "colors" => {
            let mut cards: Vec<W> = Vec::new();
            for s in SCHEMES {
                cards.push(bx(scheme_card(t, s, &raw.get("scheme").str_or("dark"), &cur_wall)));
            }
            items.push(bx(flow(cards, w, 168.0, 10.0)));
            if raw.get("scheme").str() == Some("wallpaper") {
                items.push(bx(w::para(t, &t.t("Colors follow the current wallpaper and update when you change it."), t.fs - 2.0, t.p.dim, w)));
            }
        }
        "wallpaper" => {
            let title = if cur_wall.is_empty() { t.t("Wallpaper") } else { file_name(&cur_wall) };
            let btns = Row::new(children![
                Btn::new("Random").icon(0xF049D).build(t, "wp-random", || {
                    wallpaper::random();
                    crate::cmd::forget("walls");
                }),
                Btn::new("Browse…").primary().build(t, "wp-browse", || {
                    crate::prefs::close();
                    wallpaper::set_open(true);
                })
            ])
            .gap(8.0);
            let desc = format!("{}: {}", t.t("Folder"), wallpaper::dir());
            items.push(bx(Card::new(0xF0E09, &title, &desc).ctrl(btns).build(t, w)));
            let list = walls();
            let tw = w::width_for(4, w, 8.0);
            let th = (tw * 9.0 / 16.0).round();
            let mut thumbs: Vec<W> = Vec::new();
            for wall in &list {
                let cur = wall.path == cur_wall;
                let id = format!("wpt:{}", wall.path);
                let hv = w::hov(&id);
                let img = Rectangle::new()
                    .width(tw - if cur { 6.0 } else { 0.0 })
                    .height(th - if cur { 6.0 } else { 0.0 })
                    .radius(if cur { 6.0 } else { 8.0 })
                    .fill(Image::cover(&wall.thumb))
                    .opacity(if hv || cur { 1.0 } else { 0.85 });
                let mut r = Rectangle::new().width(tw).height(th).radius(8.0).fill(t.p.surface).align_child(Center, Center).clip().child(img);
                if cur {
                    r = r.border(2.0, t.p.accent);
                }
                let path = wall.path.clone();
                thumbs.push(bx(w::clickable(r, &id, act(move || wallpaper::apply(&path)))));
            }
            items.push(bx(w::gap(10.0)));
            items.push(bx(w::grid(thumbs, 4, 8.0)));
        }
        "transparency" => {
            items.push(bx(Card::new(0xF0E7A, "Transparency effects", "See-through bar, menus and settings window")
                .ctrl(w::switch(t, "transp", transparency, |v| set("transparency", Json::Bool(v))))
                .build(t, w)));
            if transparency {
                items.push(bx(Card::new(0xF0AAB, "Panel opacity", "Lower is more transparent")
                    .ctrl(Slide::new(opacity, 0.4, 1.0, 0.05).display(opacity * 100.0).suffix("%").build(t, "opacity", |v| set("opacity", Json::Num((v * 100.0).round() / 100.0))))
                    .build(t, w)));
                items.push(bx(Card::new(0xF00B6, "Blur behind panels", "Frosted glass look (niri background blur)")
                    .ctrl(w::switch(t, "blur", blur, |v| set("blur", Json::Bool(v))))
                    .build(t, w)));
                let to = raw.get("terminalOpacity").num_or(1.0);
                items.push(bx(Card::new(0xF018D, "Terminal opacity", "foot — applies to new terminal windows")
                    .ctrl(Slide::new(to, 0.5, 1.0, 0.05).display(to * 100.0).suffix("%").build(t, "termop", |v| set("terminalOpacity", Json::Num((v * 100.0).round() / 100.0))))
                    .build(t, w)));
            }
        }
        "fonts" => {
            let (all, monos) = fonts();
            let opts = |l: &[String]| l.iter().map(|f| (f.clone(), f.clone())).collect::<Vec<_>>();
            items.push(bx(Card::new(0xF0281, "Interface font", "Bar, menus, notifications and settings")
                .ctrl(w::dropdown(t, "font", &opts(&all), &font, 260.0, |v| set("font", Json::Str(v))))
                .build(t, w)));
            items.push(bx(Card::new(0xF018D, "Terminal font", "foot, Neovim and yazi — monospace fonts only")
                .ctrl(w::dropdown(t, "monofont", &opts(&monos), &mono, 260.0, |v| set("monoFont", Json::Str(v))))
                .build(t, w)));
            let mut app = vec![(String::new(), "System default".to_string())];
            app.extend(opts(&all));
            items.push(bx(Card::new(0xF03D8, "Apps font", "GTK apps (Files, settings dialogs…)")
                .ctrl(w::dropdown(t, "appfont", &app, &raw.get("appFont").str_or(""), 260.0, |v| set("appFont", Json::Str(v))))
                .build(t, w)));
            items.push(bx(w::para(t, &t.t("Icons need a Nerd Font — if icons turn into boxes, pick a font with «Nerd Font» in the name."), t.fs - 2.0, t.p.dim, w)));
        }
        "size" => {
            let cur = format!("{}", t.c.ui_scale);
            items.push(bx(Card::new(0xF0284, "Text size", "Scales fonts and icons in the bar and menus")
                .ctrl(w::choice(t, "uiscale", &[("0.9", "90%"), ("1", "100%"), ("1.1", "110%"), ("1.25", "125%")], &cur, |v| {
                    set("uiScale", Json::Num(v.parse().unwrap_or(1.0)))
                }))
                .build(t, w)));
        }
        "bar" => items.extend(bar_panel(t, w, &raw)),
        "widgets" => items.extend(widgets_panel(t, w, &raw)),
        _ => {}
    }
    Out { crumb, subtitle: if tb.is_empty() { "Colors, wallpaper, fonts, the bar and desktop widgets".into() } else { String::new() }, items }
}

// карточки в ряд с переносом
fn flow(items: Vec<W>, w: f32, item_w: f32, gap: f32) -> Column {
    let per = (((w + gap) / (item_w + gap)).floor() as usize).max(1);
    w::grid(items, per, gap)
}

// превью: обои с полоской бара и окном, палитра схемы
fn preview(t: &Tk, w: f32, wall: &str) -> Rectangle {
    let mw = 160.0 * 16.0 / 9.0;
    let thumb = walls().into_iter().find(|x| x.path == wall).map(|x| x.thumb).unwrap_or_else(|| wall.to_string());
    let flat = t.c.bar_style == "flat";
    let bar = Rectangle::new().width(if flat { mw } else { mw - 8.0 }).height(10.0).radius(if flat { 0.0 } else { 5.0 }).fill(t.panel).translate(if flat { 0.0 } else { 4.0 }, if flat { 0.0 } else { 4.0 });
    let win_w = mw * 0.5;
    let win_h = 160.0 * 0.52;
    let win = Rectangle::new()
        .width(win_w)
        .height(win_h)
        .radius(4.0)
        .fill(t.p.surface)
        .border(1.0, t.p.surface_hi2)
        .translate(mw * 0.18, 160.0 * 0.28)
        .child(Stack::new(children![
            Rectangle::new().width(win_w * 0.4).height(4.0).radius(2.0).fill(t.p.fg).translate(8.0, 10.0),
            Rectangle::new().width(win_w * 0.6).height(4.0).radius(2.0).fill(t.p.dim).translate(8.0, 20.0),
            Rectangle::new().width(30.0).height(10.0).radius(3.0).fill(t.p.accent).translate(win_w - 38.0, win_h - 18.0)
        ]));
    let mut screen = Rectangle::new().width(mw).height(160.0).radius(8.0).fill(t.p.bg).clip();
    let mut layers: Vec<W> = Vec::new();
    if !thumb.is_empty() {
        layers.push(bx(Rectangle::new().width(mw).height(160.0).fill(Image::cover(&thumb).thumbnail(640, 360))));
    }
    layers.push(bx(bar));
    layers.push(bx(win));
    screen = screen.child(Stack::new(layers));
    let mut dots: Vec<W> = Vec::new();
    for c in [t.p.bg, t.p.surface_hi2, t.p.dim, t.p.fg, t.p.accent, t.p.warn, t.p.urgent] {
        dots.push(bx(Rectangle::new().width(22.0).height(22.0).radius(amane::Full).fill(c).border(1.0, t.p.line)));
    }
    let tw = w - 36.0 - mw - 24.0;
    let info = Column::new(children![
        w::line(t, &t.t(t.p.name), t.fs + 4.0, t.p.fg, tw, true),
        w::line(t, &if wall.is_empty() { t.t("No wallpaper") } else { file_name(wall) }, t.fs - 2.0, t.p.dim, tw, false),
        w::gap(10.0),
        Row::new(dots).gap(6.0)
    ])
    .gap(4.0);
    Rectangle::new()
        .width(w)
        .height(196.0)
        .radius(12.0)
        .fill(t.p.surface)
        .padding(18.0)
        .child(Row::new(children![screen, info]).gap(24.0).height(160.0).align(Center))
}

// карточка схемы с мини-превью
fn scheme_card(t: &Tk, s: &str, cur: &str, wall: &str) -> Rectangle {
    let p = if s == "wallpaper" {
        let l = Look::read();
        if l.p.name == "Wallpaper" { l.p } else { Palette::scheme("dark") }
    } else {
        Palette::scheme(s)
    };
    let sel = s == cur;
    let id = format!("scheme:{s}");
    let hv = w::hov(&id);
    let iw = 168.0 - 20.0;
    let mut layers: Vec<W> = Vec::new();
    if s == "wallpaper" && !wall.is_empty() {
        layers.push(bx(Rectangle::new().width(iw).height(80.0).fill(Image::cover(wall).thumbnail(300, 170)).opacity(0.55)));
    }
    layers.push(bx(Rectangle::new().width(iw).height(12.0).fill(crate::theme::alpha(p.bg, 0.95)).align_child(Start, Center).padding(Padding { top: 0.0, right: 0.0, bottom: 0.0, left: 6.0 }).child(Rectangle::new().width(14.0).height(4.0).radius(2.0).fill(p.accent))));
    layers.push(bx(Rectangle::new().width(iw - 24.0).height(48.0).radius(6.0).fill(p.surface).translate(12.0, 22.0).padding(Padding { top: 9.0, right: 0.0, bottom: 0.0, left: 8.0 }).child(
        Column::new(children![
            Rectangle::new().width(60.0).height(5.0).radius(2.0).fill(p.fg),
            Rectangle::new().width(90.0).height(4.0).radius(2.0).fill(p.dim),
            Rectangle::new().width(36.0).height(8.0).radius(4.0).fill(p.accent)
        ])
        .gap(6.0),
    )));
    let mini = Rectangle::new().width(iw).height(80.0).radius(8.0).fill(p.bg).clip().child(Stack::new(layers));
    let name = w::tx(t, if s == "wallpaper" { "From wallpaper" } else { p.name }, t.fs - 1.0, t.p.fg);
    let name = if sel { name.weight(Weight::Bold) } else { name };
    let mut bottom: Vec<W> = vec![bx(Rectangle::new().width(iw - 24.0).height(20.0).align_child(Start, Center).child(name))];
    if sel {
        bottom.push(bx(Rectangle::new().width(24.0).height(20.0).align_child(End, Center).child(ui::icon(t, 0xF012C, t.icon, t.p.accent))));
    }
    let r = Rectangle::new()
        .width(168.0)
        .height(128.0)
        .radius(12.0)
        .fill(t.p.surface)
        .border(if sel { 2.0 } else { 1.0 }, if sel { t.p.accent } else if hv { t.p.line } else { t.p.surface_hi2 })
        .padding(Padding { top: 10.0, right: 10.0, bottom: 0.0, left: 10.0 })
        .child(Column::new(children![mini, Rectangle::new().width(iw).height(38.0).padding(Padding { top: 9.0, right: 0.0, bottom: 0.0, left: 2.0 }).child(Row::new(bottom))]));
    let s = s.to_string();
    w::clickable(r, &id, act(move || set("scheme", Json::Str(s.clone()))))
}

// ── бар
fn bar_panel(t: &Tk, w: f32, raw: &Json) -> Vec<W> {
    let mut items: Vec<W> = vec![bx(w::section(t, "Style", w))];
    let mut styles: Vec<W> = Vec::new();
    for (v, label) in [("flat", "Solid"), ("floating", "Floating"), ("pills", "Pills")] {
        let sel = t.c.bar_style == v;
        let id = format!("barstyle:{v}");
        let hv = w::hov(&id);
        let iw = 180.0;
        let prev: W = match v {
            "flat" => bx(Rectangle::new().width(iw).height(10.0).fill(t.p.surface_hi2)),
            "floating" => bx(Rectangle::new().width(iw - 12.0).height(10.0).radius(4.0).fill(t.p.surface_hi2).translate(6.0, 5.0)),
            _ => bx(Rectangle::new().width(iw).height(15.0).padding(Padding { top: 5.0, right: 0.0, bottom: 0.0, left: 6.0 }).child(Row::new(children![
                Rectangle::new().width(36.0).height(10.0).radius(5.0).fill(t.p.surface_hi2),
                Rectangle::new().width(36.0).height(1.0),
                Rectangle::new().width(40.0).height(10.0).radius(5.0).fill(t.p.surface_hi2),
                Rectangle::new().width(22.0).height(1.0),
                Rectangle::new().width(30.0).height(10.0).radius(5.0).fill(t.p.surface_hi2)
            ]))),
        };
        let mini = Rectangle::new().width(iw).height(44.0).radius(8.0).fill(t.p.bg).clip().child(Column::new(vec![prev]));
        let name = w::tx(t, label, t.fs - 1.0, t.p.fg);
        let name = if sel { name.weight(Weight::Bold) } else { name };
        let r = Rectangle::new()
            .width(200.0)
            .height(96.0)
            .radius(12.0)
            .fill(t.p.surface)
            .border(if sel { 2.0 } else { 1.0 }, if sel { t.p.accent } else if hv { t.p.line } else { t.p.surface_hi2 })
            .padding(Padding { top: 10.0, right: 10.0, bottom: 0.0, left: 10.0 })
            .child(Column::new(children![mini, Rectangle::new().width(iw).height(36.0).padding(Padding { top: 10.0, right: 0.0, bottom: 0.0, left: 2.0 }).child(name)]));
        let v = v.to_string();
        styles.push(bx(w::clickable(r, &id, act(move || set("barStyle", Json::Str(v.clone()))))));
    }
    items.push(bx(flow(styles, w, 200.0, 10.0)));

    items.push(bx(w::section(t, "Show the bar on", w)));
    let outs = Niri::read().s.outputs.clone();
    let on = t.c.bar_on(&outs);
    let primary = t.c.primary(&outs);
    for (name, ow, oh) in &outs {
        let is_on = on.contains(name);
        let only = is_on && on.len() == 1;
        let title = if *name == primary { format!("{}   ·   {}", name, t.t("main display")) } else { name.clone() };
        let n = name.clone();
        let on2 = on.clone();
        let sw = w::switch(t, &format!("baron:{name}"), is_on, move |v| {
            if only {
                return; // хотя бы один монитор с баром
            }
            let mut cur = on2.clone();
            if v {
                cur.push(n.clone());
            } else {
                cur.retain(|x| *x != n);
            }
            set("barScreens", Json::Arr(cur.into_iter().map(Json::Str).collect()));
        })
        .opacity(if only { 0.4 } else { 1.0 });
        items.push(bx(Card::new(0xF0379, &title, &format!("{ow}×{oh}")).id(name).ctrl(sw).build(t, w)));
    }

    items.push(bx(w::section(t, "Layout", w)));
    items.push(bx(Card::new(0xF0E14, "Height", "")
        .ctrl(Slide::new(t.c.bar_height as f64, 26.0, 44.0, 1.0).suffix(" px").build(t, "barh", |v| set("barHeight", Json::Num(v.round()))))
        .build(t, w)));
    let clock_opts: Vec<(String, String)> = [
        ("dddd HH:mm", "Friday 15:00"),
        ("HH:mm", "15:00"),
        ("HH:mm:ss", "15:00:42"),
        ("ddd d MMM  HH:mm", "Fri 3 Oct  15:00"),
        ("dddd, d MMMM  HH:mm", "Friday, 3 October  15:00"),
        ("h:mm AP", "3:00 PM"),
    ]
    .iter()
    .map(|(a, b)| (a.to_string(), b.to_string()))
    .collect();
    items.push(bx(Card::new(0xF0954, "Clock format", "Shown in the center of the bar")
        .ctrl(w::dropdown(t, "clockfmt", &clock_opts, &t.c.clock_format, 230.0, |v| set("clockFormat", Json::Str(v))))
        .build(t, w)));
    items.push(bx(Card::new(0xF0570, "Workspaces", "How workspaces look on the left")
        .ctrl(w::choice(t, "wsstyle", &[("dots", "Dots"), ("numbers", "Numbers")], &t.c.workspace_style, |v| set("workspaceStyle", Json::Str(v))))
        .build(t, w)));
    if t.c.module("tray") {
        let desc = if t.c.tray_mode == "menu" {
            "In a menu behind a button; pinned apps stay in the bar (pin them in the menu)"
        } else {
            "All app icons right in the bar"
        };
        items.push(bx(Card::new(0xF003B, "Tray apps", desc)
            .ctrl(w::choice(t, "traymode", &[("inline", "In the bar"), ("menu", "In a menu")], &t.c.tray_mode, |v| set("trayMode", Json::Str(v))))
            .build(t, w)));
    }

    items.push(bx(w::section(t, "Modules", w)));
    let mods: [(&str, bool, u32, &str, &str); 15] = [
        ("launcher", true, 0xF08C7, "App launcher", "Button at the very left that opens the app menu (Super+D)"),
        ("control", true, 0xF062E, "Control center", "Quick toggles, volume, media and power in one menu"),
        ("window", false, 0xF05AF, "Active window", "Title and icon of the focused window"),
        ("media", false, 0xF075A, "Now playing", "Track and play/pause; click opens the player"),
        ("weather", false, 0xF0595, "Weather", "Temperature next to the clock"),
        ("stats", false, 0xF061A, "CPU & RAM", "Load at a glance; click opens system stats"),
        ("updates", false, 0xF06B0, "System updates", "Shows available pacman updates; click to update"),
        ("phone", true, 0xF011C, "Phone (Rexlink)", "Battery and notifications of your phone; click for the phone menu"),
        ("castHidden", true, 0xF0209, "Hidden from screencast", "Shown while apps are hidden with Super+G; click for the list"),
        ("tray", true, 0xF0DCA, "System tray", "App icons"),
        ("keyboard", true, 0xF030C, "Keyboard layout", "en / ru indicator"),
        ("volume", true, 0xF057E, "Volume", "Speaker and mixer"),
        ("mic", true, 0xF036C, "Microphone", "Mic level and mute"),
        ("network", true, 0xF0200, "Network", "Connection and speed"),
        ("notifications", true, 0xF009A, "Notifications", "Bell and notification list"),
    ];
    for (key, def, icon, title, desc) in mods {
        let on = t.c.module_on(key, def);
        let k = key.to_string();
        let sw = w::switch(t, &format!("mod:{key}"), on, move |v| settings::save_path(&["barModules", &k], Json::Bool(v)));
        let ctrl: W = if key == "updates" && !crate::cmd::get("checkupdates?", "command -v checkupdates >/dev/null && echo 1").is_some_and(|v| v == "1") {
            bx(Row::new(children![
                Btn::new("Install").build(t, "updates-install", || amane::spawn("setsid -f foot -e sh -c 'sudo pacman -S --needed pacman-contrib; read -r -p \"Enter…\" _'")),
                sw
            ])
            .gap(8.0)
            .align(Center))
        } else {
            bx(sw)
        };
        items.push(bx(Card::new(icon, title, desc).ctrl_box(ctrl).build(t, w)));
    }
    items
}

// ── виджеты рабочего стола
fn widgets_panel(t: &Tk, w: f32, raw: &Json) -> Vec<W> {
    let editing = Prefs::flag("widgets-editing");
    let mut items: Vec<W> = vec![bx(Card::new(
        0xF0B92,
        if editing { "Editing — drag widgets on the desktop" } else { "Arrange widgets" },
        "Widgets float above windows while editing. Press Done to lock them in place.",
    )
    .ctrl(Btn::new(if editing { "Done" } else { "Edit layout" }).primary().build(t, "widgets-edit", || {
        Prefs::toggle_flag("widgets-editing");
        let on = Prefs::flag("widgets-editing");
        crate::settings::save_key("widgetsEditing", Json::Bool(on));
    }))
    .build(t, w))];
    let (fonts, _) = fonts();
    let outs: Vec<(String, String)> = Niri::read().s.outputs.iter().map(|(n, _, _)| (n.clone(), n.clone())).collect();
    let primary = t.c.primary(&Niri::read().s.outputs);
    let sizes = [("0.75", "S"), ("1", "M"), ("1.25", "L"), ("1.5", "XL")];
    let defs: [(&str, u32, &str, &str); 7] = [
        ("clock", 0xF0954, "Clock", "Big time and date"),
        ("perf", 0xF061A, "Performance", "CPU, GPU and RAM rings"),
        ("weather", 0xF0595, "Weather", "Now and next 3 days"),
        ("media", 0xF075A, "Media", "What's playing, with controls"),
        ("calendar", 0xF00ED, "Calendar", "Month view with notes"),
        ("notes", 0xF0D2F, "Today's notes", "Notes and reminders for today"),
        ("quote", 0xF0757, "Quote of the day", "Changes daily, click for next"),
    ];
    fn wset(id: &str, key: &str, v: Json) {
        settings::save_path(&["widgets", id, key], v);
    }
    for (id, icon, name, desc) in defs {
        let cfg = raw.get("widgets").get(id);
        let on = cfg.get("enabled").bool_or(false);
        items.push(bx(w::gap(10.0)));
        let ids = id.to_string();
        items.push(bx(Card::new(icon, name, desc).id(id).ctrl(w::switch(t, &format!("w:{id}"), on, move |v| wset(&ids, "enabled", Json::Bool(v)))).build(t, w)));
        if !on {
            continue;
        }
        let ids = id.to_string();
        let screen = cfg.get("screen").str().filter(|s| !s.is_empty()).map(String::from).unwrap_or_else(|| primary.clone());
        items.push(bx(Card::new(0, "Monitor", "").id(&format!("{id}-mon")).ctrl(w::dropdown(t, &format!("wmon:{id}"), &outs, &screen, 170.0, move |v| wset(&ids, "screen", Json::Str(v)))).build(t, w)));
        let ids = id.to_string();
        items.push(bx(Card::new(0, "Background", "Card behind the widget, or just content over the wallpaper")
            .id(&format!("{id}-bg"))
            .ctrl(w::switch(t, &format!("wbg:{id}"), cfg.get("background").bool_or(true), move |v| wset(&ids, "background", Json::Bool(v))))
            .build(t, w)));
        let ids = id.to_string();
        let size = format!("{}", cfg.get("size").num_or(1.0));
        items.push(bx(Card::new(0, "Size", "").id(&format!("{id}-size")).ctrl(w::choice(t, &format!("wsize:{id}"), &sizes, &size, move |v| wset(&ids, "size", Json::Num(v.parse().unwrap_or(1.0))))).build(t, w)));
        if id == "clock" {
            let mut fo = vec![(String::new(), "Same as interface".to_string())];
            fo.extend(fonts.iter().map(|f| (f.clone(), f.clone())));
            items.push(bx(Card::new(0, "Font", "").id("clock-font").ctrl(w::dropdown(t, "wfont", &fo, &cfg.get("font").str_or(""), 240.0, |v| wset("clock", "font", Json::Str(v)))).build(t, w)));
            items.push(bx(Card::new(0, "Format", "")
                .id("clock-format")
                .ctrl(w::choice(t, "wfmt", &[("HH:mm", "15:00"), ("HH:mm:ss", "15:00:42"), ("h:mm AP", "3:00 PM")], &cfg.get("format").str_or("HH:mm"), |v| wset("clock", "format", Json::Str(v))))
                .build(t, w)));
            items.push(bx(Card::new(0, "Show date", "").id("clock-date").ctrl(w::switch(t, "wdate", cfg.get("showDate").bool_or(true), |v| wset("clock", "showDate", Json::Bool(v)))).build(t, w)));
        }
    }

    // ── виджеты телефона (Rexlink)
    items.push(bx(w::section(t, "Phone widgets", w)));
    let variants: Vec<(String, String)> = [("full", "Everything"), ("battery", "Battery"), ("status", "Status & signal"), ("notifications", "Notifications"), ("media", "Media"), ("actions", "Quick actions")]
        .iter()
        .map(|(a, b)| (a.to_string(), b.to_string()))
        .collect();
    let devs = crate::rexlink::devices();
    let mut dev_opts = vec![(String::new(), "Current device".to_string())];
    dev_opts.extend(devs.iter().map(|d| (d.id.clone(), format!("{}{}", d.name, if d.online { "" } else { "  (offline)" }))));
    if !crate::rexlink::connected() {
        items.push(bx(Card::new(0xF011C, "Rexlink isn't running", "Phone widgets show data from Rexlink — start it in Settings → Phone").build(t, w)));
    }
    let nv = Prefs::get("pw-new-variant");
    let nv = if nv.is_empty() { "full".to_string() } else { nv };
    let nd = Prefs::get("pw-new-device");
    let pr = primary.clone();
    let add = Row::new(children![
        w::dropdown(t, "pw-variant", &variants, &nv, 170.0, |v| Prefs::set("pw-new-variant", &v)),
        w::dropdown(t, "pw-device", &dev_opts, &nd, 170.0, |v| Prefs::set("pw-new-device", &v)),
        Btn::new("Add").primary().build(t, "pw-add", move || {
            let v = Prefs::get("pw-new-variant");
            add_phone_widget(&Prefs::get("pw-new-device"), if v.is_empty() { "full" } else { &v }, &pr);
        })
    ])
    .gap(8.0);
    items.push(bx(Card::new(0, "Add a phone widget", "One per device and kind — e.g. tablet battery next to phone notifications").ctrl(add).build(t, w)));
    let mut ids: Vec<String> = raw.get("widgets").obj().iter().map(|(k, _)| k.clone()).filter(|k| k.starts_with("phone-")).collect();
    ids.sort();
    for pid in ids {
        let cfg = raw.get("widgets").get(&pid);
        let variant = cfg.get("variant").str_or("full");
        let device = cfg.get("device").str_or("");
        let vlabel = variants.iter().find(|(v, _)| *v == variant).map(|(_, l)| l.clone()).unwrap_or_else(|| "Everything".into());
        let dname = if device.is_empty() {
            t.t("current device")
        } else {
            devs.iter().find(|d| d.id == device).map(|d| d.name.clone()).unwrap_or_else(|| t.t("unknown device"))
        };
        let screen = cfg.get("screen").str().filter(|s| !s.is_empty()).map(String::from).unwrap_or_else(|| primary.clone());
        let title = format!("{}  ·  {}", t.t(&vlabel), dname);
        let desc = if cfg.get("enabled").bool_or(true) { format!("{} {}", t.t("On"), screen) } else { t.t("Hidden") };
        let (p1, p2) = (pid.clone(), pid.clone());
        let ctrl = Row::new(children![
            Btn::new("").icon(ui::ic::TRASH).danger().build(t, &format!("pwdel:{pid}"), move || {
                let mut all = settings::load().get("widgets").clone();
                if let Json::Obj(items) = &mut all {
                    items.retain(|(k, _)| *k != p1);
                }
                settings::save_key("widgets", all);
            }),
            w::switch(t, &format!("pwon:{pid}"), cfg.get("enabled").bool_or(true), move |v| settings::save_path(&["widgets", &p2, "enabled"], Json::Bool(v)))
        ])
        .gap(8.0)
        .align(Center);
        items.push(bx(w::gap(8.0)));
        items.push(bx(Card::new(0xF011C, &title, &desc).id(&pid).ctrl(ctrl).build(t, w)));
        let p = pid.clone();
        items.push(bx(Card::new(0, "Kind", "").id(&format!("{pid}-k")).ctrl(w::dropdown(t, &format!("pwk:{pid}"), &variants, &variant, 190.0, move |v| settings::save_path(&["widgets", &p, "variant"], Json::Str(v)))).build(t, w)));
        let p = pid.clone();
        items.push(bx(Card::new(0, "Device", "").id(&format!("{pid}-d")).ctrl(w::dropdown(t, &format!("pwd:{pid}"), &dev_opts, &device, 190.0, move |v| settings::save_path(&["widgets", &p, "device"], Json::Str(v)))).build(t, w)));
        let p = pid.clone();
        items.push(bx(Card::new(0, "Monitor", "").id(&format!("{pid}-m")).ctrl(w::dropdown(t, &format!("pwm:{pid}"), &outs, &screen, 170.0, move |v| settings::save_path(&["widgets", &p, "screen"], Json::Str(v)))).build(t, w)));
        let p = pid.clone();
        items.push(bx(Card::new(0, "Background", "").id(&format!("{pid}-b")).ctrl(w::switch(t, &format!("pwb:{pid}"), cfg.get("background").bool_or(true), move |v| settings::save_path(&["widgets", &p, "background"], Json::Bool(v)))).build(t, w)));
        let p = pid.clone();
        let size = format!("{}", cfg.get("size").num_or(1.0));
        items.push(bx(Card::new(0, "Size", "").id(&format!("{pid}-s")).ctrl(w::choice(t, &format!("pws:{pid}"), &sizes, &size, move |v| settings::save_path(&["widgets", &p, "size"], Json::Num(v.parse().unwrap_or(1.0))))).build(t, w)));
    }
    let _ = Color::TRANSPARENT;
    items
}

// новый виджет телефона: phone-<n> с позицией лесенкой
pub fn add_phone_widget(device: &str, variant: &str, primary: &str) {
    let mut all = settings::load().get("widgets").clone();
    let mut n = 1;
    while !all.get(&format!("phone-{n}")).is_null() {
        n += 1;
    }
    let o = Json::Obj(vec![
        ("type".into(), Json::Str("phone".into())),
        ("device".into(), Json::Str(device.into())),
        ("variant".into(), Json::Str(variant.into())),
        ("enabled".into(), Json::Bool(true)),
        ("screen".into(), Json::Str(primary.into())),
        ("x".into(), Json::Num(120.0 + (n - 1) as f64 * 40.0)),
        ("y".into(), Json::Num(140.0 + (n - 1) as f64 * 40.0)),
        ("background".into(), Json::Bool(true)),
        ("size".into(), Json::Num(1.0)),
    ]);
    all.set(&format!("phone-{n}"), o);
    settings::save_key("widgets", all);
}
