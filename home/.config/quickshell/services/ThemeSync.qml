pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// переносит цветовую схему шелла в foot, Neovim, yazi и fzf
// открытые терминалы и nvim перекрашиваются сразу, yazi — при следующем запуске
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")

    // 16 цветов терминала: [0..7] обычные, [8..15] яркие
    readonly property var ansi: ({
        dark: ["#1f1f1f", "#c96a6a", "#8fa876", "#d7a65f", "#7d9bb8", "#a88bb3", "#7fb0a8", "#d4d4d4",
               "#4a4a4a", "#d98080", "#a3bc8a", "#e3b877", "#93afc9", "#bb9fc5", "#93c2ba", "#eeeeee"],
        light: ["#2a2a2a", "#b3413c", "#4d7a32", "#8f6b12", "#3a639a", "#8a4f9e", "#2f7a78", "#bdbdbd",
                "#6b6b6b", "#c9544e", "#5e8f40", "#a7801c", "#4b77b3", "#9f62b3", "#3b918e", "#d6d6d6"],
        nord: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
               "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"],
        gruvbox: ["#3c3836", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
                  "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"],
        rose: ["#26233a", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4",
               "#6e6a86", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4"],
    })

    function hex(c) {
        return Qt.color(c).toString().slice(0, 7);
    }

    // для «под обои» строим цвета из фиксированных оттенков, яркость под тёмный фон
    function wallAnsi(p) {
        const hue = h => Qt.hsla(h / 360, 0.42, 0.66, 1).toString();
        const hueB = h => Qt.hsla(h / 360, 0.48, 0.74, 1).toString();
        const hs = [0, 105, 40, 215, 290, 175];
        return [hex(p.surfaceHi2)].concat(hs.map(hue), [hex(p.fg)], [hex(p.dim)], hs.map(hueB), [hex(p.fgHover)]);
    }

    function colors() {
        const p = Theme.palette;
        const scheme = Settings.scheme;
        const a = scheme === "wallpaper" ? wallAnsi(p) : (ansi[scheme] ?? ansi.dark);
        return { scheme, p, a, light: scheme === "light" };
    }

    // ── генераторы файлов

    function footIni(c) {
        const n = s => hex(s).slice(1);
        const mono = Settings.monoFont || "JetBrainsMono Nerd Font";
        const L = ["# генерируется Quickshell (Настройки → Персонализация); вручную не править",
            // строки до секции относятся к [main] (файл подключён из [main])
            `font=${mono}:size=11.5`, `font-bold=${mono}:style=Bold:size=11.5`, `font-italic=${mono}:style=Italic:size=11.5`, "",
            "[colors-dark]",
            `background=${n(c.p.bg)}`, `foreground=${n(c.p.fg)}`, `cursor=${n(c.p.bg)} ${n(c.p.fg)}`,
            `selection-background=${n(c.p.surfaceHi2)}`, `selection-foreground=${n(c.p.fg)}`];
        if (Settings.transparency && Settings.terminalOpacity < 1) L.push(`alpha=${Settings.terminalOpacity.toFixed(2)}`);
        L.push("");
        for (let i = 0; i < 8; i++) L.push(`regular${i}=${n(c.a[i])}`);
        L.push("");
        for (let i = 0; i < 8; i++) L.push(`bright${i}=${n(c.a[i + 8])}`);
        return L.join("\n") + "\n";
    }

    function nvimPalette(c) {
        const p = c.p;
        const f = (k, v) => `${k} = "${hex(v)}"`;
        return `-- генерируется Quickshell (Настройки → Персонализация); вручную не править
return {
  scheme = "${c.scheme}", light = ${c.light},
  ${f("bg", p.bg)}, ${f("surface", p.surface)}, ${f("surfaceHi", p.surfaceHi)}, ${f("surfaceHi2", p.surfaceHi2)}, ${f("line", p.line)},
  ${f("fg", p.fg)}, ${f("dim", p.dim)}, ${f("faint", p.faint)}, ${f("accent", p.accent)},
  ${f("red", c.a[1])}, ${f("green", c.a[2])}, ${f("yellow", c.a[3])}, ${f("blue", c.a[4])},
}
`;
    }

    function zshTheme(c) {
        const p = c.p;
        return `# генерируется Quickshell (Настройки → Персонализация); вручную не править
export FZF_DEFAULT_OPTS='--height 40% --layout reverse --border none --info inline-right
  --color bg:${hex(p.bg)},bg+:${hex(p.surfaceHi)},fg:${hex(p.muted)},fg+:${hex(p.fg)},hl:${hex(c.a[3])},hl+:${hex(c.a[3])}
  --color pointer:${hex(p.accent)},marker:${hex(p.accent)},prompt:${hex(p.dim)},info:${hex(p.dim)},border:${hex(p.line)}'
`;
    }

    function yaziTheme(c) {
        const p = c.p, a = c.a;
        const x = hex;
        const R = "", Lf = "";
        return `# генерируется Quickshell (Настройки → Персонализация); вручную не править

[mgr]
cwd           = { fg = "${x(p.dim)}" }
border_symbol = "│"
border_style  = { fg = "${x(p.surfaceHi2)}" }
marker_copied   = { fg = "${x(a[2])}", bg = "${x(a[2])}" }
marker_cut      = { fg = "${x(a[1])}", bg = "${x(a[1])}" }
marker_marked   = { fg = "${x(a[6])}", bg = "${x(a[6])}" }
marker_selected = { fg = "${x(a[3])}", bg = "${x(a[3])}" }
count_copied   = { fg = "${x(p.bg)}", bg = "${x(a[2])}" }
count_cut      = { fg = "${x(p.bg)}", bg = "${x(a[1])}" }
count_selected = { fg = "${x(p.bg)}", bg = "${x(a[3])}" }
find_keyword  = { fg = "${x(a[3])}", bold = true }
find_position = { fg = "${x(p.dim)}" }

[indicator]
parent  = { fg = "${x(p.fg)}", bg = "${x(p.surfaceHi)}" }
current = { fg = "${x(p.fgHover)}", bg = "${x(p.surfaceHi2)}", bold = true }
preview = { bg = "${x(p.surface)}" }

[tabs]
active   = { fg = "${x(p.bg)}", bg = "${x(p.accent)}", bold = true }
inactive = { fg = "${x(p.dim)}", bg = "${x(p.surface)}" }
sep_inner = { open = "", close = "" }
sep_outer = { open = "${Lf}", close = "${R}" }

[mode]
normal_main = { fg = "${x(p.bg)}", bg = "${x(p.accent)}", bold = true }
normal_alt  = { fg = "${x(p.fg)}", bg = "${x(p.surfaceHi2)}" }
select_main = { fg = "${x(p.bg)}", bg = "${x(a[3])}", bold = true }
select_alt  = { fg = "${x(a[3])}", bg = "${x(p.surfaceHi2)}" }
unset_main  = { fg = "${x(p.bg)}", bg = "${x(a[1])}", bold = true }
unset_alt   = { fg = "${x(a[1])}", bg = "${x(p.surfaceHi2)}" }

[status]
sep_left   = { open = "", close = "${R}" }
sep_right  = { open = "${Lf}", close = "" }
perm_sep   = { fg = "${x(p.line)}" }
perm_type  = { fg = "${x(a[4])}" }
perm_read  = { fg = "${x(p.muted)}" }
perm_write = { fg = "${x(p.muted)}" }
perm_exec  = { fg = "${x(p.muted)}" }
progress_label  = { fg = "${x(p.fg)}", bold = true }
progress_normal = { fg = "${x(p.accent)}", bg = "${x(p.surfaceHi2)}" }
progress_error  = { fg = "${x(a[1])}", bg = "${x(p.surfaceHi2)}" }

[which]
border          = { fg = "${x(p.line)}" }
cols            = 2
mask            = { bg = "${x(p.bg)}" }
cand            = { fg = "${x(p.fg)}", bold = true }
rest            = { fg = "${x(p.dim)}" }
desc            = { fg = "${x(p.muted)}" }
separator       = "  "
separator_style = { fg = "${x(p.line)}" }

[input]
border   = { fg = "${x(p.line)}" }
title    = { fg = "${x(p.muted)}" }
value    = { fg = "${x(p.fg)}" }
selected = { bg = "${x(p.surfaceHi2)}" }

[pick]
border   = { fg = "${x(p.line)}" }
active   = { fg = "${x(p.fgHover)}", bold = true }
inactive = { fg = "${x(p.muted)}" }

[confirm]
border  = { fg = "${x(p.line)}" }
title   = { fg = "${x(p.muted)}" }
body    = { fg = "${x(p.fg)}" }
list    = { fg = "${x(p.muted)}" }
btn_yes = { fg = "${x(p.bg)}", bg = "${x(p.accent)}" }
btn_no  = { fg = "${x(p.muted)}" }

[spot]
border = { fg = "${x(p.line)}" }
title  = { fg = "${x(p.muted)}" }

[tasks]
border  = { fg = "${x(p.line)}" }
title   = { fg = "${x(p.muted)}" }
hovered = { fg = "${x(p.fgHover)}", bold = true }

[help]
on      = { fg = "${x(p.fg)}" }
run     = { fg = "${x(p.muted)}" }
hovered = { bg = "${x(p.surfaceHi2)}", bold = true }
footer  = { fg = "${x(p.bg)}", bg = "${x(p.accent)}" }

[notify]
title_info  = { fg = "${x(p.fg)}" }
title_warn  = { fg = "${x(a[3])}" }
title_error = { fg = "${x(a[1])}" }
`;
    }

    // GTK 3/4 (pavucontrol, файлы, диалоги): именованные цвета Adwaita + CSS-переменные libadwaita
    function gtkCss(c, gtk4) {
        const p = c.p, x = hex;
        const vars = {
            window_bg_color: p.bg, window_fg_color: p.fg,
            view_bg_color: p.surface, view_fg_color: p.fg,
            headerbar_bg_color: p.bg, headerbar_fg_color: p.fg, headerbar_backdrop_color: p.bg,
            sidebar_bg_color: p.surface, sidebar_fg_color: p.fg,
            card_bg_color: p.surface, card_fg_color: p.fg,
            popover_bg_color: p.surface, popover_fg_color: p.fg,
            dialog_bg_color: p.surface, dialog_fg_color: p.fg,
            accent_color: p.accent, accent_bg_color: p.accent, accent_fg_color: p.bg,
            // имена GTK 3
            theme_bg_color: p.bg, theme_fg_color: p.fg, theme_base_color: p.surface, theme_text_color: p.fg,
            theme_selected_bg_color: p.accent, theme_selected_fg_color: p.bg, borders: p.line,
        };
        let css = "/* генерируется Quickshell (Настройки → Персонализация); вручную не править */\n";
        for (const k in vars) css += `@define-color ${k} ${x(vars[k])};\n`;
        // CSS-переменные понимает только GTK 4 (libadwaita), GTK 3 на них ругается
        if (gtk4) {
            css += ":root {\n";
            for (const k in vars) if (!k.startsWith("theme_") && k !== "borders") css += `  --${k.replace(/_/g, "-")}: ${x(vars[k])};\n`;
            css += "}\n";
        }
        css += `
window, window.background, .background { background-color: ${x(p.bg)}; color: ${x(p.fg)}; }
headerbar, .titlebar { background-color: ${x(p.bg)}; color: ${x(p.fg)}; box-shadow: none; border-bottom: 1px solid ${x(p.surfaceHi2)}; }
.view, treeview, textview text, iconview, list, listview, columnview { background-color: ${x(p.surface)}; color: ${x(p.fg)}; }
popover > contents, popover.menu > contents, menu, .menu, .context-menu { background-color: ${x(p.surface)}; color: ${x(p.fg)}; }
entry, spinbutton, searchbar entry { background-color: ${x(p.surfaceHi)}; color: ${x(p.fg)}; }
*:selected, selection { background-color: ${x(p.accent)}; color: ${x(p.bg)}; }
scale highlight, progressbar progress, levelbar block.filled { background-color: ${x(p.accent)}; }
notebook, notebook > stack, notebook > header, stack.background, scrolledwindow > viewport { background-color: ${x(p.bg)}; color: ${x(p.fg)}; }
notebook > header tab:checked { color: ${x(p.fg)}; box-shadow: inset 0 -2px ${x(p.accent)}; }
button, dropdown > button, combobox button, menubutton > button { background-color: ${x(p.surfaceHi)}; color: ${x(p.fg)}; }
button:hover, dropdown > button:hover, menubutton > button:hover { background-color: ${x(p.surfaceHi2)}; }
button:checked, button.suggested-action { background-color: ${x(p.accent)}; color: ${x(p.bg)}; }
button.flat { background-color: transparent; }
button.flat:hover { background-color: ${x(p.surfaceHi2)}; }
separator { background-color: ${x(p.surfaceHi2)}; }
scale trough, progressbar trough, levelbar trough { background-color: ${x(p.surfaceHi2)}; }
tooltip, tooltip > contents { background-color: ${x(p.surfaceHi2)}; color: ${x(p.fg)}; }
`;
        return css;
    }

    // Steam (тема Millennium в steam-theme/): CSS-переменные, загрузчик темы подхватывает их на лету
    function steamCss(c) {
        const p = c.p;
        const rgb = v => { const q = Qt.color(v); return `${Math.round(q.r * 255)}, ${Math.round(q.g * 255)}, ${Math.round(q.b * 255)}`; };
        const keys = ["bg", "surface", "surfaceHi", "surfaceHi2", "line", "fg", "fgHover", "fgPressed",
                      "muted", "dim", "faint", "urgent", "warn", "accent", "rec"];
        let css = "/* генерируется Quickshell (Настройки → Персонализация); вручную не править */\n:root {\n";
        for (const k of keys) {
            const n = k.replace(/[A-Z0-9]/g, m => "-" + m.toLowerCase());
            css += `  --qs-${n}: ${hex(p[k])};\n  --qs-${n}-rgb: ${rgb(p[k])};\n`;
        }
        css += `  --qs-accent-fg: ${hex(p.bg)};\n`;
        // статусы друзей: «в игре» — зелёный, «в сети» — голубой из палитры терминала этой схемы
        css += `  --qs-green: ${hex(c.a[10])};\n  --qs-blue: ${hex(c.a[12])};\n  --qs-red: ${hex(c.a[9])};\n`;
        css += `  --qs-font: "${Settings.appFont || Theme.font}";\n`;
        css += `  --qs-light: ${c.light ? 1 : 0};\n}\n`;
        return css;
    }

    // ближайший стандартный акцент GNOME (для приложений libadwaita)
    function gnomeAccent(color) {
        const q = Qt.color(color);
        if (q.hslSaturation < 0.18) return "slate";
        const h = q.hslHue * 360;
        return h < 15 || h >= 345 ? "red" : h < 40 ? "orange" : h < 65 ? "yellow" : h < 160 ? "green"
             : h < 195 ? "teal" : h < 255 ? "blue" : h < 295 ? "purple" : "pink";
    }

    // OSC-последовательности: перекрасить уже открытые терминалы
    function osc(c) {
        const E = "\x1b]", B = "\x07";
        let s = "";
        for (let i = 0; i < 16; i++) s += `${E}4;${i};${hex(c.a[i])}${B}`;
        s += `${E}10;${hex(c.p.fg)}${B}${E}11;${hex(c.p.bg)}${B}${E}12;${hex(c.p.fg)}${B}`;
        s += `${E}17;${hex(c.p.surfaceHi2)}${B}${E}19;${hex(c.p.fg)}${B}`;
        return s;
    }

    // палитра для конфигуратора клавиатуры attakshark
    function attakTheme(c) {
        const p = c.p, o = { name: p.name, font: Theme.font, uiScale: Settings.uiScale };
        for (const k of ["bg", "surface", "surfaceHi", "surfaceHi2", "line", "fg", "fgHover", "fgPressed", "muted", "dim", "faint", "urgent", "warn", "accent"])
            o[k] = hex(p[k]);
        return JSON.stringify(o, null, 1) + "\n";
    }

    function sync() {
        if (Settings.scheme === "wallpaper" && !WallColors.palette) return;  // ждём цвета обоев
        const c = colors();
        const key = JSON.stringify({ v: 7, font: Theme.font, ui: Settings.uiScale, s: c.scheme, p: c.p, mono: Settings.monoFont, app: Settings.appFont,
            t: Settings.transparency, to: Settings.terminalOpacity });
        if (key === state.last) return;

        footFile.setText(footIni(c));
        nvimFile.setText(nvimPalette(c));
        yaziFile.setText(yaziTheme(c));
        zshFile.setText(zshTheme(c));
        steamFile.setText(steamCss(c));
        attakFile.setText(attakTheme(c));

        // системная тема приложений: тёмная/светлая, акцент, свои цвета в gtk.css
        gtk3File.setText(gtkCss(c, false));
        gtk4File.setText(gtkCss(c, true));
        const light = c.light;
        gtkApply.command = ["sh", "-c", `
            gsettings set org.gnome.desktop.interface color-scheme "$1"
            gsettings set org.gnome.desktop.interface accent-color "$3" 2>/dev/null
            # смена темы туда-обратно заставляет открытые GTK-приложения перечитать gtk.css
            gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-$( [ "$2" = Adwaita ] && echo dark || echo light )" 2>/dev/null
            sleep 0.3
            gsettings set org.gnome.desktop.interface gtk-theme "$2"`,
            "sh", light ? "prefer-light" : "prefer-dark", light ? "Adwaita" : "Adwaita-dark", gnomeAccent(c.p.accent)];
        gtkApply.running = true;

        // шрифт GTK-приложений
        if (Settings.appFont)
            Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "font-name", `${Settings.appFont} 11`]);
        if (Settings.monoFont)
            Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "monospace-font-name", `${Settings.monoFont} 11`]);

        live.command = ["sh", "-c", `
            seq="$1"
            for pid in $(pgrep -x foot); do
                for c in $(pgrep -P "$pid"); do
                    t=$(readlink "/proc/$c/fd/0" 2>/dev/null)
                    case "$t" in /dev/pts/*) printf '%s' "$seq" > "$t" 2>/dev/null ;; esac
                done
            done
            for s in "$XDG_RUNTIME_DIR"/nvim.*.0; do
                [ -S "$s" ] && timeout 3 nvim --server "$s" --remote-expr 'luaeval("require(\\"qs_theme\\").apply()")' >/dev/null 2>&1 &
            done
            wait`, "sh", osc(c)];
        live.running = true;

        state.last = key;
        stateFile.writeAdapter();
    }

    Timer {
        id: debounce
        interval: 800
        onTriggered: root.sync()
    }

    Connections {
        target: Theme
        function onPaletteChanged() { debounce.restart(); }
    }

    Connections {
        target: Settings
        function onMonoFontChanged() { debounce.restart(); }
        function onAppFontChanged() { debounce.restart(); }
        function onFontChanged() { debounce.restart(); }
        function onTransparencyChanged() { debounce.restart(); }
        function onTerminalOpacityChanged() { debounce.restart(); }
    }

    Component.onCompleted: debounce.restart()

    FileView { id: footFile; path: `${root.home}/.config/foot/colors.ini`; printErrors: false }
    FileView { id: nvimFile; path: `${root.home}/.config/nvim/lua/qs_palette.lua`; printErrors: false }
    FileView { id: yaziFile; path: `${root.home}/.config/yazi/theme.toml`; printErrors: false }
    FileView { id: gtk3File; path: `${root.home}/.config/gtk-3.0/gtk.css`; printErrors: false }
    FileView { id: gtk4File; path: `${root.home}/.config/gtk-4.0/gtk.css`; printErrors: false }
    Process { id: gtkApply }
    FileView { id: steamFile; path: `${root.home}/.config/quickshell/steam-theme/colors.css`; printErrors: false }
    FileView { id: attakFile; path: `${root.home}/.config/attakshark/theme.json`; printErrors: false }
    FileView { id: zshFile; path: `${root.home}/.config/zsh/qs-theme.zsh`; printErrors: false }

    Process { id: live }

    FileView {
        id: stateFile
        path: Quickshell.statePath("themesync.json")
        blockLoading: true
        printErrors: false

        JsonAdapter {
            id: state
            property string last: ""
        }
    }
}
