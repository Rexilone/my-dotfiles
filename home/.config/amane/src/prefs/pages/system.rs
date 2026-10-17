// Система: пользователь и компьютер, быстрые переходы, оболочка (SystemPage.qml)

use amane::{Center, Column, Padding, Rectangle, Row, Service, Weight, children};

use super::super::w::{self, Btn, Card, W, bx};
use crate::cmd;
use crate::look::{Look, Tk};
use crate::notifs::NotifState;
use crate::ui;

const SYSINFO: &str = r#"
. /etc/os-release
echo "os=$PRETTY_NAME"
echo "kernel=$(uname -r)"
echo "host=$(cat /etc/hostname 2>/dev/null || uname -n)"
echo "user=$USER"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
echo "gpu=$(lspci 2>/dev/null | grep -m1 -E 'VGA|3D' | sed 's/.*: //; s/ (rev.*//')"
echo "ram=$(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
echo "disk=$(df -h / | awk 'NR==2{print $3" / "$2" used ("$5")"}')"
echo "diskp=$(df / | awk 'NR==2{print $5}' | tr -d %)"
echo "uptime=$(uptime -p | sed 's/^up //')"
echo "shell=$(basename "$SHELL")"
echo "wm=niri $(niri --version 2>/dev/null | awk '{print $2}')"
"#;

pub fn sysinfo() -> std::collections::HashMap<String, String> {
    cmd::kv(&cmd::get("sysinfo", SYSINFO).unwrap_or_default())
}

pub fn page(t: &Tk, w: f32) -> super::Out {
    let info = sysinfo();
    let g = |k: &str| info.get(k).cloned().unwrap_or_default();
    let user = g("user");

    // ── «герой»: пользователь и компьютер
    let avatar = Rectangle::new()
        .width(64.0)
        .height(64.0)
        .radius(amane::Full)
        .fill(t.p.accent)
        .align_child(Center, Center)
        .child(ui::bold(t, user.chars().next().map(|c| c.to_uppercase().collect::<String>()).unwrap_or_else(|| "?".into()), t.p.bg).size(28.0));
    let tw = w - 44.0 - 64.0 - 18.0;
    let mut lines: Vec<W> = vec![
        bx(w::line(t, &format!("{}@{}", user, g("host")), t.fs + 5.0, t.p.fg, tw, true)),
        bx(w::line(t, &format!("{}  ·  {}  ·  {}", g("os"), g("wm"), g("shell")), t.fs - 1.0, t.p.dim, tw, false)),
    ];
    if !g("uptime").is_empty() {
        lines.push(bx(w::line(t, &format!("{} {}", t.tr("up", "работает"), g("uptime")), t.fs - 2.0, t.p.faint, tw, false)));
    }
    let hero = Rectangle::new()
        .width(w)
        .height(110.0)
        .radius(12.0)
        .fill(t.p.surface)
        .padding(22.0)
        .child(Row::new(children![avatar, Column::new(lines).gap(3.0)]).gap(18.0).height(66.0).align(Center));

    // ── быстрые переходы
    let live = crate::niriconf::NiriConf::read().live.clone();
    let mut outs: Vec<&str> = live.obj().iter().map(|(n, _)| n.as_str()).collect();
    outs.sort();
    let display = if outs.is_empty() { t.t("Monitors") } else { outs.join(" · ") };
    let net = {
        let n = crate::net::Net::read();
        match n.kind {
            crate::net::Kind::None => t.t("Disconnected"),
            crate::net::Kind::Ethernet => format!("ethernet · {}", n.iface),
            crate::net::Kind::Wifi => format!("wifi · {}", n.iface),
        }
    };
    let scheme = Look::read().p.name;
    let dnd = NotifState::read().dnd;
    let tw3 = w::width_for(3, w, 8.0);
    let quick: [(usize, u32, &str, String); 6] = [
        (1, 0xF0379, "Display", display),
        (2, 0xF057E, "Sound", t.t("Devices and apps")),
        (3, 0xF0200, "Network", net),
        (7, 0xF03D8, "Personalization", t.t(scheme)),
        (10, 0xF0FB0, "Peripherals", t.t("Keyboard, mouse, tablet, gamepads")),
        (15, 0xF009A, "Notifications", t.t(if dnd { "Do not disturb" } else { "On" })),
    ];
    let tiles: Vec<W> = quick
        .into_iter()
        .map(|(p, icon, title, desc)| bx(w::tile(t, &format!("q:{p}"), tw3, icon, title, &desc, move || crate::prefs::show(p))))
        .collect();

    let mut items: Vec<W> = vec![bx(hero), bx(w::gap(2.0)), bx(w::grid(tiles, 3, 8.0)), bx(w::gap(2.0))];
    items.push(bx(Card::new(0xF02FD, "About this PC", "Device name, account and specifications").click(|| crate::prefs::show(16)).build(t, w)));

    items.push(bx(w::section(t, "Shell", w)));
    items.push(bx(Card::new(0xF0450, "Restart shell", "Reload the bar and all menus").click(|| amane::spawn("sleep 0.2; \"$HOME/.local/bin/rexilone-shell\" restart")).build(t, w)));
    items.push(bx(Card::new(0xF04E1, "Shell engine", "Quickshell or amane (Rust). Super+Alt+S switches")
        .ctrl(w::choice(t, "engine", &[("quickshell", "Quickshell"), ("amane", "amane")], "amane", |v| {
            if v == "quickshell" {
                amane::spawn("\"$HOME/.local/bin/rexilone-shell\" use quickshell");
            }
        }))
        .build(t, w)));
    items.push(bx(Card::new(0xF0B85, "Open niri config", "~/.config/niri/config.kdl").click(|| amane::spawn("setsid -f foot nvim \"$HOME/.config/niri/config.kdl\"")).build(t, w)));
    let _ = (Btn::new(""), Padding::default(), Weight::Bold);
    super::Out::new(items)
}
