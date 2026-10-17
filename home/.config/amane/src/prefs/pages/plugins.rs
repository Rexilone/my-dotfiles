// Плагины (видно в режиме разработчика): список, включение, инструменты (PluginsPage.qml).
// Плагины — QML-код Quickshell: в amane они пока не выполняются, но включение общее с Quickshell

use amane::{Center, Column, Rectangle, Row, Service, Weight, children};

use super::super::w::{self, Btn, Card, W, bx};
use super::Out;
use crate::cmd;
use crate::json::Json;
use crate::look::Tk;
use crate::niri::sh_quote;
use crate::settings::{self, Settings};
use crate::ui;

const FOLDER: u32 = 0xF024B;

fn dir() -> String {
    settings::home().join(".config/quickshell/plugins").to_string_lossy().to_string()
}

#[derive(Debug, PartialEq)]
pub struct Plugin {
    pub id: String,
    pub name: String,
    pub version: String,
    pub author: String,
    pub description: String,
    pub parts: Vec<&'static str>,
    pub dir: String,
    pub error: String,
}

// plugin.json → описание; id обязан совпадать с папкой
pub fn parse(folder: &str, dir: &str, text: &str) -> Plugin {
    let j = Json::parse(text);
    let g = |k: &str| j.as_ref().map(|j| j.get(k).str_or("")).unwrap_or_default();
    let id = g("id");
    let error = if j.is_none() {
        "plugin.json: invalid JSON".to_string()
    } else if id.is_empty() || g("name").is_empty() {
        "plugin.json: id and name are required".to_string()
    } else if id != folder {
        format!("plugin.json: id «{id}» must match the folder «{folder}»")
    } else {
        String::new()
    };
    let parts = [("bar", "Bar"), ("service", "Service"), ("settings", "Settings")].iter().filter(|(k, _)| !g(k).is_empty()).map(|(_, l)| *l).collect();
    Plugin {
        id: if id.is_empty() { folder.to_string() } else { id },
        name: Some(g("name")).filter(|x| !x.is_empty()).unwrap_or_else(|| folder.to_string()),
        version: g("version"),
        author: g("author"),
        description: g("description"),
        parts,
        dir: dir.to_string(),
        error,
    }
}

fn scan() -> Vec<Plugin> {
    let mut v: Vec<Plugin> = std::fs::read_dir(dir())
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| !e.file_name().to_string_lossy().starts_with('.'))
        .filter_map(|e| {
            let p = e.path();
            let text = std::fs::read_to_string(p.join("plugin.json")).ok()?;
            Some(parse(&e.file_name().to_string_lossy(), &p.to_string_lossy(), &text))
        })
        .collect();
    v.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    v
}

pub fn slug(name: &str) -> String {
    let mut s = String::new();
    for c in name.trim().to_lowercase().chars() {
        if c.is_ascii_alphanumeric() {
            s.push(c);
        } else if !s.ends_with('-') {
            s.push('-');
        }
    }
    s.trim_matches('-').to_string()
}

// создать плагин из шаблона plugins/.template
fn create(name: String) {
    let id = slug(&name);
    if id.is_empty() {
        return;
    }
    let clean: String = name.trim().chars().filter(|c| !"|\\&".contains(*c)).collect();
    let script = r#"d="$1/$2"; [ -e "$d" ] && exit 1; cp -r "$1/.template" "$d"; for f in "$d"/*; do sed -i -e "s|__ID__|$2|g" -e "s|__NAME__|$3|g" -e "s|__AUTHOR__|$4|g" "$f"; done"#;
    std::thread::spawn(move || {
        amane::output(&format!("sh -c {} sh {} {} {} {}", sh_quote(script), sh_quote(&dir()), sh_quote(&id), sh_quote(&clean), sh_quote(&std::env::var("USER").unwrap_or_default())));
        w::set_field("plug-new", "");
        crate::prefs::Prefs::set("plug-scan", &format!("{:?}", std::time::Instant::now()));
    });
}

pub fn page(t: &Tk, w: f32) -> Out {
    // список перечитывается при каждом показе: папок немного
    let list = scan();
    let on = Settings::read().raw.get("plugins").clone();
    let mut items: Vec<W> = Vec::new();
    items.push(bx(Card::new(0xF0026, "Plugins run in Quickshell", "Plugins are QML code. amane doesn't run them yet: switching here is shared with Quickshell and takes effect there").build(t, w)));

    items.push(bx(w::section(t, "Developer tools", w)));
    let name = w::field_text("plug-new");
    items.push(bx(Card::new('+' as u32, "Create a plugin", "Copies a ready template with a bar module, a service and a settings page")
        .ctrl(Row::new(children![
            w::field(t, "plug-new", 220.0, "Plugin name", 0, create),
            Btn::new("Create").primary().enabled(!name.trim().is_empty()).build(t, "plug-create", || create(w::field_text("plug-new")))
        ])
        .gap(8.0)
        .align(Center))
        .build(t, w)));
    items.push(bx(Card::new(FOLDER, "Plugins folder", "Each plugin is a folder with plugin.json. See README.md there.")
        .ctrl(Row::new(children![
            Btn::new("README").build(t, "plug-readme", || amane::spawn(&format!("setsid -f foot nvim {} >/dev/null 2>&1", sh_quote(&format!("{}/README.md", dir()))))),
            Btn::new("Open").build(t, "plug-open", || amane::spawn(&format!("xdg-open {}", sh_quote(&dir()))))
        ])
        .gap(8.0))
        .build(t, w)));
    items.push(bx(Card::new(0xF0450, "Reload", "Rescan plugins after adding one; restart the shell after changing plugin code")
        .ctrl(Btn::new("Restart shell").build(t, "plug-restart", || amane::spawn("setsid -f \"$HOME/.local/bin/rexilone-shell\" restart >/dev/null 2>&1")))
        .build(t, w)));
    items.push(bx(Card::new(0xF018D, "Shell log", "Errors from plugins show up here (qs log)").click(|| amane::spawn("setsid -f foot -T 'Quickshell log' sh -c 'qs log -f' >/dev/null 2>&1")).build(t, w)));
    let targets = cmd::get("qs-ipc", "qs ipc show 2>/dev/null").unwrap_or_default();
    let t_list: Vec<&str> = targets.lines().filter_map(|l| l.strip_prefix("target ")).collect();
    items.push(bx(Card::new(0xF0169, "IPC commands", &if t_list.is_empty() { "—".to_string() } else { t_list.join(" · ") }).build(t, w)));

    items.push(bx(w::section(t, &format!("{} ({})", t.t("Installed"), list.len()), w)));
    if list.is_empty() {
        items.push(bx(w::para(t, &t.t("No plugins yet — create one above"), t.fs - 1.0, t.p.dim, w)));
    }
    for p in &list {
        let enabled = on.get(&p.id).bool() == Some(true);
        let mut ctrl: Vec<W> = Vec::new();
        let d1 = p.dir.clone();
        ctrl.push(bx(Btn::new("Edit").build(t, &format!("pe:{}", p.id), move || amane::spawn(&format!("setsid -f foot -D {} nvim . >/dev/null 2>&1", sh_quote(&d1))))));
        let d2 = p.dir.clone();
        ctrl.push(bx(Btn::new("").icon(FOLDER).build(t, &format!("pf:{}", p.id), move || amane::spawn(&format!("xdg-open {}", sh_quote(&d2))))));
        if p.error.is_empty() {
            let id = p.id.clone();
            ctrl.push(bx(w::switch(t, &format!("pon:{}", p.id), enabled, move |v| settings::save_path(&["plugins", &id], Json::Bool(v)))));
        }
        let crow = Row::new(ctrl).gap(8.0).align(Center);
        let (cw, _) = w::wh(&crow);
        let tw = w - 36.0 - 40.0 - cw - 28.0;
        let mut tags: Vec<W> = p
            .parts
            .iter()
            .map(|x| {
                let l = w::tx(t, x, t.fs - 4.0, t.p.muted);
                let (lw, _) = w::wh(&l);
                bx(Rectangle::new().width(lw + 12.0).height(18.0).radius(5.0).fill(t.p.surface_hi2).align_child(Center, Center).child(l))
            })
            .collect();
        if !p.author.is_empty() {
            tags.push(bx(w::raw(t, format!("by {}", p.author), t.fs - 3.0, t.p.dim)));
        }
        let desc = if p.error.is_empty() { &p.description } else { &p.error };
        let col = Column::new(children![
            w::raw(t, format!("{}  {}", p.name, if p.version.is_empty() { String::new() } else { format!("v{}", p.version) }), t.fs, t.p.fg).weight(Weight::Bold),
            w::para(t, desc, t.fs - 2.0, if p.error.is_empty() { t.p.dim } else { t.p.urgent }, tw),
            Row::new(tags).gap(6.0).align(Center)
        ])
        .gap(3.0);
        let (_, ch) = w::wh(&col);
        let h = ch.max(40.0) + 28.0;
        let mut r = Rectangle::new().width(w).height(h).radius(12.0).fill(t.p.surface).padding(amane::Padding { top: 14.0, right: 18.0, bottom: 14.0, left: 18.0 });
        if !p.error.is_empty() {
            r = r.border(1.0, t.p.urgent);
        }
        items.push(bx(r.child(
            Row::new(children![
                Rectangle::new().width(40.0).height(40.0).radius(12.0).fill(if enabled { t.p.accent } else { t.p.surface_hi }).align_child(Center, Center).child(ui::icon(t, 0xF0431, t.icon + 4.0, if enabled { t.p.bg } else { t.p.fg })),
                col.width(tw),
                crow
            ])
            .gap(14.0)
            .align(Center),
        )));
    }
    Out { crumb: String::new(), subtitle: "Extend the shell with your own modules — see README.md in the plugins folder".into(), items }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plugin_json() {
        let p = parse("hello", "/p/hello", r#"{"id":"hello","name":"Hello","version":"1.0.0","bar":"Bar.qml","settings":"S.qml"}"#);
        assert!(p.error.is_empty());
        assert_eq!(p.parts, vec!["Bar", "Settings"]);
        assert!(!parse("x", "/p/x", r#"{"id":"y","name":"Y"}"#).error.is_empty());
        assert!(!parse("x", "/p/x", "{").error.is_empty());
        assert_eq!(slug("  My Cool_plugin! "), "my-cool-plugin");
    }
}
