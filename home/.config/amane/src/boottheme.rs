// загрузка и вход в стиле шелла (как BootTheme.qml): тема для меню Limine и экрана входа.
// Шелл пишет файлы в ~/.local/state/rexilone/boot/ (цвета, обои под экран, размытые обои, аватар),
// применяет их системная служба rexilone-boot (root). Итог — /var/lib/rexilone/boot-status.json.

use std::time::Duration;

use amane::Service;

use crate::json::Json;
use crate::look::Look;
use crate::niri::sh_quote;
use crate::settings::{self, Settings};
use crate::themesync::hex;

pub const TOOL: &str = "/usr/local/lib/rexilone/rexilone-boot";

#[derive(Default)]
pub struct BootTheme {
    pub installed: bool,
    pub outdated: bool,
    pub dots: String,
    pub status: Json,
    pub busy: bool,
}

impl BootTheme {
    pub fn systems(&self) -> &[Json] {
        self.status.get("systems").arr()
    }
}

pub fn dir() -> String {
    settings::home().join(".local/state/rexilone/boot").to_string_lossy().to_string()
}

pub fn theme_json() -> String {
    let p = Look::read().p;
    let raw = Settings::read().raw.clone();
    let c = Settings::read().c.clone();
    let outs = crate::niri::Niri::read().s.outputs.clone();
    let col = |k: &str, v| (k.to_string(), Json::Str(hex(v)));
    let colors = Json::Obj(vec![
        col("bg", p.bg),
        col("panel", p.bg),
        col("surface", p.surface),
        col("surfaceHi", p.surface_hi),
        col("surfaceHi2", p.surface_hi2),
        col("fg", p.fg),
        col("muted", p.muted),
        col("dim", p.dim),
        col("accent", p.accent),
        col("urgent", p.urgent),
        col("warn", p.warn),
        col("line", p.line),
        col("faint", p.faint),
    ]);
    let timeout = raw.get("bootTimeout").num_or(5.0);
    let j = Json::Obj(vec![
        ("colors".into(), colors),
        ("lang".into(), Json::Str(c.language.clone())),
        ("barStyle".into(), Json::Str(c.bar_style.clone())),
        ("barHeight".into(), Json::Num(c.bar_height as f64)),
        ("uiScale".into(), Json::Num(c.ui_scale as f64)),
        ("transparency".into(), Json::Bool(c.transparency)),
        ("opacity".into(), Json::Num(raw.get("opacity").num_or(0.85))),
        ("primary".into(), Json::Str(c.primary(&outs))),
        ("dark".into(), Json::Bool(!p.is_light())),
        ("font".into(), Json::Str(c.font.clone())),
        ("timeout".into(), if timeout < 0.0 { Json::Str("no".into()) } else { Json::Num(timeout) }),
        ("remember".into(), Json::Bool(raw.get("bootRemember").bool_or(true))),
        ("wallpaper".into(), Json::Bool(raw.get("bootWallpaper").bool_or(true))),
        ("otherSystems".into(), Json::Bool(raw.get("bootOtherSystems").bool_or(true))),
        ("greeterBlur".into(), Json::Bool(raw.get("greeterBlur").bool_or(true))),
        ("greeterClock".into(), Json::Bool(raw.get("greeterClock").bool_or(true))),
        ("greeterUserImage".into(), Json::Bool(raw.get("greeterUserImage").bool_or(false))),
    ]);
    j.pretty_with(1)
}

// размер основного монитора в пикселях (режим, а не логический)
fn primary_px() -> (i64, i64) {
    let live = crate::niriconf::NiriConf::read().live.clone();
    let c = Settings::read().c.clone();
    let name = crate::niriconf::primary_of(&c, &live);
    let o = live.get(&name);
    let m = o.get("modes").at(o.get("current_mode").num().unwrap_or(0.0) as usize);
    let (w, h) = (m.get("width").num_or(1920.0) as i64, m.get("height").num_or(1080.0) as i64);
    let t = o.get("logical").get("transform").str_or("normal").to_lowercase();
    if t.contains("90") || t.contains("270") { (h, w) } else { (w, h) }
}

// записать тему, аватар и обои (обои — только если поменялись)
pub fn stage(last_wall: &mut String) {
    let d = dir();
    let json = theme_json();
    amane::output(&format!(
        r#"sh -c 'mkdir -p "$1" && printf "%s\n" "$2" > "$1/theme.json.tmp" && mv "$1/theme.json.tmp" "$1/theme.json"
f="$HOME/.face"; [ -f "$f" ] || f="$HOME/.face.icon"
if [ -f "$f" ] && [ "$f" -nt "$1/avatar.jpg" ] && command -v magick >/dev/null; then
    magick "$f[0]" -auto-orient -resize "256x256^" -gravity center -extent 256x256 -strip -quality 90 "jpg:$1/avatar.jpg.tmp" && mv "$1/avatar.jpg.tmp" "$1/avatar.jpg"
fi' sh {} {}"#,
        sh_quote(&d),
        sh_quote(&json)
    ));
    let wp = Look::read().wallpaper.clone();
    let (pw, ph) = primary_px();
    let key = format!("{wp}|{pw}x{ph}");
    if !wp.is_empty() && key != *last_wall {
        let out = std::process::Command::new("sh")
            .arg("-c")
            .arg(r#"mkdir -p "$1" && cd "$1" || exit 1
command -v magick >/dev/null || exit 0
magick "$2" -auto-orient -resize "$3x$4^" -gravity center -extent "$3x$4" -strip -quality 88 jpg:wallpaper.jpg.tmp &&
mv wallpaper.jpg.tmp wallpaper.jpg &&
magick wallpaper.jpg -resize 25% -blur 0x10 -resize "$3x$4!" -fill black -colorize 18% -strip -quality 85 jpg:greeter.jpg.tmp &&
mv greeter.jpg.tmp greeter.jpg"#)
            .arg("sh")
            .arg(&d)
            .arg(&wp)
            .arg(pw.to_string())
            .arg(ph.to_string())
            .status();
        if out.map(|s| s.success()).unwrap_or(false) {
            *last_wall = key;
        }
    }
}

fn read_status() -> Json {
    std::fs::read_to_string("/var/lib/rexilone/boot-status.json").ok().and_then(|t| Json::parse(&t)).unwrap_or(Json::Obj(Vec::new()))
}

// pkexec rexilone-boot <args>; сначала свежая тема
pub fn run(args: Vec<String>) {
    {
        let mut b = BootTheme::write();
        if b.busy || !b.installed {
            return;
        }
        b.busy = true;
    }
    std::thread::spawn(move || {
        let mut w = String::new();
        stage(&mut w);
        let a: Vec<String> = args.iter().map(|x| sh_quote(x)).collect();
        amane::output(&format!("pkexec {TOOL} {}", a.join(" ")));
        let s = read_status();
        let mut b = BootTheme::write();
        b.busy = false;
        b.status = s;
    });
}

pub fn apply_now() {
    run(vec!["all".into()]);
}
pub fn scan_now() {
    run(vec!["scan".into()]);
}
pub fn hide(id: &str) {
    run(vec!["hide".into(), id.into()]);
}
pub fn show(id: &str) {
    run(vec!["show".into(), id.into()]);
}
pub fn forget(id: &str) {
    run(vec!["forget".into(), id.into()]);
}
pub fn set_dm(which: &str) {
    run(vec!["dm".into(), which.into()]);
}

const CHECK: &str = r#"d=$(readlink -f "$HOME/.config/amane"); dots=${d%/home/.config/amane}
echo "dots=$dots"
[ -x "$1" ] && echo installed
[ -f "$dots/boot/rexilone-boot" ] && { ! cmp -s "$dots/boot/rexilone-boot" "$1" ||
    ! cmp -s "$dots/boot/rexilone-greeter" /usr/local/lib/rexilone/rexilone-greeter ||
    ! diff -rq "$dots/boot/greeter" /usr/local/share/rexilone/greeter >/dev/null 2>&1; } && {
    echo outdated
    sum=$(cat "$dots/boot/rexilone-boot" "$dots/boot/rexilone-greeter" "$dots"/boot/greeter/*.qml 2>/dev/null | cksum | cut -d" " -f1)
    f="$2/notified"
    [ "$(cat "$f" 2>/dev/null)" = "$sum" ] || { mkdir -p "$2"; echo "$sum" > "$f"; echo notify; }
}"#;

pub fn check() {
    let out = amane::output(&format!("sh -c {} sh {} {}", sh_quote(CHECK), TOOL, sh_quote(&dir())));
    let installed = out.lines().any(|l| l == "installed");
    let outdated = out.lines().any(|l| l == "outdated");
    let dots = out.lines().find_map(|l| l.strip_prefix("dots=")).unwrap_or("").to_string();
    {
        let mut b = BootTheme::write();
        b.installed = installed;
        b.outdated = outdated;
        b.dots = dots;
    }
    if out.lines().any(|l| l == "notify") {
        let ru = Settings::read().c.ru();
        let (t, b) = if ru {
            ("Обновите загрузку и экран входа", "Настройки → Обновления → «Обновить» (нужен пароль)")
        } else {
            ("Update the boot menu and the login screen", "Settings → Updates → Update (needs the password)")
        };
        amane::spawn(&format!("notify-send -a Rexilone -i system-software-update {} {}", sh_quote(t), sh_quote(b)));
    }
}

// поставить или обновить системную часть (спросит пароль)
pub fn setup() {
    let dots = {
        let mut b = BootTheme::write();
        if b.busy || b.dots.is_empty() {
            return;
        }
        b.busy = true;
        b.dots.clone()
    };
    std::thread::spawn(move || {
        let mut w = String::new();
        stage(&mut w);
        let user = std::env::var("USER").unwrap_or_default();
        amane::output(&format!("pkexec sh {} {} {}", sh_quote(&format!("{dots}/boot/install-boot.sh")), sh_quote(&dots), sh_quote(&user)));
        BootTheme::write().busy = false;
        check();
        BootTheme::write().status = read_status();
    });
}

impl Service for BootTheme {
    fn new() -> Self {
        BootTheme { status: read_status(), ..Default::default() }
    }

    // тема или обои поменялись — переписать файлы (раз в несколько секунд, если есть изменения)
    fn listen() {
        check();
        let mut last_json = String::new();
        let mut last_wall = String::new();
        loop {
            std::thread::sleep(Duration::from_secs(3));
            let j = theme_json();
            let wp = Look::read().wallpaper.clone();
            if j != last_json || !last_wall.starts_with(&format!("{wp}|")) {
                last_json = j;
                stage(&mut last_wall);
            }
            let s = read_status();
            if BootTheme::read().status != s {
                BootTheme::write().status = s;
            }
        }
    }
}
