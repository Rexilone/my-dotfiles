// Время и язык: часовой пояс, синхронизация, формат, первый день недели, язык (TimePage.qml)

use amane::{Column, Rectangle, Service, Start, Weight, children};

use super::super::w::{self, Card, W, bx};
use super::Out;
use crate::clock::{self, Clock, Seconds};
use crate::cmd;
use crate::json::Json;
use crate::look::Tk;
use crate::niri::sh_quote;
use crate::settings::{self, Settings};

const INFO: &str = "timedatectl show -p Timezone -p NTP; echo '@@'; localectl status | sed -n 's/.*LANG=//p'; echo '@@'; localectl list-locales";

const KNOWN: [(&str, &str); 11] = [
    ("en_US.UTF-8", "English (United States)"),
    ("en_GB.UTF-8", "English (United Kingdom)"),
    ("ru_RU.UTF-8", "Русский"),
    ("uk_UA.UTF-8", "Українська"),
    ("be_BY.UTF-8", "Беларуская"),
    ("kk_KZ.UTF-8", "Қазақ"),
    ("de_DE.UTF-8", "Deutsch"),
    ("fr_FR.UTF-8", "Français"),
    ("es_ES.UTF-8", "Español"),
    ("pl_PL.UTF-8", "Polski"),
    ("ja_JP.UTF-8", "日本語"),
];

pub fn norm(l: &str) -> String {
    l.to_lowercase().replace("utf8", "utf-8")
}

fn label_of(l: &str) -> String {
    KNOWN.iter().find(|(v, _)| v.to_lowercase() == norm(l)).map(|(_, n)| n.to_string()).unwrap_or_else(|| l.to_string())
}

pub struct Info {
    pub zone: String,
    pub ntp: bool,
    pub locale: String,
    pub locales: Vec<String>,
}

pub fn parse_info(text: &str) -> Info {
    let mut it = text.split("@@");
    let td = it.next().unwrap_or("");
    let loc = it.next().unwrap_or("");
    let list = it.next().unwrap_or("");
    Info {
        zone: td.lines().find_map(|l| l.strip_prefix("Timezone=")).unwrap_or("").to_string(),
        ntp: td.contains("NTP=yes"),
        locale: loc.trim().to_string(),
        locales: list.lines().map(str::trim).filter(|x| !x.is_empty() && *x != "C.UTF-8").map(String::from).collect(),
    }
}

// 24 ↔ 12 часов в формате часов бара
pub fn to_12h(fmt: &str, on: bool) -> String {
    if on {
        fmt.replace("HH:mm:ss", "h:mm:ss AP").replace("HH:mm", "h:mm AP")
    } else {
        fmt.replace("h:mm:ss AP", "HH:mm:ss").replace("h:mm AP", "HH:mm")
    }
}

fn run(c: String) {
    std::thread::spawn(move || {
        amane::output(&c);
        cmd::refresh("timeinfo", INFO);
    });
}

pub fn page(t: &Tk, w: f32) -> Out {
    let info = parse_info(&cmd::get("timeinfo", INFO).unwrap_or_default());
    let zones: Vec<(String, String)> = cmd::get("zones", "timedatectl list-timezones").unwrap_or_default().lines().filter(|z| !z.is_empty()).map(|z| (z.to_string(), z.replace('_', " "))).collect();
    let fmt = t.c.clock_format.clone();
    let is12 = fmt.contains("h:mm AP") || fmt.contains("h:mm:ss AP");
    let unix = Seconds::read().unix;
    let off = Clock::read().offset;
    let now = clock::civil(unix, off);
    let ru = t.c.ru();
    let mut items: Vec<W> = Vec::new();
    let big = clock::format(if is12 { "h:mm:ss AP" } else { "HH:mm:ss" }, &now, ru);
    let date = format!("{}   ·   {}", clock::format("dddd, d MMMM yyyy", &now, ru), info.zone);
    items.push(bx(Rectangle::new().width(w).height(120.0).radius(12.0).fill(t.p.surface).padding(amane::Padding { top: 0.0, right: 0.0, bottom: 0.0, left: 26.0 }).align_child(Start, amane::Center).child(
        Column::new(children![w::raw(t, big, 40.0, t.p.fg).weight(Weight::Bold), w::raw(t, date, t.fs - 1.0, t.p.dim)]).gap(2.0),
    )));
    items.push(bx(w::section(t, "Date & time", w)));
    items.push(bx(Card::new(0xF1450, "Time zone", "").ctrl(w::dropdown(t, "tz", &zones, &info.zone, 260.0, |v| run(format!("timedatectl set-timezone {}", sh_quote(&v))))).build(t, w)));
    items.push(bx(Card::new(0xF06B0, "Set time automatically", "Synchronize with internet time servers (NTP)")
        .ctrl(w::switch(t, "ntp", info.ntp, |v| run(format!("timedatectl set-ntp {v}"))))
        .build(t, w)));
    let f2 = fmt.clone();
    items.push(bx(Card::new(0xF0954, "Time format", "Used by the bar clock")
        .ctrl(w::choice(t, "12h", &[("0", "24-hour"), ("1", "12-hour")], if is12 { "1" } else { "0" }, move |v| settings::save_key("clockFormat", Json::Str(to_12h(&f2, v == "1")))))
        .build(t, w)));
    let monday = Settings::read().raw.get("weekStartsMonday").bool_or(true);
    items.push(bx(Card::new(0xF00ED, "First day of week", "In the calendar")
        .ctrl(w::choice(t, "week", &[("1", "Monday"), ("0", "Sunday")], if monday { "1" } else { "0" }, |v| settings::save_key("weekStartsMonday", Json::Bool(v == "1"))))
        .build(t, w)));
    items.push(bx(w::section(t, "Language", w)));
    items.push(bx(Card::new(0xF05CA, "Interface language", "Bar, menus, widgets and settings — the whole shell")
        .ctrl(w::choice(t, "lang", &[("en", "English"), ("ru", "Русский")], &t.c.language, |v| settings::save_key("language", Json::Str(v))))
        .build(t, w)));
    let locs: Vec<(String, String)> = info.locales.iter().map(|l| (l.clone(), label_of(l))).collect();
    items.push(bx(Card::new(0xF05CA, "System language", "Language of apps and system messages. Takes effect after you log in again.")
        .id("syslang")
        .ctrl(w::dropdown(t, "locale", &locs, &info.locale, 240.0, |v| run(format!("localectl set-locale LANG={}", sh_quote(&v)))))
        .build(t, w)));
    let mut add = vec![(String::new(), "Choose…".to_string())];
    add.extend(KNOWN.iter().filter(|(k, _)| !info.locales.iter().any(|l| norm(l) == k.to_lowercase())).map(|(k, n)| (k.to_string(), n.to_string())));
    items.push(bx(Card::new(0, "Add a language", "Generates the language on this computer (needs your password)")
        .ctrl(w::dropdown(t, "addlocale", &add, "", 240.0, |v| {
            if !v.is_empty() {
                run(format!("pkexec sh -c 'sed -i \"s/^#\\($1 UTF-8\\)/\\1/\" /etc/locale.gen && locale-gen' sh {}", sh_quote(&v)));
            }
        }))
        .build(t, w)));
    let layouts: Vec<String> = Settings::read().raw.get("input").get("layouts").arr().iter().filter_map(|v| v.str().map(String::from)).collect();
    items.push(bx(Card::new(0xF030C, "Keyboard layouts", &layouts.join(", ")).click(|| {
        crate::prefs::ipc(&["page".into(), "keyboard".into()]);
    }).build(t, w)));
    Out { crumb: String::new(), subtitle: "Time zone, clock format and system language".into(), items }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_and_formats() {
        let i = parse_info("Timezone=Asia/Novosibirsk\nNTP=yes\n@@en_US.UTF-8\n@@C.UTF-8\nen_US.UTF-8\nru_RU.UTF-8\n");
        assert_eq!(i.zone, "Asia/Novosibirsk");
        assert!(i.ntp);
        assert_eq!(i.locale, "en_US.UTF-8");
        assert_eq!(i.locales, vec!["en_US.UTF-8", "ru_RU.UTF-8"]);
        assert_eq!(to_12h("dddd HH:mm", true), "dddd h:mm AP");
        assert_eq!(to_12h("HH:mm:ss", true), "h:mm:ss AP");
        assert_eq!(to_12h("dddd h:mm AP", false), "dddd HH:mm");
        assert_eq!(norm("ru_RU.utf8"), "ru_ru.utf-8");
        assert_eq!(label_of("ru_RU.utf8"), "Русский");
    }
}
