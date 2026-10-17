// Электропитание: экран и сон, режим питания, кнопки (PowerPage.qml)

use amane::{Row, Service, children};

use super::super::w::{self, Btn, Card, W, bx};
use super::Out;
use crate::cmd;
use crate::idle::{self, Idle};
use crate::json::Json;
use crate::look::Tk;
use crate::settings::{self, Settings};

const PP: &str = "command -v powerprofilesctl >/dev/null || exit 0; echo yes; powerprofilesctl get; powerprofilesctl list | sed -n 's/^[* ] *\\([a-z-]*\\):$/\\1/p'";

fn minutes(t: &Tk) -> Vec<(String, String)> {
    [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
        .iter()
        .map(|m| {
            let label = if *m == 0 {
                t.t("Never")
            } else if *m < 60 {
                format!("{m} {}", t.tr("min", "мин"))
            } else {
                format!("{} {}", m / 60, t.tr("h", "ч"))
            };
            (m.to_string(), label)
        })
        .collect()
}

pub fn page(t: &Tk, w: f32) -> Out {
    let p = Settings::read().raw.get("power").clone();
    let mins = minutes(t);
    let cur = |k: &str| format!("{}", p.get(k).num_or(0.0) as i64);
    let set = |k: &'static str| move |v: String| settings::save_path(&["power", k], Json::Num(v.parse().unwrap_or(0.0)));
    let mut items: Vec<W> = vec![bx(w::section(t, "Screen & sleep", w))];
    items.push(bx(Card::new(0xF033E, "Lock the screen after", "With swaylock").ctrl(w::dropdown(t, "lock", &mins, &cur("lock"), 140.0, set("lock"))).build(t, w)));
    items.push(bx(Card::new(0xF0379, "Turn off the screens after", "They wake up on mouse or keyboard").ctrl(w::dropdown(t, "screenoff", &mins, &cur("screenOff"), 140.0, set("screenOff"))).build(t, w)));
    items.push(bx(Card::new(0xF0904, "Put the computer to sleep after", "").ctrl(w::dropdown(t, "suspend", &mins, &cur("suspend"), 140.0, set("suspend"))).build(t, w)));
    items.push(bx(Card::new(0xF033E, "Lock before sleep", "")
        .id("lock-before")
        .ctrl(w::switch(t, "lock-sleep", p.get("lockOnSuspend").bool_or(true), |v| settings::save_path(&["power", "lockOnSuspend"], Json::Bool(v))))
        .build(t, w)));
    let caff = Idle::read().caffeine;
    items.push(bx(Card::new(0xF0176, "Keep awake", "Pause all timers above (also: qs ipc call idle caffeine). Videos and games already keep the screen on.")
        .ctrl(w::switch(t, "caffeine", caff, |v| Idle::write().caffeine = v))
        .build(t, w)));

    items.push(bx(w::section(t, "Power mode", w)));
    let pp = cmd::get("powerprofiles", PP).unwrap_or_default();
    let lines: Vec<&str> = pp.lines().filter(|l| !l.trim().is_empty()).collect();
    if lines.first() != Some(&"yes") {
        items.push(bx(Card::new(0xF06A5, "Power profiles are not installed", "power-profiles-daemon switches between Power saver, Balanced and Performance")
            .ctrl(Btn::new("Install").primary().build(t, "pp-install", || {
                std::thread::spawn(|| {
                    amane::output("pkexec sh -c 'pacman -S --needed --noconfirm power-profiles-daemon && systemctl enable --now power-profiles-daemon'");
                    cmd::refresh("powerprofiles", PP);
                });
            }))
            .build(t, w)));
    } else {
        let current = lines.get(1).copied().unwrap_or("");
        let opts: Vec<(&str, &str)> = lines
            .iter()
            .skip(2)
            .map(|p| (*p, match *p {
                "power-saver" => "Saver",
                "balanced" => "Balanced",
                "performance" => "Performance",
                o => o,
            }))
            .collect();
        items.push(bx(Card::new(0xF06A5, "Power mode", "")
            .ctrl(w::choice(t, "pp", &opts, current, |v| {
                std::thread::spawn(move || {
                    amane::output(&format!("powerprofilesctl set {}", crate::niri::sh_quote(&v)));
                    cmd::refresh("powerprofiles", PP);
                });
            }))
            .build(t, w)));
    }
    items.push(bx(w::section(t, "Power", w)));
    items.push(bx(Row::new(children![
        Btn::new("Lock").icon(0xF033E).build(t, "pw-lock", idle::lock),
        Btn::new("Sleep").icon(0xF0904).build(t, "pw-sleep", idle::suspend),
        Btn::new("Power menu…").icon(0xF0425).build(t, "pw-menu", || {
            crate::prefs::close();
            crate::power::set_open(true);
        })
    ])
    .gap(8.0)));
    Out { crumb: String::new(), subtitle: "Screen, sleep and power mode".into(), items }
}
