// Обновления: окружение (git-репозиторий dots) и пакеты системы (pacman), UpdatesPage.qml

use amane::{Center, Column, Padding, Rectangle, Row, Service, Stack, Start, Weight, children};

use super::super::w::{self, Btn, Card, W, bx};
use super::Out;
use crate::boottheme::{self, BootTheme};
use crate::dotfiles::{self, DEFAULT_REPO, Dotfiles, PkgUpdates};
use crate::json::Json;
use crate::look::Tk;
use crate::settings::{self, Settings};
use crate::ui::{self, ic};

pub fn page(t: &Tk, w: f32) -> Out {
    // при открытии: проверить, если давно не проверяли
    let stale = Dotfiles::read().last_check.is_none_or(|i| i.elapsed().as_secs() > 60);
    if stale && !Dotfiles::read().checking {
        std::thread::spawn(dotfiles::check);
    }
    let d = Dotfiles::read();
    let ru = t.c.ru();
    let available = d.behind > 0;
    let mut items: Vec<W> = Vec::new();
    let busy = d.checking || d.updating;
    let icon = if busy { 0xF0450 } else if available { 0xF01DA } else { 0xF012C };
    let head = if d.updating {
        t.t("Updating…")
    } else if d.checking {
        t.t("Checking for updates…")
    } else if !d.is_repo {
        t.t("Not installed from git")
    } else if available {
        if ru {
            format!("Доступно обновление: {} {}", d.behind, crate::i18n::plural(true, d.behind, "", "", "изменение", "изменения", "изменений"))
        } else {
            format!("Update available: {} new {}", d.behind, if d.behind == 1 { "change" } else { "changes" })
        }
    } else if !d.error.is_empty() {
        t.t("Couldn't check for updates")
    } else {
        t.t("You're up to date")
    };
    let sub = format!("Rexilone Shell {}{}", d.version, if d.commit.is_empty() { String::new() } else { format!("   ·   {} · {}", d.commit, d.commit_date) });
    // крутится, пока идёт проверка
    let spin = if busy {
        amane::request_frame();
        (std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|x| x.as_millis()).unwrap_or(0) % 1200) as f32 / 1200.0 * 360.0
    } else {
        0.0
    };
    let mut btns: Vec<W> = vec![bx(Btn::new("Check").icon(0xF0450).enabled(!busy).build(t, "upd-check", dotfiles::check))];
    if available {
        btns.push(bx(Btn::new("Update").primary().enabled(!d.updating && d.dirty == 0).build(t, "upd-update", dotfiles::update)));
    }
    let br = Row::new(btns).gap(8.0).align(Center);
    let (bw, _) = w::wh(&br);
    let tw = w - 40.0 - 64.0 - 18.0 * 2.0 - bw;
    let mut lines: Vec<W> = vec![bx(w::line(t, &head, t.fs + 4.0, t.p.fg, tw, true)), bx(w::line(t, &sub, t.fs - 1.0, t.p.dim, tw, false))];
    if let Some(i) = d.last_check {
        let mins = i.elapsed().as_secs() / 60;
        let ago = if mins < 1 { t.tr("just now", "только что").to_string() } else if ru { format!("{mins} мин назад") } else { format!("{mins} min ago") };
        lines.push(bx(w::line(t, &format!("{}: {ago}", t.t("Last checked")), t.fs - 2.0, t.p.faint, tw, false)));
    }
    items.push(bx(Rectangle::new().width(w).height(104.0).radius(12.0).fill(t.p.surface).padding(20.0).child(
        Row::new(children![
            Rectangle::new().width(64.0).height(64.0).radius(18.0).fill(if available { t.p.accent } else { t.p.surface_hi }).align_child(Center, Center).child(
                Rectangle::new().width(32.0).height(32.0).rotate(spin).align_child(Center, Center).child(ui::icon(t, icon, 28.0, if available { t.p.bg } else { t.p.fg }))
            ),
            Column::new(lines).gap(3.0),
            br
        ])
        .gap(18.0)
        .height(64.0)
        .align(Center),
    )));
    if !d.error.is_empty() {
        let title = if d.error.contains("couldn't find remote ref") { "The repository is empty for now" } else { "Couldn't reach the repository" };
        items.push(bx(Card::new(0xF0026, title, &d.error).build(t, w)));
    }
    if d.dirty > 0 && available {
        let desc = if ru {
            format!("Изменено файлов в {}: {}. Закоммитьте или уберите их (git stash) — потом обновление.", d.dir, d.dirty)
        } else {
            format!("{} changed files in {}. Commit or stash them (git stash), then update.", d.dirty, d.dir)
        };
        items.push(bx(Card::new(0xF0026, "You have local changes", &desc).build(t, w)));
    }
    if !d.changed_packages.is_empty() || !d.missing_packages.is_empty() {
        let desc = if !d.missing_packages.is_empty() {
            format!("{}: {}", t.tr("Not installed", "Не установлено"), d.missing_packages.join(", "))
        } else {
            format!("{}: {}", t.tr("Changed lists", "Изменились списки"), d.changed_packages.join(", "))
        };
        items.push(bx(Card::new(0xF03D7, "New packages are needed", &desc).ctrl(Btn::new("Install packages").build(t, "upd-pkgs", dotfiles::install_packages)).build(t, w)));
    }
    let b = BootTheme::read();
    if !b.dots.is_empty() && (!b.installed || b.outdated) {
        items.push(bx(Card::new(ic::LOCK, "Update the boot menu and the login screen", "The system part (rexilone-boot, the Rexilone login screen on greetd) is newer in the update. Needs the password once; the new login screen starts on the next boot")
            .ctrl(Btn::new(if b.busy { "Installing…" } else { "Update" }).primary().enabled(!b.busy).build(t, "upd-boot", boottheme::setup))
            .build(t, w)));
    }
    drop(b);
    let repo = { let r = Settings::read().raw.get("updateRepo").str_or(""); if r.is_empty() { DEFAULT_REPO.to_string() } else { r } };
    if !d.is_repo && !d.checking {
        items.push(bx(Card::new(0xF02A2, "Install from git to get updates", &format!("git clone {repo} ~/my-dotfiles && ~/my-dotfiles/install.sh")).build(t, w)));
    }

    // ── что нового: «линия времени»
    if !d.incoming.is_empty() {
        items.push(bx(w::section(t, "What's new", w)));
        let n = d.incoming.len();
        let mut rows: Vec<W> = Vec::new();
        for (i, c) in d.incoming.iter().enumerate() {
            let mut dot: Vec<W> = Vec::new();
            if n > 1 {
                let (y, h) = if i == 0 { (22.0, 22.0) } else if i == n - 1 { (0.0, 22.0) } else { (0.0, 44.0) };
                dot.push(bx(Rectangle::new().width(2.0).height(h).fill(t.p.surface_hi2).translate(9.0, y)));
            }
            dot.push(bx(Rectangle::new().width(10.0).height(10.0).radius(amane::Full).fill(if i == 0 { t.p.accent } else { t.p.line }).translate(5.0, 17.0)));
            let tw = w - 16.0 - 20.0 - 14.0;
            rows.push(bx(Row::new(children![
                Rectangle::new().width(20.0).height(44.0).child(Stack::new(dot)),
                Column::new(children![
                    w::line(t, &c.subject, t.fs - 1.0, t.p.fg, tw, false),
                    w::line(t, &format!("{}   ·   {}   ·   {}", c.hash, c.author, c.when), t.fs - 3.0, t.p.dim, tw, false)
                ])
                .gap(1.0)
            ])
            .gap(14.0)
            .height(44.0)
            .align(Center)));
        }
        let col = Column::new(rows);
        let (_, ch) = w::wh(&col);
        items.push(bx(Rectangle::new().width(w).height(ch + 16.0).radius(10.0).fill(t.p.surface).padding(8.0).child(col)));
    }
    if !d.log.is_empty() && !d.error.is_empty() {
        let l = w::para(t, &d.log, t.fs - 3.0, t.p.muted, w - 28.0);
        let (_, lh) = w::wh(&l);
        items.push(bx(Rectangle::new().width(w).height(lh + 24.0).radius(10.0).fill(t.p.surface).padding(Padding { top: 12.0, right: 14.0, bottom: 12.0, left: 14.0 }).child(l)));
    }
    drop(d);

    // ── настройки обновлений
    items.push(bx(w::section(t, "Update settings", w)));
    let auto = Settings::read().raw.get("updateAuto").bool_or(true);
    items.push(bx(Card::new(0xF0450, "Check automatically", "A minute after login and every 6 hours; you get a notification when there's something new")
        .ctrl(w::switch(t, "upd-auto", auto, |v| settings::save_key("updateAuto", Json::Bool(v))))
        .build(t, w)));
    let branch = { let b = Settings::read().raw.get("updateBranch").str_or(""); if b.is_empty() { "main".to_string() } else { b } };
    let fw = w - 18.0 - 16.0 - 22.0 - 16.0 * 3.0 - 180.0 - 80.0;
    let r3 = repo.clone();
    let save = |v: String| {
        let v = v.trim().to_string();
        settings::save_key("updateRepo", Json::Str(if v == DEFAULT_REPO { String::new() } else { v }));
    };
    items.push(bx(Rectangle::new().width(w).height(64.0).radius(10.0).fill(t.p.surface).padding(Padding { top: 0.0, right: 16.0, bottom: 0.0, left: 18.0 }).child(
        Row::new(children![
            Rectangle::new().width(22.0).height(64.0).align_child(Center, Center).child(ui::icon(t, 0xF02A4, t.icon + 3.0, t.p.fg)),
            Column::new(children![w::tx(t, "Repository", t.fs, t.p.fg), w::raw(t, format!("{}: {branch}", t.t("Branch")), t.fs - 2.0, t.p.dim)]).gap(2.0).width(180.0),
            w::field(t, "upd-repo", fw.max(120.0), &repo, 0, save),
            Btn::new("Open").build(t, "upd-open", move || amane::spawn(&format!("xdg-open {}", crate::niri::sh_quote(&r3))))
        ])
        .gap(16.0)
        .height(64.0)
        .align(Center),
    )));

    // ── пакеты системы
    items.push(bx(w::section(t, "System packages", w)));
    let p = PkgUpdates::read();
    let title = if !p.installed {
        t.t("Update checker is not installed")
    } else if p.checking {
        t.t("Checking packages…")
    } else if !p.list.is_empty() {
        if ru { format!("Доступно обновлений: {}", p.list.len()) } else { format!("{} package updates", p.list.len()) }
    } else {
        t.t("Packages are up to date")
    };
    let desc = if !p.installed {
        t.t("pacman-contrib (checkupdates) counts updates without touching the system")
    } else {
        p.list.iter().take(5).map(|u| u.split(' ').next().unwrap_or("").to_string()).collect::<Vec<_>>().join(", ")
    };
    let ctrl: Option<W> = if !p.installed {
        Some(bx(Btn::new("Install").build(t, "pkg-install", dotfiles::pkg_install_tool)))
    } else if !p.list.is_empty() {
        Some(bx(Btn::new("Update").primary().build(t, "pkg-upgrade", dotfiles::pkg_upgrade)))
    } else {
        None
    };
    drop(p);
    let card = Card::new(0xF06B0, &title, &desc).id("pkgs");
    items.push(bx(match ctrl {
        Some(c) => card.ctrl_box(c),
        None => card,
    }
    .build(t, w)));
    let _ = (Start, Weight::Bold);
    Out { crumb: String::new(), subtitle: "Shell updates from GitHub and system packages".into(), items }
}
