// Автозапуск: строки spawn-at-startup из конфига niri + свои из Настроек (AutostartPage.qml)

use std::fs;

use amane::{Center, Row, Service, children};

use super::super::w::{self, Btn, Card, W, bx};
use super::Out;
use crate::apps::AppList;
use crate::json::Json;
use crate::look::Tk;
use crate::settings::{self, Settings};
use crate::ui::ic;

#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub line: usize,
    pub enabled: bool,
    pub command: String,
}

fn cfg_path() -> std::path::PathBuf {
    settings::home().join(".config/niri/config.kdl")
}

// аргументы KDL: "a" "b c" → a "b c"
pub fn pretty(args: &str) -> String {
    let mut parts: Vec<String> = Vec::new();
    let mut chars = args.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '"' {
            continue;
        }
        let mut s = String::new();
        while let Some(c) = chars.next() {
            match c {
                '\\' => {
                    if let Some(n) = chars.next() {
                        s.push(n)
                    }
                }
                '"' => break,
                c => s.push(c),
            }
        }
        parts.push(s);
    }
    parts.into_iter().map(|p| if p.contains(char::is_whitespace) { format!("\"{p}\"") } else { p }).collect::<Vec<_>>().join(" ")
}

pub fn parse(text: &str) -> Vec<Entry> {
    text.lines()
        .enumerate()
        .filter_map(|(i, l)| {
            let t = l.trim_start();
            let (enabled, rest) = match t.strip_prefix("/-") {
                Some(r) => (false, r),
                None => (true, t),
            };
            let rest = rest.strip_prefix("spawn-sh-at-startup").or_else(|| rest.strip_prefix("spawn-at-startup"))?;
            rest.starts_with(char::is_whitespace).then(|| Entry { line: i, enabled, command: pretty(rest) })
        })
        .collect()
}

// включить/выключить строку конфига (комментарий KDL «/-»)
pub fn toggle_line(text: &str, line: usize, on: bool) -> String {
    let mut lines: Vec<String> = text.split('\n').map(String::from).collect();
    if let Some(l) = lines.get_mut(line) {
        let indent: String = l.chars().take_while(|c| c.is_whitespace()).collect();
        let body = l.trim_start();
        *l = if on { format!("{indent}{}", body.strip_prefix("/-").unwrap_or(body)) } else if body.starts_with("/-") { l.clone() } else { format!("{indent}/-{body}") };
    }
    lines.join("\n")
}

pub fn is_shell(cmd: &str) -> bool {
    let first = cmd.split_whitespace().next().unwrap_or("");
    first == "qs" || first == "quickshell" || first.ends_with("rexilone-shell")
}

fn add(cmd: &str) {
    let cmd = cmd.trim();
    if cmd.is_empty() {
        return;
    }
    let mut a = settings::load().get("autostart").clone();
    if !matches!(a, Json::Arr(_)) {
        a = Json::Arr(Vec::new());
    }
    if let Json::Arr(v) = &mut a {
        v.push(Json::Obj(vec![("command".into(), Json::Str(cmd.into())), ("enabled".into(), Json::Bool(true))]));
    }
    settings::save_key("autostart", a);
}

fn set_managed(i: usize, key: Option<(&str, Json)>) {
    let mut a = settings::load().get("autostart").clone();
    if let Json::Arr(v) = &mut a {
        match key {
            None => {
                if i < v.len() {
                    v.remove(i);
                }
            }
            Some((k, val)) => {
                if let Some(o) = v.get_mut(i) {
                    o.set(k, val)
                }
            }
        }
    }
    settings::save_key("autostart", a);
}

pub fn page(t: &Tk, w: f32) -> Out {
    // файл конфига читаем через cmd: вид не трогает диск
    let text = crate::cmd::get("niri-config", &format!("cat {}", crate::niri::sh_quote(&cfg_path().to_string_lossy()))).unwrap_or_default();
    let entries = parse(&text);
    let mut items: Vec<W> = vec![bx(w::section(t, "From niri config", w))];
    for e in entries {
        let shell = is_shell(&e.command);
        let name = e.command.split(' ').next().unwrap_or("").to_string();
        let desc = if shell { t.t("This shell — can't be turned off here") } else { e.command.clone() };
        let mut ctrl: Vec<W> = Vec::new();
        if !shell {
            let c = e.command.clone();
            ctrl.push(bx(Btn::new("Run").build(t, &format!("run-cfg:{}", e.line), move || amane::spawn(&format!("setsid -f sh -c {} >/dev/null 2>&1", crate::niri::sh_quote(&c))))));
        }
        let line = e.line;
        ctrl.push(bx(w::switch(t, &format!("cfg:{line}"), e.enabled, move |v| {
            if shell {
                return;
            }
            let p = cfg_path();
            if let Ok(txt) = fs::read_to_string(&p) {
                let _ = fs::write(&p, toggle_line(&txt, line, v));
            }
            crate::cmd::forget("niri-config");
        })
        .opacity(if shell { 0.4 } else { 1.0 })));
        items.push(bx(Card::new(0xF0412, &name, &desc).id(&format!("cfg{line}")).ctrl(Row::new(ctrl).gap(8.0).align(Center)).build(t, w)));
    }
    items.push(bx(w::section(t, "Added here", w)));
    let managed = Settings::read().raw.get("autostart").clone();
    if managed.arr().is_empty() {
        items.push(bx(w::para(t, &t.t("Nothing yet — add an app or a command below"), t.fs - 1.0, t.p.dim, w)));
    }
    for (i, m) in managed.arr().iter().enumerate() {
        let c = m.get("command").str_or("");
        let name = c.split(' ').next().unwrap_or("").to_string();
        let c2 = c.clone();
        let ctrl = Row::new(children![
            Btn::new("Run").build(t, &format!("run-m:{i}"), move || amane::spawn(&format!("setsid -f sh -c {} >/dev/null 2>&1", crate::niri::sh_quote(&c2)))),
            Btn::new("").icon(ic::TRASH).danger().build(t, &format!("del-m:{i}"), move || set_managed(i, None)),
            w::switch(t, &format!("m:{i}"), m.get("enabled").bool_or(false), move |v| set_managed(i, Some(("enabled", Json::Bool(v)))))
        ])
        .gap(8.0)
        .align(Center);
        items.push(bx(Card::new(0xF0412, &name, &c).id(&format!("m{i}")).ctrl(ctrl).build(t, w)));
    }
    items.push(bx(w::gap(6.0)));
    let mut apps = vec![(String::new(), "Choose an app…".to_string())];
    apps.extend(AppList::read().list.iter().map(|e| (e.exec.clone(), e.name.clone())));
    items.push(bx(Card::new(0, "Add an app", "").ctrl(w::dropdown(t, "addapp", &apps, "", 260.0, |v| add(&v))).build(t, w)));
    let typed = w::field_text("autostart-cmd");
    let add_cmd = Row::new(children![
        w::field(t, "autostart-cmd", 260.0, "", 0, |v| {
            add(&v);
            w::set_field("autostart-cmd", "");
        }),
        Btn::new("Add").primary().enabled(!typed.trim().is_empty()).build(t, "autostart-add", || {
            add(&w::field_text("autostart-cmd"));
            w::set_field("autostart-cmd", "");
        })
    ])
    .gap(8.0)
    .align(Center);
    items.push(bx(Card::new(0xF018D, "Add a command", "Any shell command, e.g. telegram-desktop -startintray").ctrl(add_cmd).build(t, w)));
    items.push(bx(w::para(t, &t.t("Changes apply at the next login. Use «Run» to start something now."), t.fs - 2.0, t.p.dim, w)));
    Out { crumb: String::new(), subtitle: "Apps and commands that start when you log in".into(), items }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CFG: &str = "spawn-at-startup \"qs\"\n/-spawn-at-startup \"wl-paste\" \"--type\" \"text\"\n    spawn-sh-at-startup \"$HOME/.local/bin/rexilone-shell start\"\n// spawn-at-startup \"x\"\nspawn-at-startupX \"y\"\n";

    #[test]
    fn parses_startup_lines() {
        let e = parse(CFG);
        assert_eq!(e.len(), 3);
        assert_eq!(e[0], Entry { line: 0, enabled: true, command: "qs".into() });
        assert_eq!(e[1].command, "wl-paste --type text");
        assert!(!e[1].enabled);
        assert_eq!(e[2].command, "\"$HOME/.local/bin/rexilone-shell start\"");
        assert!(is_shell("qs"));
        assert!(is_shell(&e[2].command.replace('"', "")));
        assert!(!is_shell("wl-paste --type text"));
    }

    #[test]
    fn toggles_lines_in_place() {
        let off = toggle_line(CFG, 0, false);
        assert!(off.starts_with("/-spawn-at-startup \"qs\"\n"));
        let on = toggle_line(CFG, 1, true);
        assert!(on.contains("\nspawn-at-startup \"wl-paste\""));
        let ind = toggle_line(CFG, 2, false);
        assert!(ind.contains("\n    /-spawn-sh-at-startup"));
        assert_eq!(toggle_line(CFG, 99, true), CFG);
    }

    #[test]
    fn kdl_args() {
        assert_eq!(pretty(" \"a\" \"b c\" \"say \\\"hi\\\"\""), "a \"b c\" \"say \"hi\"\"");
    }
}
