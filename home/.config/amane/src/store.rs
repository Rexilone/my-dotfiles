// «Программы» (Store.qml): приложения из репозиториев Arch и AUR. Данные — data/store.py (каталог appstream,
// поиск, сведения, обновления); действия — очередь задач: pacman через pkexec (пароль спросит окно polkit),
// AUR — через paru/yay с --sudo pkexec

use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use amane::Service;

use crate::json::Json;
use crate::niri::sh_quote;
use crate::settings::{self, Settings};

#[derive(Debug, Clone, PartialEq, Default)]
pub struct App {
    pub id: String,
    pub pkg: String,
    pub repo: String,
    pub name: String,
    pub summary: String,
    pub description: String,
    pub icon: String,
    pub categories: Vec<String>,
    pub keywords: String,
    pub homepage: String,
    pub license: String,
    pub developer: String,
    pub screenshots: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Job {
    pub id: u32,
    pub kind: String, // install | remove | upgrade
    pub pkgs: Vec<String>,
    pub aur: bool,
    pub state: String, // queued | running | done | failed | cancelled
    pub line: String,
    pub log: String,
    pub step: u32,
    pub total: u32,
}

#[derive(Default)]
pub struct Store {
    pub catalog: Vec<App>,
    pub by_pkg: HashMap<String, usize>,
    pub appstream: bool,
    pub catalog_loading: bool,
    pub versions: HashMap<String, String>,
    pub apps: HashMap<String, String>,
    pub packages: Vec<Json>,
    pub foreign: Vec<Json>,
    pub updates: Vec<Json>,
    pub checking: bool,
    pub last_check: Option<Instant>,
    pub has_checkupdates: bool,
    pub helper: String,
    pub query: String,
    pub repo: Vec<Json>,
    pub aur: Vec<Json>,
    pub aur_error: bool,
    pub searching: bool,
    pub jobs: Vec<Job>,
    pub job_seq: u32,
    pub info: HashMap<String, Json>,
}

pub const CATEGORIES: [(&str, &str, u32); 10] = [
    ("Network", "Internet", 0xF059F),
    ("AudioVideo", "Music & video", 0xF0C34),
    ("Graphics", "Graphics & photo", 0xF02E9),
    ("Office", "Office", 0xF0219),
    ("Development", "Development", 0xF0169),
    ("Game", "Games", 0xF0297),
    ("Education", "Education", 0xF0474),
    ("Science", "Science", 0xF0668),
    ("System", "System", 0xF048B),
    ("Utility", "Utilities", 0xF0AD7),
];

pub const PICKS: [&str; 24] = [
    "firefox", "chromium", "telegram-desktop", "discord", "obs-studio", "vlc", "gimp", "krita", "inkscape", "blender", "libreoffice-fresh", "obsidian", "thunderbird", "steam", "lutris",
    "prismlauncher", "code", "qbittorrent", "kdenlive", "audacity", "keepassxc", "signal-desktop", "spotify-launcher", "mpv",
];

pub const AUR_PICKS: [(&str, &str); 8] = [
    ("visual-studio-code-bin", "Visual Studio Code (official build)"),
    ("google-chrome", "The popular web browser by Google"),
    ("spotify", "Music streaming service"),
    ("zen-browser-bin", "A calmer Firefox-based browser"),
    ("heroic-games-launcher-bin", "Epic, GOG and Amazon games"),
    ("onlyoffice-bin", "Office suite compatible with MS Office"),
    ("anydesk-bin", "Remote desktop"),
    ("ayugram-desktop-bin", "Telegram client with extras"),
];

fn script() -> String {
    settings::home().join(".config/amane/data/store.py").to_string_lossy().to_string()
}

fn py(args: &str) -> String {
    let lang = Settings::read().c.language.clone();
    amane::output(&format!("STORE_LANG={} python3 {} {args}", sh_quote(&lang), sh_quote(&script())))
}

fn strs(j: &Json) -> Vec<String> {
    j.arr().iter().filter_map(|v| v.str().map(String::from)).collect()
}

pub fn parse_app(j: &Json) -> App {
    App {
        id: j.get("id").str_or(""),
        pkg: j.get("pkg").str_or(""),
        repo: j.get("repo").str_or(""),
        name: j.get("name").str_or(""),
        summary: j.get("summary").str_or(""),
        description: j.get("description").str_or(""),
        icon: j.get("icon").str_or(""),
        categories: strs(j.get("categories")),
        keywords: match j.get("keywords") {
            Json::Arr(_) => strs(j.get("keywords")).join(" "),
            k => k.str_or(""),
        },
        homepage: j.get("homepage").str_or(""),
        license: j.get("license").str_or(""),
        developer: j.get("developer").str_or(""),
        screenshots: strs(j.get("screenshots")),
    }
}

impl Store {
    pub fn app(&self, pkg: &str) -> Option<&App> {
        self.by_pkg.get(pkg).and_then(|i| self.catalog.get(*i))
    }
    pub fn display_name(&self, pkg: &str) -> String {
        self.app(pkg).map(|a| a.name.clone()).filter(|n| !n.is_empty()).unwrap_or_else(|| pkg.to_string())
    }
    pub fn installed(&self, pkg: &str) -> bool {
        self.versions.contains_key(pkg)
    }
    pub fn has_update(&self, pkg: &str) -> bool {
        self.updates.iter().any(|u| u.get("name").str() == Some(pkg))
    }
    pub fn busy_with(&self, pkg: &str) -> String {
        self.jobs.iter().find(|j| (j.state == "running" || j.state == "queued") && j.pkgs.iter().any(|p| p == pkg)).map(|j| j.kind.clone()).unwrap_or_default()
    }
    pub fn current(&self) -> Option<&Job> {
        self.jobs.iter().find(|j| j.state == "running")
    }
    pub fn queued(&self) -> usize {
        self.jobs.iter().filter(|j| j.state == "queued").count()
    }
    pub fn in_category(&self, key: &str) -> Vec<App> {
        self.catalog.iter().filter(|a| a.categories.iter().any(|c| c == key)).cloned().collect()
    }
    // .desktop приложения пакета (то, что можно запустить)
    fn desktop_id(&self, pkg: &str) -> String {
        self.apps.get(pkg).cloned().unwrap_or_else(|| self.app(pkg).map(|a| a.id.trim_end_matches(".desktop").to_string()).unwrap_or_default())
    }
    pub fn can_launch(&self, pkg: &str) -> bool {
        let id = self.desktop_id(pkg);
        self.installed(pkg) && !id.is_empty() && crate::apps::AppList::read().list.iter().any(|e| e.id == id)
    }
    // иконка: из appstream, иначе из темы значков
    pub fn icon_for(&self, pkg: &str) -> Option<std::path::PathBuf> {
        if let Some(a) = self.app(pkg) {
            if let Some(s) = a.icon.strip_prefix("stock:") {
                if let Some(p) = crate::apps::icon_file(s) {
                    return Some(p);
                }
            } else if a.icon.ends_with(".jxl") {
                // JPEG XL amane не читает — PNG-копия в кэше
                if let Some(p) = jxl_png(&a.icon) {
                    return Some(p);
                }
            } else if !a.icon.is_empty() && std::path::Path::new(&a.icon).exists() {
                return Some(a.icon.clone().into());
            }
        }
        let id = self.desktop_id(pkg);
        if let Some(e) = crate::apps::AppList::read().list.iter().find(|e| e.id == id) {
            if let Some(p) = crate::apps::icon_file(&e.icon) {
                return Some(p);
            }
        }
        crate::icons::resolve(pkg)
    }
}

// значки каталога (.jxl) → PNG в ~/.cache/amane/store-icons; пока не готово — None
fn jxl_png(src: &str) -> Option<std::path::PathBuf> {
    use std::sync::Mutex;
    static BUSY: Mutex<Vec<String>> = Mutex::new(Vec::new());
    let dir = settings::home().join(".cache/amane/store-icons");
    let name = std::path::Path::new(src).file_stem()?.to_string_lossy().to_string();
    let out = dir.join(format!("{name}.png"));
    if out.exists() {
        return Some(out);
    }
    let mut b = BUSY.lock().unwrap();
    if !b.iter().any(|x| x == src) {
        b.push(src.to_string());
        let (s, o) = (src.to_string(), out.clone());
        std::thread::spawn(move || {
            // по одному: на главной десятки значков
            static ONE: Mutex<()> = Mutex::new(());
            let _g = ONE.lock().unwrap();
            let _ = std::fs::create_dir_all(o.parent().unwrap());
            let tmp = o.with_extension("part.png");
            amane::output(&format!("djxl {} {} >/dev/null 2>&1 || magick {} {}", sh_quote(&s), sh_quote(&tmp.to_string_lossy()), sh_quote(&s), sh_quote(&tmp.to_string_lossy())));
            if std::fs::rename(&tmp, &o).is_ok() {
                // перерисовать окно
                let n = Store::read().job_seq;
                Store::write().job_seq = n;
            }
        });
    }
    None
}

// локальный поиск по каталогу (названия, описания, ключевые слова, имя пакета)
pub fn search_catalog(cat: &[App], q: &str) -> Vec<App> {
    let q = q.trim().to_lowercase();
    if q.is_empty() {
        return Vec::new();
    }
    let score = |a: &App| {
        let n = a.name.to_lowercase();
        if n == q || a.pkg == q {
            0
        } else if n.starts_with(&q) || a.pkg.starts_with(&q) {
            1
        } else if n.contains(&q) || a.pkg.contains(&q) {
            2
        } else {
            3
        }
    };
    let mut v: Vec<App> = cat.iter().filter(|a| format!("{} {} {} {}", a.name, a.pkg, a.summary, a.keywords).to_lowercase().contains(&q)).cloned().collect();
    v.sort_by(|a, b| score(a).cmp(&score(b)).then_with(|| a.name.cmp(&b.name)));
    v.truncate(60);
    v
}

// ── загрузка данных

pub fn load_catalog() {
    {
        let mut s = Store::write();
        if s.catalog_loading {
            return;
        }
        s.catalog_loading = true;
    }
    std::thread::spawn(|| {
        let r = Json::parse(py("catalog").trim()).unwrap_or_default();
        let appstream = r.get("appstream").bool_or(true);
        let list: Vec<App> = std::fs::read_to_string(r.get("path").str_or("")).ok().and_then(|t| Json::parse(&t)).map(|j| j.arr().iter().map(parse_app).collect()).unwrap_or_default();
        let mut s = Store::write();
        s.by_pkg = list.iter().enumerate().map(|(i, a)| (a.pkg.clone(), i)).collect();
        s.catalog = list;
        s.appstream = appstream;
        s.catalog_loading = false;
    });
}

pub fn refresh_installed() {
    std::thread::spawn(|| {
        let Some(r) = Json::parse(py("installed").trim()) else { return };
        let mut s = Store::write();
        s.versions = r.get("versions").obj().iter().map(|(k, v)| (k.clone(), v.str_or(""))).collect();
        s.apps = r.get("apps").obj().iter().map(|(k, v)| (k.clone(), v.str_or(""))).collect();
        s.packages = r.get("packages").arr().to_vec();
        s.foreign = r.get("foreign").arr().to_vec();
    });
}

pub fn check_updates() {
    {
        let mut s = Store::write();
        if s.checking {
            return;
        }
        s.checking = true;
    }
    std::thread::spawn(|| {
        let r = Json::parse(py("updates").trim());
        let mut s = Store::write();
        if let Some(r) = r {
            s.updates = r.get("updates").arr().to_vec();
            s.has_checkupdates = r.get("checkupdates").bool_or(true);
            s.helper = r.get("helper").str_or("");
        }
        s.last_check = Some(Instant::now());
        s.checking = false;
    });
}

// поиск по pacman и AUR — с задержкой после последней буквы
pub fn search(q: &str) {
    let q = q.to_string();
    if Store::read().query == q {
        return;
    }
    Store::write().query = q.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(350));
        if Store::read().query != q {
            return;
        }
        if q.trim().chars().count() < 2 {
            let mut s = Store::write();
            s.repo.clear();
            s.aur.clear();
            return;
        }
        Store::write().searching = true;
        let r = Json::parse(py(&format!("search {}", sh_quote(q.trim()))).trim());
        let mut s = Store::write();
        if s.query != q {
            return;
        }
        if let Some(r) = r {
            let ql = q.trim().to_lowercase();
            let rank = |p: &Json| {
                let n = p.get("name").str_or("");
                if n == ql {
                    0
                } else if n.starts_with(&ql) {
                    1
                } else if n.contains(&ql) {
                    2
                } else {
                    3
                }
            };
            let mut repo = r.get("repo").arr().to_vec();
            repo.sort_by_key(|p| rank(p));
            let mut aur = r.get("aur").arr().to_vec();
            aur.sort_by(|a, b| rank(a).cmp(&rank(b)).then_with(|| b.get("popularity").num_or(0.0).partial_cmp(&a.get("popularity").num_or(0.0)).unwrap_or(std::cmp::Ordering::Equal)));
            s.repo = repo;
            s.aur = aur;
            s.aur_error = r.get("aurError").bool_or(false);
        }
        s.searching = false;
    });
}

pub fn load_info(pkg: &str) {
    if pkg.is_empty() || Store::read().info.contains_key(pkg) {
        return;
    }
    Store::write().info.insert(pkg.to_string(), Json::Null);
    let p = pkg.to_string();
    std::thread::spawn(move || {
        if let Some(j) = Json::parse(py(&format!("info {}", sh_quote(&p))).trim()) {
            Store::write().info.insert(p, j);
        }
    });
}

// ── задачи

fn enqueue(kind: &str, pkgs: Vec<String>, aur: bool) {
    {
        let mut s = Store::write();
        s.job_seq += 1;
        let id = s.job_seq;
        s.jobs.push(Job { id, kind: kind.into(), pkgs, aur, state: "queued".into(), line: String::new(), log: String::new(), step: 0, total: 0 });
    }
    next();
}

pub fn install(pkg: &str, aur: bool) {
    enqueue("install", vec![pkg.into()], aur);
}
pub fn remove(pkg: &str) {
    enqueue("remove", vec![pkg.into()], false);
}
pub fn upgrade_all() {
    let aur = !Store::read().helper.is_empty();
    enqueue("upgrade", vec![], aur);
}
pub fn clear_finished() {
    Store::write().jobs.retain(|j| j.state == "running" || j.state == "queued");
}

fn aur_cmd(helper: &str, args: &[&str]) -> Vec<String> {
    let h = if helper.is_empty() { "paru" } else { helper };
    let mut v: Vec<String> = vec![h.into()];
    v.extend(args.iter().map(|s| s.to_string()));
    v.extend(["--noconfirm", "--sudo", "pkexec"].map(String::from));
    if h == "paru" {
        v.push("--skipreview".into());
    } else {
        v.extend(["--answerdiff", "None", "--answerclean", "None", "--answeredit", "None"].map(String::from));
    }
    v
}

pub fn command_for(j: &Job, helper: &str, retry: bool) -> Vec<String> {
    let mut v: Vec<String> = match j.kind.as_str() {
        "remove" => ["pkexec", "pacman", "-Rns", "--noconfirm"].map(String::from).to_vec(),
        "upgrade" => {
            return if j.aur { aur_cmd(helper, &["-Syu"]) } else { ["pkexec", "pacman", "-Syu", "--noconfirm"].map(String::from).to_vec() };
        }
        _ if j.aur => {
            let mut a = vec!["-S", "--needed"];
            a.extend(j.pkgs.iter().map(String::as_str));
            return aur_cmd(helper, &a);
        }
        // база пакетов устарела (404 при скачивании) — повтор с обновлением системы, как положено в Arch
        _ => vec!["pkexec".into(), "pacman".into(), if retry { "-Syu".into() } else { "-S".into() }, "--needed".into(), "--noconfirm".into()],
    };
    v.extend(j.pkgs.iter().cloned());
    v
}

fn patch(id: u32, f: impl FnOnce(&mut Job)) {
    let mut s = Store::write();
    if let Some(j) = s.jobs.iter_mut().find(|j| j.id == id) {
        f(j);
    }
}

// строка вывода pacman: «( 3/12) installing foo» — шаг из всех
pub fn parse_step(line: &str) -> Option<(u32, u32, String)> {
    let r = line.strip_prefix('(')?;
    let (nums, rest) = r.split_once(')')?;
    let (a, b) = nums.split_once('/')?;
    Some((a.trim().parse().ok()?, b.trim().parse().ok()?, rest.trim().to_string()))
}

fn strip_ansi(s: &str) -> String {
    let mut out = String::new();
    let mut it = s.chars().peekable();
    while let Some(c) = it.next() {
        if c == '\x1b' {
            if it.peek() == Some(&'[') {
                it.next();
                for d in it.by_ref() {
                    if d.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
            continue;
        }
        out.push(c);
    }
    out
}

fn next() {
    let (job, helper) = {
        let mut s = Store::write();
        if s.current().is_some() {
            return;
        }
        let ru = Settings::read().c.ru();
        let Some(j) = s.jobs.iter_mut().find(|j| j.state == "queued") else { return };
        j.state = "running".into();
        j.line = if ru { "Ожидание пароля…".into() } else { "Waiting for the password…".into() };
        (j.clone(), s.helper.clone())
    };
    std::thread::spawn(move || run_job(job, helper));
}

fn run_job(j: Job, helper: String) {
    let ru = Settings::read().c.ru();
    let mut retried = false;
    let mut buf = String::new();
    loop {
        let cmd = command_for(&j, &helper, retried);
        let child = Command::new("sh")
            .arg("-c")
            .arg("exec \"$@\" 2>&1")
            .arg("sh")
            .args(&cmd)
            .env("LC_ALL", "C")
            .env("PACMAN_COLOR", "never")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .spawn();
        let Ok(mut child) = child else {
            patch(j.id, |x| {
                x.state = "failed".into();
                x.line = "spawn failed".into();
            });
            break;
        };
        let out = child.stdout.take().unwrap();
        for line in BufReader::new(out).lines() {
            let Ok(line) = line else { break };
            let line = strip_ansi(&line).trim().to_string();
            if line.is_empty() {
                continue;
            }
            buf.push_str(&line);
            buf.push('\n');
            if buf.len() > 12000 {
                let cut = buf.len() - 12000;
                let cut = (cut..buf.len()).find(|i| buf.is_char_boundary(*i)).unwrap_or(cut);
                buf.drain(..cut);
            }
            let step = parse_step(&line);
            let log = buf.clone();
            patch(j.id, move |x| {
                x.log = log;
                if let Some((a, b, rest)) = step {
                    x.step = a;
                    x.total = b;
                    x.line = rest;
                } else if !line.chars().all(|c| c == '#' || c == '-' || c.is_whitespace()) {
                    x.line = line.chars().take(160).collect();
                }
            });
        }
        let code = child.wait().ok().and_then(|s| s.code()).unwrap_or(1);
        // пакет пропал с зеркала: база устарела — один раз повторяем с -Syu
        if code != 0 && !retried && j.kind == "install" && !j.aur && (buf.contains("failed retrieving file") || buf.contains("404")) {
            retried = true;
            patch(j.id, |x| x.line = if ru { "Обновляю базу пакетов…".into() } else { "Updating the package database…".into() });
            continue;
        }
        let state = if code == 0 {
            "done"
        } else if code == 126 || code == 127 {
            "cancelled"
        } else {
            "failed"
        };
        patch(j.id, |x| {
            x.state = state.into();
            if state == "done" {
                x.line.clear();
            } else if state == "cancelled" {
                x.line = if ru { "Отменено — пароль не введён".into() } else { "Cancelled — no password".into() };
            } else if x.line.is_empty() {
                x.line = if ru { "Ошибка".into() } else { "Failed".into() };
            }
        });
        refresh_installed();
        if j.kind == "upgrade" || state == "done" {
            check_updates();
        }
        if state == "done" {
            let name = Store::read().display_name(j.pkgs.first().map(String::as_str).unwrap_or(""));
            let what = match (j.kind.as_str(), ru) {
                ("upgrade", true) => "Система обновлена".to_string(),
                ("upgrade", false) => "System updated".to_string(),
                ("install", true) => format!("{name} — установлено"),
                ("install", false) => format!("{name} — installed"),
                (_, true) => format!("{name} — удалено"),
                (_, false) => format!("{name} — removed"),
            };
            amane::spawn(&format!("notify-send -a {} -i system-software-install {}", sh_quote(if ru { "Программы" } else { "Software" }), sh_quote(&what)));
        }
        break;
    }
    next();
}

// запустить установленное приложение
pub fn launch(pkg: &str) {
    let id = Store::read().desktop_id(pkg);
    let e = crate::apps::AppList::read().list.iter().find(|e| e.id == id).cloned();
    if let Some(e) = e {
        amane::spawn(&crate::apps::launch_cmd(&e, &e.exec));
    }
}

impl Service for Store {
    fn new() -> Self {
        Store { appstream: true, has_checkupdates: true, ..Default::default() }
    }

    // помощник AUR, установленное; обновления — раз в 3 часа
    fn listen() {
        let h = amane::output("basename \"$(command -v paru || command -v yay)\" 2>/dev/null").trim().to_string();
        Store::write().helper = h;
        refresh_installed();
        loop {
            std::thread::sleep(Duration::from_secs(3 * 3600));
            check_updates();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn steps_and_commands() {
        assert_eq!(parse_step("( 3/12) installing foo"), Some((3, 12, "installing foo".into())));
        assert_eq!(parse_step("downloading..."), None);
        assert_eq!(strip_ansi("\x1b[1;32mok\x1b[0m"), "ok");
        let j = Job { id: 1, kind: "install".into(), pkgs: vec!["gimp".into()], aur: false, state: "queued".into(), line: String::new(), log: String::new(), step: 0, total: 0 };
        assert_eq!(command_for(&j, "", false).join(" "), "pkexec pacman -S --needed --noconfirm gimp");
        assert_eq!(command_for(&j, "", true).join(" "), "pkexec pacman -Syu --needed --noconfirm gimp");
        let a = Job { aur: true, pkgs: vec!["spotify".into()], ..j.clone() };
        assert_eq!(command_for(&a, "yay", false).join(" "), "yay -S --needed spotify --noconfirm --sudo pkexec --answerdiff None --answerclean None --answeredit None");
        let r = Job { kind: "remove".into(), ..j.clone() };
        assert_eq!(command_for(&r, "", false).join(" "), "pkexec pacman -Rns --noconfirm gimp");
        let u = Job { kind: "upgrade".into(), pkgs: vec![], aur: true, ..j };
        assert_eq!(command_for(&u, "paru", false).join(" "), "paru -Syu --noconfirm --sudo pkexec --skipreview");
    }

    #[test]
    fn catalog_search_ranks() {
        let a = |n: &str, p: &str| App { name: n.into(), pkg: p.into(), ..Default::default() };
        let cat = vec![a("GNU Image Manipulation Program", "gimp"), a("Gimp Helper", "gimp-help"), a("Krita", "krita")];
        let r = search_catalog(&cat, "gimp");
        assert_eq!(r[0].pkg, "gimp");
        assert_eq!(r.len(), 2);
    }
}
