// приложения из .desktop: свой разбор — нужны id (частота запусков общая с Quickshell),
// ключевые слова, «в терминале» и действия («Новое окно» и т. п.)

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

use amane::Service;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Action {
    pub name: String,
    pub exec: String,
    pub icon: String,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub generic: String,
    pub comment: String,
    pub keywords: Vec<String>,
    pub exec: String,
    pub icon: String,
    pub terminal: bool,
    pub path: String,
    pub actions: Vec<Action>,
}

// Name[ru] при русском интерфейсе, иначе Name
fn localized<'a>(group: &'a [(String, String)], key: &str, lang: &str) -> Option<&'a str> {
    let loc = format!("{key}[{lang}]");
    group
        .iter()
        .find(|(k, _)| *k == loc)
        .or_else(|| group.iter().find(|(k, _)| k == key))
        .map(|(_, v)| v.as_str())
}

pub fn parse(id: &str, text: &str, lang: &str) -> Option<Entry> {
    let mut groups: Vec<(String, Vec<(String, String)>)> = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            groups.push((line[1..line.len() - 1].to_string(), Vec::new()));
            continue;
        }
        if let (Some((k, v)), Some(g)) = (line.split_once('='), groups.last_mut()) {
            g.1.push((k.trim().to_string(), v.trim().to_string()));
        }
    }
    let main = &groups.iter().find(|(n, _)| n == "Desktop Entry")?.1;
    let get = |k: &str| main.iter().find(|(key, _)| key == k).map(|(_, v)| v.as_str());
    if get("Type") != Some("Application") || get("NoDisplay") == Some("true") || get("Hidden") == Some("true") {
        return None;
    }
    let exec = get("Exec")?;
    let name = localized(main, "Name", lang)?.to_string();
    let mut actions = Vec::new();
    for a in get("Actions").unwrap_or("").split(';').filter(|s| !s.is_empty()) {
        if let Some((_, g)) = groups.iter().find(|(n, _)| *n == format!("Desktop Action {a}")) {
            let ga = |k: &str| g.iter().find(|(key, _)| key == k).map(|(_, v)| v.clone());
            if let (Some(n), Some(e)) = (localized(g, "Name", lang), ga("Exec")) {
                actions.push(Action { name: n.to_string(), exec: clean_exec(&e), icon: ga("Icon").unwrap_or_default() });
            }
        }
    }
    Some(Entry {
        id: id.to_string(),
        name,
        generic: localized(main, "GenericName", lang).unwrap_or("").to_string(),
        comment: localized(main, "Comment", lang).unwrap_or("").to_string(),
        keywords: localized(main, "Keywords", lang)
            .unwrap_or("")
            .split(';')
            .filter(|s| !s.is_empty())
            .map(String::from)
            .collect(),
        exec: clean_exec(exec),
        icon: get("Icon").unwrap_or("").to_string(),
        terminal: get("Terminal") == Some("true"),
        path: get("Path").unwrap_or("").to_string(),
        actions,
    })
}

// убрать коды полей (%f %U …), «%%» → «%»
pub fn clean_exec(exec: &str) -> String {
    let mut out = String::new();
    let mut chars = exec.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '%' {
            match chars.next() {
                Some('%') => out.push('%'),
                Some(_) | None => {}
            }
        } else {
            out.push(c);
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

// id по спецификации: путь от applications/ с «/» → «-», без .desktop
pub fn desktop_id(root: &Path, file: &Path) -> Option<String> {
    let rel = file.strip_prefix(root).ok()?.to_string_lossy().to_string();
    let rel = rel.strip_suffix(".desktop")?;
    Some(rel.replace('/', "-"))
}

pub fn data_dirs() -> Vec<PathBuf> {
    let home = crate::settings::home();
    let mut dirs = vec![std::env::var_os("XDG_DATA_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".local/share"))];
    let sys = std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".into());
    dirs.extend(sys.split(':').filter(|s| !s.is_empty()).map(PathBuf::from));
    dirs
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        if p.is_dir() {
            walk(&p, out);
        } else if p.extension().is_some_and(|x| x == "desktop") {
            out.push(p);
        }
    }
}

pub fn scan(lang: &str) -> Vec<Entry> {
    let mut seen = HashSet::new();
    let mut list = Vec::new();
    for d in data_dirs() {
        let root = d.join("applications");
        let mut files = Vec::new();
        walk(&root, &mut files);
        files.sort();
        for f in files {
            let Some(id) = desktop_id(&root, &f) else { continue };
            // файл из более раннего каталога перекрывает позднее (и скрывает, если NoDisplay)
            if !seen.insert(id.clone()) {
                continue;
            }
            if let Some(e) = fs::read_to_string(&f).ok().and_then(|t| parse(&id, &t, lang)) {
                list.push(e);
            }
        }
    }
    list.sort_by_key(|e| e.name.to_lowercase());
    list
}

pub fn launch_cmd(e: &Entry, exec: &str) -> String {
    let cmd = if e.terminal { format!("foot {exec}") } else { exec.to_string() };
    let dir = if e.path.is_empty() { crate::settings::home().to_string_lossy().to_string() } else { e.path.clone() };
    format!("cd {} && setsid -f {cmd} >/dev/null 2>&1", crate::niri::sh_quote(&dir))
}

pub struct AppList {
    pub list: Vec<Entry>,
}

impl Service for AppList {
    fn new() -> Self {
        AppList { list: Vec::new() }
    }

    fn listen() {
        loop {
            let lang = crate::settings::Settings::read().c.language.clone();
            let list = scan(&lang);
            if AppList::read().list != list {
                AppList::write().list = list;
            }
            // программы, поставленные при работающем шелле, появляются сами
            thread::sleep(Duration::from_secs(20));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIREFOX: &str = "[Desktop Entry]\nType=Application\nName=Firefox\nName[ru]=Фаерфокс\nGenericName=Web Browser\nComment=Browse\nKeywords=web;internet;\nExec=/usr/lib/firefox/firefox %u\nIcon=firefox\nActions=new-window;private;\n\n[Desktop Action new-window]\nName=New Window\nName[ru]=Новое окно\nExec=/usr/lib/firefox/firefox --new-window %u\n\n[Desktop Action private]\nName=Private\nExec=firefox --private-window\n";

    #[test]
    fn parses_entry_with_actions() {
        let e = parse("firefox", FIREFOX, "en").unwrap();
        assert_eq!(e.name, "Firefox");
        assert_eq!(e.generic, "Web Browser");
        assert_eq!(e.keywords, vec!["web", "internet"]);
        assert_eq!(e.exec, "/usr/lib/firefox/firefox");
        assert_eq!(e.actions.len(), 2);
        assert_eq!(e.actions[0].exec, "/usr/lib/firefox/firefox --new-window");
        let ru = parse("firefox", FIREFOX, "ru").unwrap();
        assert_eq!(ru.name, "Фаерфокс");
        assert_eq!(ru.actions[0].name, "Новое окно");
        assert_eq!(ru.actions[1].name, "Private");
    }

    #[test]
    fn skips_hidden_and_non_apps() {
        assert!(parse("x", "[Desktop Entry]\nType=Application\nName=X\nExec=x\nNoDisplay=true\n", "en").is_none());
        assert!(parse("x", "[Desktop Entry]\nType=Link\nName=X\nURL=y\n", "en").is_none());
        assert!(parse("x", "[Desktop Entry]\nType=Application\nName=X\n", "en").is_none());
        assert!(parse("x", "garbage", "en").is_none());
    }

    #[test]
    fn exec_codes() {
        assert_eq!(clean_exec("foo %F --bar=%u 100%%"), "foo --bar= 100%");
        assert_eq!(clean_exec("  a   b  "), "a b");
    }

    #[test]
    fn ids_from_paths() {
        let r = Path::new("/usr/share/applications");
        assert_eq!(desktop_id(r, Path::new("/usr/share/applications/kde/org.kde.krita.desktop")), Some("kde-org.kde.krita".into()));
        assert_eq!(desktop_id(r, Path::new("/usr/share/applications/foot.desktop")), Some("foot".into()));
        assert_eq!(desktop_id(r, Path::new("/elsewhere/foot.desktop")), None);
    }

    #[test]
    fn terminal_apps_open_in_foot() {
        let e = Entry { terminal: true, path: "/tmp".into(), ..Default::default() };
        assert_eq!(launch_cmd(&e, "htop"), "cd '/tmp' && setsid -f foot htop >/dev/null 2>&1");
    }
}
