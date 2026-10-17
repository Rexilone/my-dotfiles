// О системе: устройство, учётная запись, оболочка, характеристики (AboutPage.qml)

use amane::{Center, Column, End, Rectangle, Row, Service, Start, Weight, children};

use super::super::Prefs;
use super::super::w::{self, Btn, Card, W, bx};
use super::Out;
use crate::cmd;
use crate::dotfiles::Dotfiles;
use crate::json::Json;
use crate::look::{Look, Tk};
use crate::niri::sh_quote;
use crate::settings::{self, Settings};
use crate::ui;

const INFO: &str = r#"
. /etc/os-release
echo "os=$PRETTY_NAME"
echo "kernel=$(uname -r)"
echo "arch=$(uname -m)"
echo "host=$(hostnamectl hostname 2>/dev/null || cat /etc/hostname)"
echo "model=$(cat /sys/devices/virtual/dmi/id/board_vendor 2>/dev/null) $(cat /sys/devices/virtual/dmi/id/board_name 2>/dev/null)"
echo "user=$USER"
echo "fullname=$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1)"
echo "admin=$(id -nG | tr ' ' '\n' | grep -qx wheel && echo yes || echo no)"
echo "since=$(stat -c %w / 2>/dev/null | cut -d' ' -f1)"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
echo "cores=$(nproc)"
echo "gpu=$(lspci 2>/dev/null | grep -m1 -E 'VGA|3D' | sed 's/.*: //; s/ (rev.*//')"
echo "vram=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1 | awk '{printf "%.0f GB", $1/1073741824}')"
echo "ram=$(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
echo "disk=$(df -h / | awk 'NR==2{print $3" of "$2" used"}')"
echo "diskp=$(df / | awk 'NR==2{print $5}' | tr -d %)"
echo "uptime=$(uptime -p | sed 's/^up //')"
echo "amane=$(amane --version 2>/dev/null | awk '{print $2}')"
echo "niri=$(niri --version 2>/dev/null | awk '{print $2}')"
echo "shell=$(basename "$SHELL")"
"#;

pub fn valid_host(s: &str) -> bool {
    !s.is_empty() && s.len() <= 63 && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
}

pub fn page(t: &Tk, w: f32) -> Out {
    let info = cmd::kv(&cmd::get("about", INFO).unwrap_or_default());
    let g = |k: &str| info.get(k).map(|s| s.trim().to_string()).unwrap_or_default();
    let version = Dotfiles::read().version.clone();
    let renaming = Prefs::flag("about:renaming");
    let mut items: Vec<W> = Vec::new();

    // ── устройство
    let monitor = Column::new(children![
        Rectangle::new().width(84.0).height(64.0).radius(8.0).border(3.0, t.p.accent),
        Rectangle::new().width(84.0).height(7.0).align_child(Center, End).child(Rectangle::new().width(30.0).height(5.0).radius(2.0).fill(t.p.accent))
    ]);
    let name: W = if renaming {
        bx(w::field(t, "about-host", 240.0, "", 0, |v| {
            if valid_host(&v) {
                rename(v);
            }
        }))
    } else {
        bx(w::raw(t, g("host"), t.fs + 8.0, t.p.fg).weight(Weight::Bold))
    };
    let host = g("host");
    let btn = Btn::new(if renaming { "Save" } else { "Rename" }).primary_if(renaming).build(t, "about-rename", move || {
        if !Prefs::flag("about:renaming") {
            w::set_field("about-host", &host);
            Prefs::set("about:renaming", "1");
        } else {
            let v = w::field_text("about-host");
            if valid_host(&v) {
                rename(v);
            }
        }
    });
    items.push(bx(Rectangle::new().width(w).height(128.0).radius(12.0).fill(t.p.surface).padding(22.0).child(
        Row::new(children![monitor, Column::new(children![Row::new(vec![name, bx(btn)]).gap(10.0).align(Center), w::raw(t, g("model"), t.fs - 1.0, t.p.dim)]).gap(4.0)])
            .gap(20.0)
            .height(84.0)
            .align(Center),
    )));

    // ── учётная запись
    items.push(bx(w::section(t, "Account", w)));
    let title = if g("fullname").is_empty() { g("user") } else { format!("{} ({})", g("fullname"), g("user")) };
    let mut desc = vec![t.t(if g("admin") == "yes" { "Administrator" } else { "Standard user" }), format!("{}: {}", t.tr("shell", "оболочка"), g("shell"))];
    if !g("since").is_empty() {
        desc.push(format!("{} {}", t.tr("system installed", "система установлена"), g("since")));
    }
    items.push(bx(Card::new(0xF0004, &title, &desc.join("   ·   ")).build(t, w)));

    // ── оболочка
    items.push(bx(w::section(t, "Shell", w)));
    let tw = w - 44.0 - 52.0 - 18.0;
    items.push(bx(Rectangle::new().width(w).height(52.0 + 36.0).radius(12.0).fill(t.p.surface).padding(amane::Padding { top: 18.0, right: 22.0, bottom: 18.0, left: 22.0 }).child(
        Row::new(children![
            Rectangle::new().width(52.0).height(52.0).radius(14.0).fill(t.p.accent).align_child(Center, Center).child(w::raw(t, "R", 26.0, t.p.bg).weight(Weight::Bold)),
            Column::new(children![
                w::line(t, &format!("Rexilone Shell  {version}"), t.fs + 3.0, t.p.fg, tw, true),
                w::line(t, &format!("{} Rexilone", t.tr("by", "автор:")), t.fs - 1.0, t.p.accent, tw, false),
                w::line(t, &format!("{} amane {} · niri {} · {}", t.tr("Built on", "На"), g("amane"), g("niri"), t.t(Look::read().p.name)), t.fs - 2.0, t.p.dim, tw, false)
            ])
            .gap(3.0)
        ])
        .gap(18.0)
        .align(Center),
    )));

    // ── характеристики
    let specs = format!(
        "Device: {} ({})\nOS: {} {}\nKernel: {}\nCPU: {} ({} threads)\nGPU: {} {}\nRAM: {}\nStorage: {}\nDesktop: niri {} + Rexilone Shell {} (amane {})",
        g("host"),
        g("model"),
        g("os"),
        g("arch"),
        g("kernel"),
        g("cpu"),
        g("cores"),
        g("gpu"),
        if g("vram").is_empty() { String::new() } else { format!("· {}", g("vram")) },
        g("ram"),
        g("disk"),
        g("niri"),
        version,
        g("amane")
    );
    let copied = Prefs::flag("about:copied");
    let copy = Btn::new(if copied { "Copied" } else { "Copy" }).icon(0xF018F).build(t, "about-copy", move || {
        amane::spawn(&format!("printf '%s' {} | wl-copy", sh_quote(&specs)));
        Prefs::set("about:copied", "1");
        std::thread::spawn(|| {
            std::thread::sleep(std::time::Duration::from_millis(1500));
            Prefs::set("about:copied", "");
        });
    });
    items.push(bx(Row::new(children![w::section(t, "Device specifications", w - 120.0), Rectangle::new().width(110.0).height(54.0).align_child(End, End).child(copy)]).align(End)));
    items.push(bx(Card::new(0xF061A, "Processor", &format!("{}  ·  {} {}", g("cpu"), g("cores"), t.tr("threads", "потоков"))).build(t, w)));
    items.push(bx(Card::new(0xF08AE, "Graphics", &format!("{}{}", g("gpu"), if g("vram").is_empty() { String::new() } else { format!("  ·  {}", g("vram")) })).build(t, w)));
    items.push(bx(Card::new(0xF035B, "Memory", &g("ram")).build(t, w)));
    let dp: f32 = g("diskp").parse().unwrap_or(0.0);
    let bar = Rectangle::new().width(180.0).height(6.0).radius(3.0).fill(t.p.surface_hi2).align_child(Start, Center).child(Rectangle::new().width(180.0 * dp / 100.0).height(6.0).radius(3.0).fill(if dp > 90.0 { t.p.urgent } else { t.p.accent }));
    items.push(bx(Card::new(0xF02CA, "Storage", &g("disk")).ctrl(bar).build(t, w)));
    items.push(bx(Card::new(0xF08C7, "Operating system", &format!("{} · {}", g("os"), g("arch"))).build(t, w)));
    items.push(bx(Card::new(0xF033B, "Kernel", &g("kernel")).build(t, w)));
    items.push(bx(Card::new(0xF051B, "Uptime", &g("uptime")).build(t, w)));

    items.push(bx(w::section(t, "For developers", w)));
    let dev = Settings::read().raw.get("developerMode").bool_or(false);
    items.push(bx(Card::new(0xF0169, "Developer mode", "Shows the Plugins page: install and write your own plugins for the shell")
        .ctrl(w::switch(t, "devmode", dev, |v| settings::save_key("developerMode", Json::Bool(v))))
        .build(t, w)));
    let _ = ui::ic::SEARCH;
    Out::new(items)
}

fn rename(v: String) {
    std::thread::spawn(move || {
        amane::output(&format!("hostnamectl set-hostname {}", sh_quote(&v)));
        Prefs::set("about:renaming", "");
        cmd::refresh("about", INFO);
        cmd::forget("sysinfo");
    });
}

#[cfg(test)]
mod tests {
    #[test]
    fn hostnames() {
        assert!(super::valid_host("my-pc2"));
        assert!(!super::valid_host("my pc"));
        assert!(!super::valid_host(""));
        assert!(!super::valid_host(&"a".repeat(64)));
    }
}
