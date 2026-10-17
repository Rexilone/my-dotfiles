// переносит схему шелла в foot, Neovim, yazi, fzf, GTK, Steam и attakshark (как ThemeSync.qml);
// открытые терминалы и nvim перекрашиваются сразу

use std::fs;
use std::path::PathBuf;
use std::thread;
use std::time::Duration;

use amane::{Color, Service};

use crate::json::Json;
use crate::look::Look;
use crate::settings;
use crate::theme::{self, Palette};

// 16 цветов терминала: [0..7] обычные, [8..15] яркие
fn ansi_table(scheme: &str) -> Option<[&'static str; 16]> {
    Some(match scheme {
        "dark" => ["#1f1f1f", "#c96a6a", "#8fa876", "#d7a65f", "#7d9bb8", "#a88bb3", "#7fb0a8", "#d4d4d4", "#4a4a4a", "#d98080", "#a3bc8a", "#e3b877", "#93afc9", "#bb9fc5", "#93c2ba", "#eeeeee"],
        "light" => ["#2a2a2a", "#b3413c", "#4d7a32", "#8f6b12", "#3a639a", "#8a4f9e", "#2f7a78", "#bdbdbd", "#6b6b6b", "#c9544e", "#5e8f40", "#a7801c", "#4b77b3", "#9f62b3", "#3b918e", "#d6d6d6"],
        "nord" => ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0", "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"],
        "gruvbox" => ["#3c3836", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984", "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"],
        "rose" => ["#26233a", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4", "#6e6a86", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4"],
        _ => return None,
    })
}

pub fn hex(c: Color) -> String {
    format!("#{:02x}{:02x}{:02x}", c.red(), c.green(), c.blue())
}

// для «под обои» — фиксированные оттенки, яркость под тёмный фон
pub fn wall_ansi(p: &Palette) -> [Color; 16] {
    let hs = [0.0, 105.0, 40.0, 215.0, 290.0, 175.0];
    let mut a = [Color::BLACK; 16];
    a[0] = p.surface_hi2;
    for (i, h) in hs.iter().enumerate() {
        a[1 + i] = theme::hsl(h / 360.0, 0.42, 0.66);
        a[9 + i] = theme::hsl(h / 360.0, 0.48, 0.74);
    }
    a[7] = p.fg;
    a[8] = p.dim;
    a[15] = p.fg_hover;
    a
}

pub struct Colors {
    pub scheme: String,
    pub p: Palette,
    pub a: [Color; 16],
    pub light: bool,
}

pub fn colors(scheme: &str, p: Palette) -> Colors {
    let a = if scheme == "wallpaper" {
        wall_ansi(&p)
    } else {
        let t = ansi_table(scheme).or_else(|| ansi_table("dark")).unwrap();
        let mut a = [Color::BLACK; 16];
        for (i, h) in t.iter().enumerate() {
            a[i] = theme::parse_hex(h).unwrap();
        }
        a
    };
    Colors { scheme: scheme.to_string(), p, a, light: scheme == "light" }
}

pub struct Fonts {
    pub mono: String,
    pub app: String,
    pub ui: String,
    pub ui_scale: f64,
    pub transparency: bool,
    pub terminal_opacity: f64,
}

impl Fonts {
    pub fn from(s: &Json) -> Fonts {
        let ui = s.get("font").str_or("");
        Fonts {
            mono: Some(s.get("monoFont").str_or("")).filter(|v| !v.is_empty()).unwrap_or_else(|| "JetBrainsMono Nerd Font".into()),
            app: s.get("appFont").str_or(""),
            ui: if ui.is_empty() { "JetBrainsMono Nerd Font".into() } else { ui },
            ui_scale: s.get("uiScale").num_or(1.0),
            transparency: s.get("transparency").bool_or(false),
            terminal_opacity: s.get("terminalOpacity").num_or(1.0),
        }
    }
}

pub fn foot_ini(c: &Colors, f: &Fonts) -> String {
    let n = |x: Color| hex(x)[1..].to_string();
    let mono = &f.mono;
    let mut l = vec![
        "# генерируется Quickshell (Настройки → Персонализация); вручную не править".to_string(),
        format!("font={mono}:size=11.5"),
        format!("font-bold={mono}:style=Bold:size=11.5"),
        format!("font-italic={mono}:style=Italic:size=11.5"),
        String::new(),
        "[colors-dark]".into(),
        format!("background={}", n(c.p.bg)),
        format!("foreground={}", n(c.p.fg)),
        format!("cursor={} {}", n(c.p.bg), n(c.p.fg)),
        format!("selection-background={}", n(c.p.surface_hi2)),
        format!("selection-foreground={}", n(c.p.fg)),
    ];
    if f.transparency && f.terminal_opacity < 1.0 {
        l.push(format!("alpha={:.2}", f.terminal_opacity));
    }
    l.push(String::new());
    for i in 0..8 {
        l.push(format!("regular{i}={}", n(c.a[i])));
    }
    l.push(String::new());
    for i in 0..8 {
        l.push(format!("bright{i}={}", n(c.a[i + 8])));
    }
    l.join("\n") + "\n"
}

pub fn nvim_palette(c: &Colors) -> String {
    let p = &c.p;
    let f = |k: &str, v: Color| format!("{k} = \"{}\"", hex(v));
    format!(
        "-- генерируется Quickshell (Настройки → Персонализация); вручную не править\nreturn {{\n  scheme = \"{}\", light = {},\n  {}, {}, {}, {}, {},\n  {}, {}, {}, {},\n  {}, {}, {}, {},\n}}\n",
        c.scheme,
        c.light,
        f("bg", p.bg),
        f("surface", p.surface),
        f("surfaceHi", p.surface_hi),
        f("surfaceHi2", p.surface_hi2),
        f("line", p.line),
        f("fg", p.fg),
        f("dim", p.dim),
        f("faint", p.faint),
        f("accent", p.accent),
        f("red", c.a[1]),
        f("green", c.a[2]),
        f("yellow", c.a[3]),
        f("blue", c.a[4]),
    )
}

pub fn zsh_theme(c: &Colors) -> String {
    let p = &c.p;
    let x = hex;
    format!(
        "# генерируется Quickshell (Настройки → Персонализация); вручную не править\nexport FZF_DEFAULT_OPTS='--height 40% --layout reverse --border none --info inline-right\n  --color bg:{},bg+:{},fg:{},fg+:{},hl:{},hl+:{}\n  --color pointer:{},marker:{},prompt:{},info:{},border:{}'\n",
        x(p.bg),
        x(p.surface_hi),
        x(p.muted),
        x(p.fg),
        x(c.a[3]),
        x(c.a[3]),
        x(p.accent),
        x(p.accent),
        x(p.dim),
        x(p.dim),
        x(p.line)
    )
}

pub fn yazi_theme(c: &Colors) -> String {
    let p = &c.p;
    let a = &c.a;
    let x = hex;
    let r = "\u{e0b0}";
    let lf = "\u{e0b2}";
    let mut s = String::from("# генерируется Quickshell (Настройки → Персонализация); вручную не править\n\n");
    let lines: Vec<String> = vec![
        "[mgr]".into(),
        format!("cwd           = {{ fg = \"{}\" }}", x(p.dim)),
        "border_symbol = \"│\"".into(),
        format!("border_style  = {{ fg = \"{}\" }}", x(p.surface_hi2)),
        format!("marker_copied   = {{ fg = \"{}\", bg = \"{}\" }}", x(a[2]), x(a[2])),
        format!("marker_cut      = {{ fg = \"{}\", bg = \"{}\" }}", x(a[1]), x(a[1])),
        format!("marker_marked   = {{ fg = \"{}\", bg = \"{}\" }}", x(a[6]), x(a[6])),
        format!("marker_selected = {{ fg = \"{}\", bg = \"{}\" }}", x(a[3]), x(a[3])),
        format!("count_copied   = {{ fg = \"{}\", bg = \"{}\" }}", x(p.bg), x(a[2])),
        format!("count_cut      = {{ fg = \"{}\", bg = \"{}\" }}", x(p.bg), x(a[1])),
        format!("count_selected = {{ fg = \"{}\", bg = \"{}\" }}", x(p.bg), x(a[3])),
        format!("find_keyword  = {{ fg = \"{}\", bold = true }}", x(a[3])),
        format!("find_position = {{ fg = \"{}\" }}", x(p.dim)),
        String::new(),
        "[indicator]".into(),
        format!("parent  = {{ fg = \"{}\", bg = \"{}\" }}", x(p.fg), x(p.surface_hi)),
        format!("current = {{ fg = \"{}\", bg = \"{}\", bold = true }}", x(p.fg_hover), x(p.surface_hi2)),
        format!("preview = {{ bg = \"{}\" }}", x(p.surface)),
        String::new(),
        "[tabs]".into(),
        format!("active   = {{ fg = \"{}\", bg = \"{}\", bold = true }}", x(p.bg), x(p.accent)),
        format!("inactive = {{ fg = \"{}\", bg = \"{}\" }}", x(p.dim), x(p.surface)),
        "sep_inner = { open = \"\", close = \"\" }".into(),
        format!("sep_outer = {{ open = \"{lf}\", close = \"{r}\" }}"),
        String::new(),
        "[mode]".into(),
        format!("normal_main = {{ fg = \"{}\", bg = \"{}\", bold = true }}", x(p.bg), x(p.accent)),
        format!("normal_alt  = {{ fg = \"{}\", bg = \"{}\" }}", x(p.fg), x(p.surface_hi2)),
        format!("select_main = {{ fg = \"{}\", bg = \"{}\", bold = true }}", x(p.bg), x(a[3])),
        format!("select_alt  = {{ fg = \"{}\", bg = \"{}\" }}", x(a[3]), x(p.surface_hi2)),
        format!("unset_main  = {{ fg = \"{}\", bg = \"{}\", bold = true }}", x(p.bg), x(a[1])),
        format!("unset_alt   = {{ fg = \"{}\", bg = \"{}\" }}", x(a[1]), x(p.surface_hi2)),
        String::new(),
        "[status]".into(),
        format!("sep_left   = {{ open = \"\", close = \"{r}\" }}"),
        format!("sep_right  = {{ open = \"{lf}\", close = \"\" }}"),
        format!("perm_sep   = {{ fg = \"{}\" }}", x(p.line)),
        format!("perm_type  = {{ fg = \"{}\" }}", x(a[4])),
        format!("perm_read  = {{ fg = \"{}\" }}", x(p.muted)),
        format!("perm_write = {{ fg = \"{}\" }}", x(p.muted)),
        format!("perm_exec  = {{ fg = \"{}\" }}", x(p.muted)),
        format!("progress_label  = {{ fg = \"{}\", bold = true }}", x(p.fg)),
        format!("progress_normal = {{ fg = \"{}\", bg = \"{}\" }}", x(p.accent), x(p.surface_hi2)),
        format!("progress_error  = {{ fg = \"{}\", bg = \"{}\" }}", x(a[1]), x(p.surface_hi2)),
        String::new(),
        "[which]".into(),
        format!("border          = {{ fg = \"{}\" }}", x(p.line)),
        "cols            = 2".into(),
        format!("mask            = {{ bg = \"{}\" }}", x(p.bg)),
        format!("cand            = {{ fg = \"{}\", bold = true }}", x(p.fg)),
        format!("rest            = {{ fg = \"{}\" }}", x(p.dim)),
        format!("desc            = {{ fg = \"{}\" }}", x(p.muted)),
        "separator       = \"  \"".into(),
        format!("separator_style = {{ fg = \"{}\" }}", x(p.line)),
        String::new(),
        "[input]".into(),
        format!("border   = {{ fg = \"{}\" }}", x(p.line)),
        format!("title    = {{ fg = \"{}\" }}", x(p.muted)),
        format!("value    = {{ fg = \"{}\" }}", x(p.fg)),
        format!("selected = {{ bg = \"{}\" }}", x(p.surface_hi2)),
        String::new(),
        "[pick]".into(),
        format!("border   = {{ fg = \"{}\" }}", x(p.line)),
        format!("active   = {{ fg = \"{}\", bold = true }}", x(p.fg_hover)),
        format!("inactive = {{ fg = \"{}\" }}", x(p.muted)),
        String::new(),
        "[confirm]".into(),
        format!("border  = {{ fg = \"{}\" }}", x(p.line)),
        format!("title   = {{ fg = \"{}\" }}", x(p.muted)),
        format!("body    = {{ fg = \"{}\" }}", x(p.fg)),
        format!("list    = {{ fg = \"{}\" }}", x(p.muted)),
        format!("btn_yes = {{ fg = \"{}\", bg = \"{}\" }}", x(p.bg), x(p.accent)),
        format!("btn_no  = {{ fg = \"{}\" }}", x(p.muted)),
        String::new(),
        "[spot]".into(),
        format!("border = {{ fg = \"{}\" }}", x(p.line)),
        format!("title  = {{ fg = \"{}\" }}", x(p.muted)),
        String::new(),
        "[tasks]".into(),
        format!("border  = {{ fg = \"{}\" }}", x(p.line)),
        format!("title   = {{ fg = \"{}\" }}", x(p.muted)),
        format!("hovered = {{ fg = \"{}\", bold = true }}", x(p.fg_hover)),
        String::new(),
        "[help]".into(),
        format!("on      = {{ fg = \"{}\" }}", x(p.fg)),
        format!("run     = {{ fg = \"{}\" }}", x(p.muted)),
        format!("hovered = {{ bg = \"{}\", bold = true }}", x(p.surface_hi2)),
        format!("footer  = {{ fg = \"{}\", bg = \"{}\" }}", x(p.bg), x(p.accent)),
        String::new(),
        "[notify]".into(),
        format!("title_info  = {{ fg = \"{}\" }}", x(p.fg)),
        format!("title_warn  = {{ fg = \"{}\" }}", x(a[3])),
        format!("title_error = {{ fg = \"{}\" }}", x(a[1])),
    ];
    s.push_str(&lines.join("\n"));
    s.push('\n');
    s
}

// GTK 3/4: именованные цвета Adwaita + CSS-переменные libadwaita
pub fn gtk_css(c: &Colors, gtk4: bool) -> String {
    let p = &c.p;
    let x = hex;
    let vars: [(&str, Color); 27] = [
        ("window_bg_color", p.bg),
        ("window_fg_color", p.fg),
        ("view_bg_color", p.surface),
        ("view_fg_color", p.fg),
        ("headerbar_bg_color", p.bg),
        ("headerbar_fg_color", p.fg),
        ("headerbar_backdrop_color", p.bg),
        ("sidebar_bg_color", p.surface),
        ("sidebar_fg_color", p.fg),
        ("card_bg_color", p.surface),
        ("card_fg_color", p.fg),
        ("popover_bg_color", p.surface),
        ("popover_fg_color", p.fg),
        ("dialog_bg_color", p.surface),
        ("dialog_fg_color", p.fg),
        ("accent_color", p.accent),
        ("accent_bg_color", p.accent),
        ("accent_fg_color", p.bg),
        ("theme_bg_color", p.bg),
        ("theme_fg_color", p.fg),
        ("theme_base_color", p.surface),
        ("theme_text_color", p.fg),
        ("theme_selected_bg_color", p.accent),
        ("theme_selected_fg_color", p.bg),
        ("borders", p.line),
        // в Quickshell объект — без повторов; здесь хвост пустой
        ("", Color::BLACK),
        ("", Color::BLACK),
    ];
    let mut css = String::from("/* генерируется Quickshell (Настройки → Персонализация); вручную не править */\n");
    for (k, v) in vars.iter().filter(|(k, _)| !k.is_empty()) {
        css += &format!("@define-color {k} {};\n", x(*v));
    }
    if gtk4 {
        css += ":root {\n";
        for (k, v) in vars.iter().filter(|(k, _)| !k.is_empty() && !k.starts_with("theme_") && *k != "borders") {
            css += &format!("  --{}: {};\n", k.replace('_', "-"), x(*v));
        }
        css += "}\n";
    }
    let (bg, fg, sf, sh, sh2, ac) = (x(p.bg), x(p.fg), x(p.surface), x(p.surface_hi), x(p.surface_hi2), x(p.accent));
    css += &format!(
        "
window, window.background, .background {{ background-color: {bg}; color: {fg}; }}
headerbar, .titlebar {{ background-color: {bg}; color: {fg}; box-shadow: none; border-bottom: 1px solid {sh2}; }}
.view, treeview, textview text, iconview, list, listview, columnview {{ background-color: {sf}; color: {fg}; }}
popover > contents, popover.menu > contents, menu, .menu, .context-menu {{ background-color: {sf}; color: {fg}; }}
entry, spinbutton, searchbar entry {{ background-color: {sh}; color: {fg}; }}
*:selected, selection {{ background-color: {ac}; color: {bg}; }}
scale highlight, progressbar progress, levelbar block.filled {{ background-color: {ac}; }}
notebook, notebook > stack, notebook > header, stack.background, scrolledwindow > viewport {{ background-color: {bg}; color: {fg}; }}
notebook > header tab:checked {{ color: {fg}; box-shadow: inset 0 -2px {ac}; }}
button, dropdown > button, combobox button, menubutton > button {{ background-color: {sh}; color: {fg}; }}
button:hover, dropdown > button:hover, menubutton > button:hover {{ background-color: {sh2}; }}
button:checked, button.suggested-action {{ background-color: {ac}; color: {bg}; }}
button.flat {{ background-color: transparent; }}
button.flat:hover {{ background-color: {sh2}; }}
separator {{ background-color: {sh2}; }}
scale trough, progressbar trough, levelbar trough {{ background-color: {sh2}; }}
tooltip, tooltip > contents {{ background-color: {sh2}; color: {fg}; }}
"
    );
    css
}

// Steam (тема Millennium): CSS-переменные
pub fn steam_css(c: &Colors, f: &Fonts) -> String {
    let p = &c.p;
    let keys: [(&str, Color); 15] = [
        ("bg", p.bg),
        ("surface", p.surface),
        ("surfaceHi", p.surface_hi),
        ("surfaceHi2", p.surface_hi2),
        ("line", p.line),
        ("fg", p.fg),
        ("fgHover", p.fg_hover),
        ("fgPressed", p.fg_pressed),
        ("muted", p.muted),
        ("dim", p.dim),
        ("faint", p.faint),
        ("urgent", p.urgent),
        ("warn", p.warn),
        ("accent", p.accent),
        ("rec", p.rec),
    ];
    let mut css = String::from("/* генерируется Quickshell (Настройки → Персонализация); вручную не править */\n:root {\n");
    for (k, v) in keys {
        let mut n = String::new();
        for ch in k.chars() {
            if ch.is_ascii_uppercase() || ch.is_ascii_digit() {
                n.push('-');
                n.push(ch.to_ascii_lowercase());
            } else {
                n.push(ch);
            }
        }
        css += &format!("  --qs-{n}: {};\n  --qs-{n}-rgb: {}, {}, {};\n", hex(v), v.red(), v.green(), v.blue());
    }
    css += &format!("  --qs-accent-fg: {};\n", hex(p.bg));
    css += &format!("  --qs-green: {};\n  --qs-blue: {};\n  --qs-red: {};\n", hex(c.a[10]), hex(c.a[12]), hex(c.a[9]));
    css += &format!("  --qs-font: \"{}\";\n", if f.app.is_empty() { &f.ui } else { &f.app });
    css += &format!("  --qs-light: {};\n}}\n", if c.light { 1 } else { 0 });
    css
}

// ближайший стандартный акцент GNOME (для приложений libadwaita)
pub fn gnome_accent(c: Color) -> &'static str {
    let (h, s, _) = theme::to_hsl(c);
    if s < 0.18 {
        return "slate";
    }
    let h = h * 360.0;
    if !(15.0..345.0).contains(&h) {
        "red"
    } else if h < 40.0 {
        "orange"
    } else if h < 65.0 {
        "yellow"
    } else if h < 160.0 {
        "green"
    } else if h < 195.0 {
        "teal"
    } else if h < 255.0 {
        "blue"
    } else if h < 295.0 {
        "purple"
    } else {
        "pink"
    }
}

// OSC: перекрасить уже открытые терминалы
pub fn osc(c: &Colors) -> String {
    let (e, b) = ("\x1b]", "\x07");
    let mut s = String::new();
    for i in 0..16 {
        s += &format!("{e}4;{i};{}{b}", hex(c.a[i]));
    }
    s += &format!("{e}10;{}{b}{e}11;{}{b}{e}12;{}{b}", hex(c.p.fg), hex(c.p.bg), hex(c.p.fg));
    s += &format!("{e}17;{}{b}{e}19;{}{b}", hex(c.p.surface_hi2), hex(c.p.fg));
    s
}

pub fn attak_theme(c: &Colors, f: &Fonts) -> String {
    let p = &c.p;
    let mut o = Json::Obj(vec![
        ("name".into(), Json::Str(p.name.into())),
        ("font".into(), Json::Str(f.ui.clone())),
        ("uiScale".into(), Json::Num(f.ui_scale)),
    ]);
    for (k, v) in [
        ("bg", p.bg),
        ("surface", p.surface),
        ("surfaceHi", p.surface_hi),
        ("surfaceHi2", p.surface_hi2),
        ("line", p.line),
        ("fg", p.fg),
        ("fgHover", p.fg_hover),
        ("fgPressed", p.fg_pressed),
        ("muted", p.muted),
        ("dim", p.dim),
        ("faint", p.faint),
        ("urgent", p.urgent),
        ("warn", p.warn),
        ("accent", p.accent),
    ] {
        o.set(k, Json::Str(hex(v)));
    }
    // как JSON.stringify(o, null, 1)
    o.pretty_with(1)
}

fn home() -> PathBuf {
    settings::home()
}

pub struct Files {
    pub foot: String,
    pub nvim: String,
    pub yazi: String,
    pub zsh: String,
    pub steam: String,
    pub attak: String,
    pub gtk3: String,
    pub gtk4: String,
}

pub fn files(c: &Colors, f: &Fonts) -> Files {
    Files {
        foot: foot_ini(c, f),
        nvim: nvim_palette(c),
        yazi: yazi_theme(c),
        zsh: zsh_theme(c),
        steam: steam_css(c, f),
        attak: attak_theme(c, f),
        gtk3: gtk_css(c, false),
        gtk4: gtk_css(c, true),
    }
}

fn write_if_changed(rel: &str, text: &str) -> bool {
    let p = home().join(rel);
    if fs::read_to_string(&p).ok().as_deref() == Some(text) {
        return false;
    }
    if let Some(d) = p.parent() {
        let _ = fs::create_dir_all(d);
    }
    fs::write(p, text).is_ok()
}

// записать всё и перекрасить открытое; false — уже так
pub fn apply(c: &Colors, f: &Fonts) -> bool {
    let fl = files(c, f);
    let mut changed = false;
    for (rel, text) in [
        (".config/foot/colors.ini", &fl.foot),
        (".config/nvim/lua/qs_palette.lua", &fl.nvim),
        (".config/yazi/theme.toml", &fl.yazi),
        (".config/zsh/qs-theme.zsh", &fl.zsh),
        (".config/quickshell/steam-theme/colors.css", &fl.steam),
        (".config/attakshark/theme.json", &fl.attak),
        (".config/gtk-3.0/gtk.css", &fl.gtk3),
        (".config/gtk-4.0/gtk.css", &fl.gtk4),
    ] {
        changed |= write_if_changed(rel, text);
    }
    if !changed {
        return false;
    }
    let q = crate::niri::sh_quote;
    let (scheme, theme_name) = if c.light { ("prefer-light", "Adwaita") } else { ("prefer-dark", "Adwaita-dark") };
    let other = if theme_name == "Adwaita" { "Adwaita-dark" } else { "Adwaita-light" };
    amane::spawn(&format!(
        "gsettings set org.gnome.desktop.interface color-scheme {scheme}; \
         gsettings set org.gnome.desktop.interface accent-color {} 2>/dev/null; \
         gsettings set org.gnome.desktop.interface gtk-theme {other} 2>/dev/null; sleep 0.3; \
         gsettings set org.gnome.desktop.interface gtk-theme {theme_name}",
        gnome_accent(c.p.accent)
    ));
    if !f.app.is_empty() {
        amane::spawn(&format!("gsettings set org.gnome.desktop.interface font-name {}", q(&format!("{} 11", f.app))));
    }
    amane::spawn(&format!("gsettings set org.gnome.desktop.interface monospace-font-name {}", q(&format!("{} 11", f.mono))));
    // открытые терминалы и nvim
    amane::spawn(&format!(
        r#"seq={}
for pid in $(pgrep -x foot); do
    for c in $(pgrep -P "$pid"); do
        t=$(readlink "/proc/$c/fd/0" 2>/dev/null)
        case "$t" in /dev/pts/*) printf '%s' "$seq" > "$t" 2>/dev/null ;; esac
    done
done
for s in "$XDG_RUNTIME_DIR"/nvim.*.0; do
    [ -S "$s" ] && timeout 3 nvim --server "$s" --remote-expr 'luaeval("require(\"qs_theme\").apply()")' >/dev/null 2>&1 &
done
wait"#,
        q(&osc(c))
    ));
    true
}

pub struct ThemeSync;

impl Service for ThemeSync {
    fn new() -> Self {
        ThemeSync
    }

    fn listen() {
        let mut last = String::new();
        loop {
            thread::sleep(Duration::from_millis(800));
            let raw = settings::load();
            let scheme = raw.get("scheme").str_or("dark");
            let look = Look::read();
            // «под обои» — ждём цвета обоев
            if scheme == "wallpaper" && look.p.name != "Wallpaper" {
                continue;
            }
            let p = look.p;
            drop(look);
            let f = Fonts::from(&raw);
            let c = colors(&scheme, p);
            let key = format!("{}{}{}{}{}{}{}{:?}", scheme, f.mono, f.app, f.ui, f.ui_scale, f.transparency, f.terminal_opacity, hex(p.bg) + &hex(p.accent) + &hex(p.fg));
            if key == last {
                continue;
            }
            last = key;
            apply(&c, &f);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixed_schemes_have_ansi() {
        let c = colors("nord", Palette::scheme("nord"));
        assert_eq!(hex(c.a[1]), "#bf616a");
        let c = colors("unknown", Palette::scheme("dark"));
        assert_eq!(hex(c.a[0]), "#1f1f1f");
    }

    #[test]
    fn foot_file_shape() {
        let c = colors("dark", Palette::scheme("dark"));
        let f = Fonts { mono: "Mono".into(), app: String::new(), ui: "UI".into(), ui_scale: 1.0, transparency: true, terminal_opacity: 0.9 };
        let s = foot_ini(&c, &f);
        assert!(s.contains("font=Mono:size=11.5\n"));
        assert!(s.contains("background=151515\n"));
        assert!(s.contains("alpha=0.90\n"));
        assert!(s.contains("regular1=c96a6a\nregular2"));
        assert!(s.ends_with("bright7=eeeeee\n"));
    }

    #[test]
    fn gnome_accents() {
        assert_eq!(gnome_accent(Color::rgb(0xd4, 0xd4, 0xd4)), "slate");
        assert_eq!(gnome_accent(Color::rgb(0x88, 0xc0, 0xd0)), "teal");
        assert_eq!(gnome_accent(Color::rgb(0xfe, 0x80, 0x19)), "orange");
    }

    #[test]
    fn steam_names() {
        let c = colors("dark", Palette::scheme("dark"));
        let f = Fonts::from(&Json::Null);
        let s = steam_css(&c, &f);
        assert!(s.contains("  --qs-surface-hi-2: #2a2a2a;\n  --qs-surface-hi-2-rgb: 42, 42, 42;\n"));
        assert!(s.contains("--qs-font: \"JetBrainsMono Nerd Font\";"));
    }

    // значения, которые выдал Quickshell (Qt 6.12) для обоев с оттенком 65°: фон, текст, выделение, тусклый
    #[test]
    fn wallpaper_colors_match_qt() {
        let h = 6500.0 / 36000.0;
        assert_eq!(hex(theme::hsl(h, 0.18, 0.87)), "#e3e4d8");
        assert_eq!(hex(theme::hsl(h, 0.16, 0.075)), "#161610");
        assert_eq!(hex(theme::hsl(h, 0.13, 0.17)), "#303126");
        assert_eq!(hex(theme::hsl(h, 0.08, 0.46)), "#7d7f6c");
        // серый #181816 — оттенок ровно 60°
        let (hue, _, _) = theme::to_hsl(Color::rgb(0x18, 0x18, 0x16));
        assert_eq!((hue * 36000.0).round(), 6000.0);
    }
}
