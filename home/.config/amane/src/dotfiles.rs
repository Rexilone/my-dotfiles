// обновление окружения из git (Настройки → Обновления), как Dotfiles.qml:
// git pull --ff-only → install.sh --link-only → перезапуск шелла. С локальными изменениями не обновляет.
// И обновления pacman (как Updates.qml): checkupdates раз в 30 минут, если модуль бара включён.

use std::time::{Duration, Instant};

use amane::Service;

use crate::json::Json;
use crate::niri::sh_quote;
use crate::settings::{self, Settings};

pub const DEFAULT_REPO: &str = "https://github.com/Rexilone/my-dotfiles";

#[derive(Debug, Clone, PartialEq)]
pub struct Commit {
    pub hash: String,
    pub author: String,
    pub when: String,
    pub subject: String,
}

#[derive(Default)]
pub struct Dotfiles {
    pub dir: String,
    pub is_repo: bool,
    pub version: String,
    pub commit: String,
    pub commit_date: String,
    pub commit_subject: String,
    pub behind: i64,
    pub incoming: Vec<Commit>,
    pub changed_packages: Vec<String>,
    pub missing_packages: Vec<String>,
    pub dirty: i64,
    pub checking: bool,
    pub updating: bool,
    pub error: String,
    pub last_check: Option<Instant>,
    pub log: String,
}

const CHECK: &str = r#"
cfg=$(readlink -f "$HOME/.config/amane")
dir=$(git -C "$cfg" rev-parse --show-toplevel 2>/dev/null) || { echo "@norepo"; exit 0; }
echo "@dir $dir"
cd "$dir"
[ -f VERSION ] && echo "@version $(head -1 VERSION)"
if command -v pacman >/dev/null && [ -f packages/arch.txt ]; then
    pacman -T $(grep -vE '^[[:space:]]*(#|$)' packages/arch.txt) 2>/dev/null | sed 's/^/@missing /'
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "$1"
echo "@dirty $(git status --porcelain | wc -l)"
if git rev-parse -q --verify HEAD >/dev/null; then
    git log -1 --format='@commit %h%x09%cr%x09%s'
fi
if ! git fetch --quiet origin "$2" 2>/tmp/qs-dots-fetch.$$; then
    echo "@error $(tail -1 /tmp/qs-dots-fetch.$$)"; rm -f /tmp/qs-dots-fetch.$$; exit 0
fi
rm -f /tmp/qs-dots-fetch.$$
if git rev-parse -q --verify HEAD >/dev/null; then
    echo "@behind $(git rev-list --count HEAD..FETCH_HEAD)"
    git log --format='@in %h%x09%an%x09%cr%x09%s' HEAD..FETCH_HEAD | head -50
    git diff --name-only HEAD FETCH_HEAD -- packages/ | sed 's/^/@pkg /'
else
    echo "@behind $(git rev-list --count FETCH_HEAD)"
    git log --format='@in %h%x09%an%x09%cr%x09%s' FETCH_HEAD | head -50
fi
"#;

// разбор вывода проверки в состояние
pub fn apply_check(d: &mut Dotfiles, text: &str) {
    let (mut inc, mut pkgs, mut missing) = (Vec::new(), Vec::new(), Vec::new());
    let (mut behind, mut is_repo) = (0, true);
    for l in text.lines() {
        let (tag, v) = l.split_once(' ').unwrap_or((l, ""));
        match tag {
            "@norepo" => is_repo = false,
            "@dir" => d.dir = v.to_string(),
            "@version" => {
                if !v.trim().is_empty() {
                    d.version = v.trim().to_string()
                }
            }
            "@dirty" => d.dirty = v.trim().parse().unwrap_or(0),
            "@commit" => {
                let p: Vec<&str> = v.splitn(3, '\t').collect();
                d.commit = p.first().unwrap_or(&"").to_string();
                d.commit_date = p.get(1).unwrap_or(&"").to_string();
                d.commit_subject = p.get(2).unwrap_or(&"").to_string();
            }
            "@error" => d.error = v.to_string(),
            "@behind" => behind = v.trim().parse().unwrap_or(0),
            "@in" => {
                let p: Vec<&str> = v.splitn(4, '\t').collect();
                inc.push(Commit {
                    hash: p.first().unwrap_or(&"").to_string(),
                    author: p.get(1).unwrap_or(&"").to_string(),
                    when: p.get(2).unwrap_or(&"").to_string(),
                    subject: p.get(3).unwrap_or(&"").to_string(),
                });
            }
            "@pkg" => pkgs.push(v.to_string()),
            "@missing" if !v.trim().is_empty() => missing.push(v.trim().to_string()),
            _ => {}
        }
    }
    d.is_repo = is_repo;
    d.behind = behind;
    d.incoming = inc;
    d.changed_packages = pkgs;
    d.missing_packages = missing;
}

fn repo_branch() -> (String, String) {
    let raw = Settings::read().raw.clone();
    let repo = Some(raw.get("updateRepo").str_or("")).filter(|r| !r.is_empty()).unwrap_or_else(|| DEFAULT_REPO.into());
    let branch = Some(raw.get("updateBranch").str_or("")).filter(|r| !r.is_empty()).unwrap_or_else(|| "main".into());
    (repo, branch)
}

pub fn check() {
    {
        let mut d = Dotfiles::write();
        if d.checking || d.updating {
            return;
        }
        d.checking = true;
        d.error.clear();
    }
    std::thread::spawn(|| {
        let (repo, branch) = repo_branch();
        let out = amane::output(&format!("GIT_TERMINAL_PROMPT=0 LC_ALL=C sh -c {} sh {} {}", sh_quote(CHECK), sh_quote(&repo), sh_quote(&branch)));
        {
            let mut d = Dotfiles::write();
            apply_check(&mut d, &out);
            d.last_check = Some(Instant::now());
            d.checking = false;
        }
        notify_if_new();
    });
}

pub fn update() {
    let (dir, ok) = {
        let d = Dotfiles::read();
        (d.dir.clone(), !d.updating && d.is_repo && d.dirty == 0)
    };
    if !ok {
        return;
    }
    {
        let mut d = Dotfiles::write();
        d.updating = true;
        d.error.clear();
        d.log.clear();
    }
    std::thread::spawn(move || {
        let (_, branch) = repo_branch();
        let script = r#"cd "$1" || exit 1
git pull --ff-only origin "$2" 2>&1 || exit 2
./install.sh --link-only 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -20"#;
        let out = std::process::Command::new("sh")
            .arg("-c")
            .arg(script)
            .arg("sh")
            .arg(&dir)
            .arg(&branch)
            .env("GIT_TERMINAL_PROMPT", "0")
            .env("LC_ALL", "C")
            .env("REXILONE_UPDATER", "1")
            .output();
        let ru = Settings::read().c.ru();
        let (ok, log) = match out {
            Ok(o) => (o.status.success(), String::from_utf8_lossy(&o.stdout).to_string()),
            Err(e) => (false, e.to_string()),
        };
        let pkgs = !Dotfiles::read().changed_packages.is_empty();
        {
            let mut d = Dotfiles::write();
            d.updating = false;
            d.log = log;
            if !ok {
                d.error = if ru { "Не удалось обновить — подробности ниже".into() } else { "Update failed — see the log below".into() };
            }
        }
        if ok {
            let (t, b) = if ru {
                ("Обновлено — перезапускаю оболочку", if pkgs { "Изменились списки пакетов — поставьте их в Настройки → Обновления" } else { "Новая версия запустится через секунду" })
            } else {
                ("Updated — restarting the shell", if pkgs { "Package lists changed — install them in Settings → Updates" } else { "The new version starts in a second" })
            };
            amane::spawn(&format!("notify-send -a Rexilone -i system-software-update {} {}", sh_quote(t), sh_quote(b)));
            // новая версия: пересобрать и перезапустить выбранный шелл
            amane::spawn("setsid -f sh -c 'sleep 0.5; \"$HOME/.local/bin/rexilone-shell\" build >/dev/null 2>&1; \"$HOME/.local/bin/rexilone-shell\" restart' >/dev/null 2>&1");
        }
    });
}

// поставить пакеты из обновлённых списков — в терминале (спросит пароль)
pub fn install_packages() {
    let dir = Dotfiles::read().dir.clone();
    let ru = Settings::read().c.ru();
    let prompt = if ru { "Готово. Enter — закрыть" } else { "Done. Press Enter to close" };
    amane::spawn(&format!(
        "setsid -f foot -T 'Rexilone update' sh -c {} >/dev/null 2>&1",
        sh_quote(&format!("\"{dir}/install.sh\"; echo; read -p '{prompt}' _"))
    ));
}

// уведомление о новых коммитах (одно на каждую новую версию)
fn notify_if_new() {
    let (behind, head, subject) = {
        let d = Dotfiles::read();
        (d.behind, d.incoming.first().map(|c| c.hash.clone()), d.incoming.first().map(|c| c.subject.clone()).unwrap_or_default())
    };
    let Some(head) = head.filter(|_| behind > 0) else { return };
    if Settings::read().raw.get("updateNotified").str() == Some(head.as_str()) {
        return;
    }
    settings::save_key("updateNotified", Json::Str(head));
    let ru = Settings::read().c.ru();
    let more = if behind > 1 { if ru { format!(" и ещё {}", behind - 1) } else { format!(" and {} more", behind - 1) } } else { String::new() };
    let title = if ru { "Доступно обновление" } else { "Update available" };
    let body = format!("{subject}{more} — {}", if ru { "Настройки → Обновления" } else { "Settings → Updates" });
    amane::spawn(&format!("notify-send -a Rexilone -i system-software-update {} {}", sh_quote(title), sh_quote(&body)));
}

pub fn ipc(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("update") => update(),
        _ => check(),
    }
    String::from("ok")
}

impl Service for Dotfiles {
    fn new() -> Self {
        // версия — сразу из файла VERSION рядом с дотфайлами (проверка git — позже)
        let root = std::fs::canonicalize(settings::home().join(".config/amane")).ok().and_then(|p| p.ancestors().nth(3).map(|a| a.to_path_buf()));
        let version = root
            .and_then(|r| std::fs::read_to_string(r.join("VERSION")).ok())
            .map(|v| v.lines().next().unwrap_or("").trim().to_string())
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| "1.0.0".into());
        Dotfiles { version, ..Default::default() }
    }

    // автопроверка: через минуту после запуска и потом раз в 6 часов
    fn listen() {
        std::thread::sleep(Duration::from_secs(60));
        loop {
            if Settings::read().raw.get("updateAuto").bool_or(true) {
                check();
            }
            std::thread::sleep(Duration::from_secs(6 * 3600));
        }
    }
}

// ── pacman

#[derive(Default)]
pub struct PkgUpdates {
    pub installed: bool,
    pub list: Vec<String>,
    pub checking: bool,
}

pub fn pkg_refresh() {
    if !PkgUpdates::read().installed {
        return;
    }
    PkgUpdates::write().checking = true;
    std::thread::spawn(|| {
        let out = amane::output("checkupdates 2>/dev/null");
        let mut p = PkgUpdates::write();
        p.list = out.lines().filter(|l| !l.trim().is_empty()).map(String::from).collect();
        p.checking = false;
    });
}

pub fn pkg_upgrade() {
    amane::spawn("setsid -f foot -T 'System update' sh -c \"sudo pacman -Syu; echo; read -p 'Done. Press Enter to close…' _\" >/dev/null 2>&1");
}

pub fn pkg_install_tool() {
    amane::spawn("pkexec pacman -S --needed --noconfirm pacman-contrib");
}

impl Service for PkgUpdates {
    fn new() -> Self {
        PkgUpdates { installed: !amane::output("command -v checkupdates").is_empty(), ..Default::default() }
    }

    fn listen() {
        let mut since = Instant::now() - Duration::from_secs(3600);
        loop {
            let wanted = Settings::read().c.module_on("updates", false);
            let installed = !amane::output("command -v checkupdates").is_empty();
            if PkgUpdates::read().installed != installed {
                PkgUpdates::write().installed = installed;
            }
            if wanted && installed && since.elapsed() > Duration::from_secs(30 * 60) {
                since = Instant::now();
                pkg_refresh();
            }
            std::thread::sleep(Duration::from_secs(20));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_check_output() {
        let mut d = Dotfiles::default();
        apply_check(&mut d, "@dir /home/u/my-dotfiles\n@version 1.8.0\n@missing swayidle\n@dirty 2\n@commit 7fa7b4b\t3 hours ago\tRexilone Shell 1.7.1: x\n@behind 2\n@in abc\tRexilone\t1 hour ago\tNew: thing\n@in def\tRexilone\t2 hours ago\tFix\n@pkg packages/arch.txt\n");
        assert!(d.is_repo);
        assert_eq!(d.version, "1.8.0");
        assert_eq!(d.dirty, 2);
        assert_eq!(d.commit, "7fa7b4b");
        assert_eq!(d.commit_subject, "Rexilone Shell 1.7.1: x");
        assert_eq!(d.behind, 2);
        assert_eq!(d.incoming[0], Commit { hash: "abc".into(), author: "Rexilone".into(), when: "1 hour ago".into(), subject: "New: thing".into() });
        assert_eq!(d.changed_packages, vec!["packages/arch.txt"]);
        assert_eq!(d.missing_packages, vec!["swayidle"]);
        let mut n = Dotfiles::default();
        apply_check(&mut n, "@norepo\n");
        assert!(!n.is_repo);
    }
}
