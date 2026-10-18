// окно «Программы» (StoreWindow.qml + store/*.qml): главная, категории, поиск, установленное, обновления,
// страница приложения и полоса задач. Заголовок окна «Software» — на нём правило окна в niri

use std::time::SystemTime;

use amane::{Center, Column, End, Image, Key, Padding, Parent, Pointer, Rectangle, Row, ScrollArea, Service, Stack, Start, Window, children, close_window, open_window};

use crate::look::{self, Tk};
use crate::prefs::Prefs;
use crate::prefs::w::{self, Btn, Card, W, bx};
use crate::store::{self, AUR_PICKS, App, CATEGORIES, PICKS, Store};
use crate::ui;

fn get(k: &str) -> String {
    Prefs::get(&format!("store:{k}"))
}
fn set(k: &str, v: &str) {
    Prefs::set(&format!("store:{k}"), v);
}

pub fn show(page: &str) {
    if !page.is_empty() {
        set("page", page);
    }
    if get("page").is_empty() {
        set("page", "home");
    }
    if Store::read().catalog.is_empty() {
        store::load_catalog();
    }
    store::refresh_installed();
    if Store::read().last_check.is_none_or(|t| t.elapsed().as_secs() > 600) {
        store::check_updates();
    }
    set("open", "1");
    open_window("store", view);
}

pub fn close() {
    set("open", "");
    close_window("store");
}

fn open_app(pkg: &str, aur: bool) {
    set("detail", pkg);
    set("aur", if aur { "1" } else { "" });
    store::load_info(pkg);
}

pub fn ipc(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("toggle") => {
            if get("open").is_empty() {
                show("")
            } else {
                close()
            }
        }
        Some("search") => {
            let q = args[1..].join(" ");
            set("detail", "");
            w::set_field("store-search", &q);
            store::search(&q);
            show("search");
        }
        Some("app") => {
            if let Some(p) = args.get(1) {
                open_app(p, false);
                show("");
            }
        }
        Some("updates") => {
            set("detail", "");
            show("updates");
        }
        Some("hide") | Some("close") => close(),
        _ => show(""),
    }
    "ok".into()
}

// ── общие куски

fn icon(t: &Tk, pkg: &str, size: f32) -> Rectangle {
    let s = Store::read();
    let p = s.icon_for(pkg);
    let name = s.display_name(pkg);
    drop(s);
    let r = Rectangle::new().width(size).height(size);
    match p {
        Some(p) => r.fill(Image::contain(p).thumbnail((size * 2.0) as u32, (size * 2.0) as u32)),
        None => {
            let base = name.trim_start_matches("lib").trim_start_matches("python-").trim_start_matches("ttf-");
            let letter = base.chars().next().map(|c| c.to_uppercase().collect::<String>()).unwrap_or_else(|| "?".into());
            r.radius(size * 0.26).fill(Rectangle_fill(t)).align_child(Center, Center).child(ui::bold(t, letter, t.p.fg).size(size * 0.42))
        }
    }
}

#[allow(non_snake_case)]
fn Rectangle_fill(t: &Tk) -> amane::Color {
    t.p.surface_hi2
}

// кнопка действия: Установить / Открыть / в очереди / идёт установка
fn action(t: &Tk, pkg: &str, aur: bool) -> Rectangle {
    let s = Store::read();
    let busy = s.busy_with(pkg);
    let installed = s.installed(pkg);
    let launch = s.can_launch(pkg);
    let running = s.current().is_some_and(|j| j.pkgs.iter().any(|p| p == pkg));
    drop(s);
    let label = match busy.as_str() {
        "install" => if running { "Installing…" } else { "Queued" },
        "remove" => "Removing…",
        _ if installed => if launch { "Open" } else { "Installed" },
        _ => "Install",
    };
    let mut b = Btn::new(label).primary_if(!installed && busy.is_empty()).enabled(busy.is_empty() && (!installed || launch));
    if busy.is_empty() && !installed {
        b = b.icon(0xF01DA);
    }
    let p = pkg.to_string();
    b.build(t, &format!("st-act:{pkg}"), move || if installed { store::launch(&p) } else { store::install(&p, aur) })
}

// карточка приложения в сетке
fn app_card(t: &Tk, w: f32, pkg: &str, summary: &str, aur: bool) -> Rectangle {
    let s = Store::read();
    let name = s.display_name(pkg);
    let installed = s.installed(pkg);
    let upd = s.has_update(pkg);
    drop(s);
    let id = format!("st-card:{pkg}");
    let hov = w::hov(&id);
    let tw = w - 28.0 - 52.0 - 14.0;
    let mut title: Vec<W> = Vec::new();
    let mut used = 0.0;
    if aur {
        used += 40.0;
    }
    if installed {
        used += 22.0;
    }
    title.push(bx(w::line(t, &name, t.fs, t.p.fg, tw - used, true)));
    if aur {
        title.push(bx(Rectangle::new().width(34.0).height(16.0).radius(5.0).fill(t.p.surface_hi2).align_child(Center, Center).child(ui::bold(t, "AUR", t.p.warn).size(t.fs - 5.0))));
    }
    if installed {
        title.push(bx(ui::icon(t, if upd { 0xF06B0 } else { 0xF012C }, t.icon - 2.0, if upd { t.p.warn } else { t.p.dim })));
    }
    let sum: String = summary.chars().take(140).collect();
    let r = Rectangle::new().width(w).height(92.0).radius(12.0).fill(if hov { t.p.surface_hi } else { t.p.surface }).padding(Padding { top: 0.0, right: 14.0, bottom: 0.0, left: 14.0 }).child(
        Row::new(children![icon(t, pkg, 52.0), Column::new(children![Row::new(title).gap(6.0).align(Center), clip_para(t, &sum, tw, 2)]).gap(3.0).width(tw)]).gap(14.0).height(92.0).align(Center),
    );
    let p = pkg.to_string();
    w::clickable(r, &id, w::act(move || open_app(&p, aur)))
}

// абзац не длиннее n строк
fn clip_para(t: &Tk, s: &str, w: f32, n: usize) -> Rectangle {
    let p = w::para(t, s, t.fs - 2.0, t.p.dim, w);
    let lh = w::line_h(t.fs - 2.0);
    let (_, h) = w::wh(&p);
    Rectangle::new().width(w).height(h.min(lh * n as f32)).clip().child(p)
}

fn grid(t: &Tk, width: f32, items: Vec<(String, String, bool)>) -> W {
    let cols = ((width / 260.0).floor() as usize).max(1);
    let cw = w::width_for(cols, width, 10.0);
    let cards: Vec<W> = items.iter().map(|(p, s, a)| bx(app_card(t, cw, p, s, *a))).collect();
    bx(w::grid(cards, cols, 10.0))
}

fn header(t: &Tk, width: f32, text: &str, act: Option<(String, Box<dyn Fn()>)>) -> W {
    let mut row: Vec<W> = vec![bx(Rectangle::new().width(width - 140.0).height(28.0).align_child(Start, End).child(ui::bold(t, text, t.p.fg).size(t.fs + 3.0)))];
    if let Some((label, f)) = act {
        let id = format!("st-hdr:{text}");
        let hov = w::hov(&id);
        row.push(bx(w::clickable(Rectangle::new().width(140.0).height(28.0).align_child(End, End).child(ui::text(t, format!("{label}  ›"), if hov { t.p.fg } else { t.p.dim }).size(t.fs - 1.0)), &id, w::act(f))));
    }
    bx(Rectangle::new().width(width).height(42.0).align_child(Start, End).child(Row::new(row)))
}

fn empty(t: &Tk, width: f32, icon: u32, text: &str, hint: &str) -> W {
    let mut c: Vec<W> = vec![bx(ui::icon(t, icon, 44.0, t.p.dim)), bx(ui::text(t, text, t.p.fg).size(t.fs + 1.0))];
    if !hint.is_empty() {
        c.push(bx(w::para(t, hint, t.fs - 2.0, t.p.dim, 520.0f32.min(width))));
    }
    bx(Rectangle::new().width(width).height(180.0).padding(Padding { top: 40.0, right: 0.0, bottom: 0.0, left: 0.0 }).align_child(Center, Start).child(Column::new(c).gap(8.0).align(Center)))
}

// строка пакета (поиск по пакетам, установленное, обновления)
fn pkg_row(t: &Tk, w: f32, pkg: &str, title: &str, sub: &str, badge: &str, meta: &str, aur: bool, show_action: bool, extra: Vec<W>) -> Rectangle {
    let id = format!("st-row:{pkg}:{badge}");
    let hov = w::hov(&id);
    let metal = ui::text(t, meta, t.p.dim).size(t.fs - 3.0);
    let (mw, _) = ui::size_of(&metal);
    let mut right: Vec<W> = vec![bx(metal)];
    right.extend(extra);
    if show_action {
        right.push(bx(action(t, pkg, aur)));
    }
    let rr = Row::new(right).gap(10.0).align(Center);
    let (rw, _) = ui::size_of(&rr);
    let tw = w - 26.0 - 36.0 - 28.0 - rw;
    let mut tl: Vec<W> = vec![bx(w::line(t, title, t.fs - 1.0, t.p.fg, (tw - if badge.is_empty() { 0.0 } else { 50.0 }).max(40.0), true))];
    if !badge.is_empty() {
        tl.push(bx(ui::text(t, badge, if badge == "aur" { t.p.warn } else { t.p.dim }).size(t.fs - 4.0)));
    }
    let mut col: Vec<W> = vec![bx(Row::new(tl).gap(8.0).align(Center))];
    if !sub.is_empty() {
        col.push(bx(w::line(t, sub, t.fs - 3.0, t.p.dim, tw, false)));
    }
    let _ = mw;
    let r = Rectangle::new().width(w).height(62.0).radius(10.0).fill(if hov { t.p.surface_hi } else { t.p.surface }).padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 14.0 }).child(
        Row::new(children![icon(t, pkg, 36.0), Column::new(col).gap(2.0).width(tw), rr]).gap(14.0).height(62.0).align(Center),
    );
    let p = pkg.to_string();
    w::clickable(r, &id, w::act(move || open_app(&p, aur)))
}

fn big_title(t: &Tk, text: &str) -> amane::Text {
    ui::bold(t, text, t.p.fg).size(t.fs + 13.0)
}

// ── страницы

fn home(t: &Tk, width: f32) -> Vec<W> {
    let s = Store::read();
    let mut v: Vec<W> = Vec::new();
    if !s.appstream {
        v.push(bx(Card::new(0xF0026, "App catalog is not installed", "archlinux-appstream-data gives names, icons, categories and screenshots. Search works without it")
            .ctrl(Btn::new("Install").primary().build(t, "st-appstream", || store::install("archlinux-appstream-data", false)))
            .build(t, width)));
    }
    let picks: Vec<(String, String, bool)> = PICKS.iter().filter_map(|p| s.app(p).map(|a| (p.to_string(), a.summary.clone(), false))).collect();
    let cats: Vec<(&str, &str, Vec<App>)> = CATEGORIES.iter().map(|(k, l, _)| (*k, *l, s.in_category(k))).collect();
    let loading = s.catalog_loading;
    drop(s);
    v.push(header(t, width, &t.t("Editors' picks"), None));
    v.push(grid(t, width, picks));
    v.push(header(t, width, &t.t("Popular in AUR"), None));
    v.push(grid(t, width, AUR_PICKS.iter().map(|(n, d)| (n.to_string(), t.t(d), true)).collect()));
    for (key, label, mut list) in cats {
        if list.is_empty() {
            continue;
        }
        let n = list.len();
        // сначала подборки, потом приложения со скриншотами
        list.sort_by_key(|a| (!PICKS.contains(&a.pkg.as_str()), a.screenshots.is_empty(), a.description.len() <= 200));
        let k = key.to_string();
        v.push(header(t, width, &t.t(label), Some((format!("{} {n}", t.t("All")), Box::new(move || set("page", &k))))));
        v.push(grid(t, width, list.iter().take(6).map(|a| (a.pkg.clone(), a.summary.clone(), false)).collect()));
    }
    if loading {
        v.push(bx(ui::text(t, t.t("Loading…"), t.p.dim).size(t.fs - 1.0)));
    }
    v
}

fn category(t: &Tk, width: f32, key: &str) -> Vec<W> {
    let label = CATEGORIES.iter().find(|c| c.0 == key).map(|c| c.1).unwrap_or("");
    let sort = Some(get("sort")).filter(|x| !x.is_empty()).unwrap_or_else(|| "popular".into());
    let mut list = Store::read().in_category(key);
    if sort != "name" {
        list.sort_by(|a, b| (!PICKS.contains(&a.pkg.as_str()), a.screenshots.is_empty()).cmp(&(!PICKS.contains(&b.pkg.as_str()), b.screenshots.is_empty())).then_with(|| a.name.cmp(&b.name)));
    }
    let ch = w::choice(t, "st-sort", &[("popular", "Featured"), ("name", "A–Z")], &sort, |v| set("sort", &v));
    let (cw, _) = ui::size_of(&ch);
    let n = list.len();
    vec![
        bx(Row::new(children![Rectangle::new().width(width - cw).height(48.0).align_child(Start, Center).child(big_title(t, &t.t(label))), ch]).align(Center)),
        bx(ui::text(t, format!("{n} {}", crate::i18n::plural(t.c.ru(), n as i64, "app", "apps", "приложение", "приложения", "приложений")), t.p.dim).size(t.fs - 1.0)),
        grid(t, width, list.iter().map(|a| (a.pkg.clone(), a.summary.clone(), false)).collect()),
    ]
}

fn search_page(t: &Tk, width: f32) -> Vec<W> {
    let s = Store::read();
    let apps = store::search_catalog(&s.catalog, &s.query);
    let app_pkgs: Vec<String> = apps.iter().map(|a| a.pkg.clone()).collect();
    let pkgs: Vec<crate::json::Json> = s.repo.iter().filter(|p| !app_pkgs.contains(&p.get("name").str_or(""))).take(40).cloned().collect();
    let aur: Vec<crate::json::Json> = s.aur.iter().take(40).cloned().collect();
    let (aur_err, searching, q) = (s.aur_error, s.searching, s.query.clone());
    drop(s);
    let mut v: Vec<W> = Vec::new();
    if !apps.is_empty() {
        v.push(header(t, width, &t.t("Apps"), None));
        v.push(grid(t, width, apps.iter().take(24).map(|a| (a.pkg.clone(), a.summary.clone(), false)).collect()));
    }
    if !pkgs.is_empty() {
        v.push(header(t, width, &t.t("Packages"), None));
    }
    for p in &pkgs {
        let n = p.get("name").str_or("");
        v.push(bx(pkg_row(t, width, &n, &n, &p.get("desc").str_or(""), &p.get("repo").str_or(""), &p.get("version").str_or(""), false, true, vec![])));
    }
    if !aur.is_empty() || aur_err {
        v.push(header(t, width, "AUR", None));
    }
    if aur_err {
        v.push(bx(ui::text(t, t.t("AUR is not reachable — check the connection"), t.p.dim).size(t.fs - 1.0)));
    }
    for p in &aur {
        let n = p.get("name").str_or("");
        let meta = format!("{} {}   {}", ui::glyph(0xF04CE), p.get("votes").num_or(0.0), p.get("version").str_or(""));
        v.push(bx(pkg_row(t, width, &n, &n, &p.get("desc").str_or(""), "aur", &meta, true, true, vec![])));
    }
    if searching {
        v.push(bx(ui::text(t, t.t("Searching repositories and AUR…"), t.p.dim).size(t.fs - 1.0)));
    }
    if !searching && q.trim().chars().count() >= 2 && apps.is_empty() && pkgs.is_empty() && aur.is_empty() {
        v.push(empty(t, width, ui::ic::SEARCH, &t.t("Nothing found"), &t.t("Try another name or a shorter word")));
    }
    v
}

fn installed_page(t: &Tk, width: f32) -> Vec<W> {
    let mode = Some(get("mode")).filter(|x| !x.is_empty()).unwrap_or_else(|| "apps".into());
    let filter = w::field_text("st-filter").trim().to_lowercase();
    let s = Store::read();
    let mut list: Vec<crate::json::Json> = s
        .packages
        .iter()
        .filter(|p| {
            let n = p.get("name").str_or("");
            (mode == "all" || !p.get("app").str_or("").is_empty() || s.app(&n).is_some())
                && (filter.is_empty() || format!("{n} {} {}", s.display_name(&n), p.get("desc").str_or("")).to_lowercase().contains(&filter))
        })
        .cloned()
        .collect();
    list.sort_by_key(|p| s.display_name(&p.get("name").str_or("")).to_lowercase());
    let foreign = s.foreign.len();
    let rows: Vec<(String, String, String, String, bool, bool, bool)> = list
        .iter()
        .map(|p| {
            let n = p.get("name").str_or("");
            let dn = s.display_name(&n);
            let summary = s.app(&n).map(|a| a.summary.clone()).filter(|x| !x.is_empty()).unwrap_or_else(|| p.get("desc").str_or(""));
            let sub = [if dn != n { n.clone() } else { String::new() }, summary].into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join("   ·   ");
            let meta = [p.get("version").str_or(""), p.get("size").str_or("")].into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join("   ·   ");
            let aur = p.get("aur").bool_or(false);
            let busy = !s.busy_with(&n).is_empty();
            (n.clone(), dn, sub, meta, aur, busy, s.can_launch(&n) || busy)
        })
        .collect();
    drop(s);
    let ch = w::choice(t, "st-mode", &[("apps", "Apps"), ("all", "All packages")], &mode, |v| set("mode", &v));
    let (cw, _) = ui::size_of(&ch);
    let n = rows.len();
    let mut v: Vec<W> = vec![
        bx(Row::new(children![Rectangle::new().width(width - cw).height(48.0).align_child(Start, Center).child(big_title(t, &t.t("Installed"))), ch]).align(Center)),
        bx(Row::new(children![
            Rectangle::new().width(width - 270.0).height(38.0).align_child(Start, Center).child(ui::text(t, format!("{n} {}   ·   {foreign} {}", t.tr("items", "шт."), t.t("from AUR")), t.p.dim).size(t.fs - 1.0)),
            w::field(t, "st-filter", 260.0, "Filter", ui::ic::SEARCH, |_| {})
        ])
        .gap(10.0)
        .align(Center)),
    ];
    for (name, dn, sub, meta, aur, busy, show) in rows.into_iter().take(400) {
        let mut extra: Vec<W> = Vec::new();
        if !busy {
            let p = name.clone();
            extra.push(bx(Btn::new("").icon(ui::ic::TRASH).danger().build(t, &format!("st-rm:{name}"), move || store::remove(&p))));
        }
        v.push(bx(pkg_row(t, width, &name, &dn, &sub, if aur { "aur" } else { "" }, &meta, aur, show, extra)));
    }
    v
}

fn updates_page(t: &Tk, width: f32) -> Vec<W> {
    let s = Store::read();
    let ups = s.updates.clone();
    let (checking, has_cu, last) = (s.checking, s.has_checkupdates, s.last_check);
    let upgrading = s.jobs.iter().any(|j| j.kind == "upgrade" && (j.state == "running" || j.state == "queued"));
    drop(s);
    let mut btns: Vec<W> = vec![bx(Btn::new(if checking { "Checking…" } else { "Check" }).icon(0xF0450).enabled(!checking).build(t, "st-check", store::check_updates))];
    if !ups.is_empty() {
        btns.push(bx(Btn::new(if upgrading { "Updating…" } else { "Update all" }).icon(0xF06B0).primary().enabled(!upgrading).build(t, "st-upall", store::upgrade_all)));
    }
    let br = Row::new(btns).gap(10.0).align(Center);
    let (bw, _) = ui::size_of(&br);
    let mut v: Vec<W> = vec![bx(Row::new(children![Rectangle::new().width(width - bw).height(48.0).align_child(Start, Center).child(big_title(t, &t.t("Updates"))), br]).align(Center))];
    if !ups.is_empty() {
        let n = ups.len();
        v.push(bx(w::para(
            t,
            &format!("{n} {}   ·   {}", crate::i18n::plural(t.c.ru(), n as i64, "update", "updates", "обновление", "обновления", "обновлений"), t.t("Arch updates the whole system at once — single packages aren't updated separately")),
            t.fs - 1.0,
            t.p.dim,
            width,
        )));
    }
    if !has_cu {
        v.push(bx(Card::new(0xF0026, "Checking updates needs pacman-contrib", "It counts updates without touching the system")
            .ctrl(Btn::new("Install").primary().build(t, "st-cu", || store::install("pacman-contrib", false)))
            .build(t, width)));
    }
    for u in &ups {
        let n = u.get("name").str_or("");
        let aur = u.get("repo").str() == Some("aur");
        let dn = Store::read().display_name(&n);
        v.push(bx(pkg_row(t, width, &n, &dn, &format!("{}  →  {}", u.get("from").str_or(""), u.get("to").str_or("")), if aur { "aur" } else { "" }, "", aur, false, vec![])));
    }
    if ups.is_empty() && !checking && has_cu {
        let hint = last
            .map(|l| {
                let secs = SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0) - l.elapsed().as_secs() as i64;
                let c = crate::clock::civil(secs, crate::clock::Clock::read().offset);
                format!("{} {}", t.t("Checked"), crate::clock::format("HH:mm", &c, t.c.ru()))
            })
            .unwrap_or_default();
        v.push(empty(t, width, 0xF05E0, &t.t("Everything is up to date"), &hint));
    }
    v
}

fn chip(t: &Tk, label: &str, value: &str, tint: amane::Color) -> Rectangle {
    let c = Column::new(children![ui::bold(t, value, tint), ui::text(t, t.t(label), t.p.dim).size(t.fs - 4.0)]).gap(2.0).align(Center);
    let (cw, _) = ui::size_of(&c);
    Rectangle::new().width(cw + 28.0).height(54.0).radius(10.0).fill(t.p.surface).align_child(Center, Center).child(c)
}

fn detail_page(t: &Tk, width: f32, pkg: &str, aur: bool) -> Vec<W> {
    let s = Store::read();
    let app = s.app(pkg).cloned();
    let inf = s.info.get(pkg).cloned().unwrap_or_default();
    let installed = s.installed(pkg);
    let busy = s.busy_with(pkg);
    let upd = s.has_update(pkg);
    let cur_line = s.current().filter(|j| j.pkgs.iter().any(|p| p == pkg)).map(|j| j.line.clone());
    drop(s);
    let is_aur = aur || inf.get("repo").str() == Some("aur");
    let mut v: Vec<W> = Vec::new();
    let bh = w::hov("st-back");
    v.push(bx(w::clickable(Rectangle::new().width(120.0).height(24.0).child(ui::text(t, format!("‹  {}", t.t("Go back")), if bh { t.p.fg } else { t.p.dim })), "st-back", w::act(|| set("detail", "")))));
    // ── шапка
    let tw = width - 96.0 - 22.0;
    let name = app.as_ref().map(|a| a.name.clone()).filter(|x| !x.is_empty()).unwrap_or_else(|| pkg.to_string());
    let repo = if is_aur { "AUR".to_string() } else { inf.get("repo").str().map(String::from).or(app.as_ref().map(|a| a.repo.clone())).unwrap_or_default() };
    let meta = [app.as_ref().map(|a| a.developer.clone()).unwrap_or_default(), pkg.to_string(), repo.clone()].into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join("   ·   ");
    let summary = app.as_ref().map(|a| a.summary.clone()).filter(|x| !x.is_empty()).unwrap_or_else(|| inf.get("desc").str_or(""));
    let mut head: Vec<W> = vec![bx(w::para(t, &name, t.fs + 12.0, t.p.fg, tw)), bx(w::line(t, &meta, t.fs - 1.0, if is_aur { t.p.warn } else { t.p.dim }, tw, false))];
    if !summary.is_empty() {
        head.push(bx(Rectangle::new().width(tw).height(4.0)));
        head.push(bx(w::para(t, &summary, t.fs, t.p.muted, tw)));
    }
    let mut btns: Vec<W> = vec![bx(action(t, pkg, is_aur))];
    if installed && upd && busy.is_empty() {
        btns.push(bx(Btn::new("Update").icon(0xF06B0).build(t, "st-d-up", store::upgrade_all)));
    }
    if installed && busy.is_empty() {
        let p = pkg.to_string();
        btns.push(bx(Btn::new("Remove").icon(ui::ic::TRASH).danger().build(t, "st-d-rm", move || store::remove(&p))));
    }
    let site = app.as_ref().map(|a| a.homepage.clone()).filter(|x| !x.is_empty()).unwrap_or_else(|| inf.get("url").str_or(""));
    if !site.is_empty() {
        let u = site.clone();
        btns.push(bx(Btn::new("Website").icon(0xF059F).build(t, "st-d-web", move || amane::spawn(&format!("xdg-open {}", crate::niri::sh_quote(&u))))));
    }
    head.push(bx(Rectangle::new().width(tw).height(12.0)));
    head.push(bx(Row::new(btns).gap(8.0).align(Center)));
    if let Some(l) = cur_line {
        head.push(bx(w::line(t, &l, t.fs - 2.0, t.p.dim, tw, false)));
    }
    v.push(bx(Row::new(vec![bx(icon(t, pkg, 96.0)), bx(Column::new(head).gap(4.0).width(tw))]).gap(22.0)));
    // ── коротко
    let version = if installed && !inf.get("localVersion").str_or("").is_empty() { inf.get("localVersion").str_or("") } else { inf.get("version").str_or("") };
    let license = app.as_ref().map(|a| a.license.clone()).filter(|x| !x.is_empty()).unwrap_or_else(|| inf.get("license").str_or(""));
    let license = license.split(" AND ").next().unwrap_or("").split(" OR ").next().unwrap_or("").split("  ").next().unwrap_or("").to_string();
    let mut chips: Vec<W> = Vec::new();
    for (l, val) in [
        ("Version", version.clone()),
        ("Download", inf.get("download").str_or("")),
        ("Size", Some(inf.get("installedSize").str_or("")).filter(|x| !x.is_empty()).unwrap_or_else(|| inf.get("size").str_or(""))),
        ("License", license),
        ("Votes", inf.get("votes").num().map(|x| format!("{x}")).unwrap_or_default()),
        ("Popularity", inf.get("popularity").num().map(|x| format!("{x:.2}")).unwrap_or_default()),
    ] {
        if !val.is_empty() {
            chips.push(bx(chip(t, l, &val, t.p.fg)));
        }
    }
    if inf.get("outOfDate").bool_or(false) || inf.get("outOfDate").num().is_some_and(|x| x > 0.0) {
        chips.push(bx(chip(t, "Out of date", "!", t.p.warn)));
    }
    v.push(bx(Row::new(chips).gap(8.0)));
    // ── AUR: собирается из чужого PKGBUILD
    if is_aur {
        let maint = inf.get("maintainer").str_or("");
        let text = format!(
            "{}{}",
            t.t("AUR packages are made by users and built on your computer. Look at the PKGBUILD before installing."),
            if maint.is_empty() { String::new() } else { format!("   {}: {maint}", t.t("Maintainer")) }
        );
        let mut b: Vec<W> = Vec::new();
        let pb = inf.get("pkgbuild").str_or("");
        if !pb.is_empty() {
            b.push(bx(Btn::new("PKGBUILD").build(t, "st-pkgb", move || amane::spawn(&format!("xdg-open {}", crate::niri::sh_quote(&pb))))));
        }
        let ap = inf.get("aurPage").str_or("");
        if !ap.is_empty() {
            b.push(bx(Btn::new("AUR").build(t, "st-aurp", move || amane::spawn(&format!("xdg-open {}", crate::niri::sh_quote(&ap))))));
        }
        let br = Row::new(b).gap(8.0);
        let (bw, _) = ui::size_of(&br);
        let p = w::para(t, &text, t.fs - 2.0, t.p.fg, width - 32.0 - 30.0 - bw - 28.0);
        let (_, ph) = ui::size_of(&p);
        v.push(bx(Rectangle::new().width(width).height(ph.max(36.0) + 28.0).radius(10.0).fill(crate::theme::alpha(t.p.warn, 0.10)).border(1.0, crate::theme::alpha(t.p.warn, 0.5)).padding(Padding { top: 14.0, right: 16.0, bottom: 14.0, left: 16.0 }).child(
            Row::new(children![ui::icon(t, 0xF0026, t.icon + 4.0, t.p.warn), p, br]).gap(14.0).align(Center),
        )));
    }
    // ── скриншоты (скачиваются в кэш)
    if let Some(a) = &app {
        if !a.screenshots.is_empty() {
            let mut shots: Vec<W> = Vec::new();
            for (i, u) in a.screenshots.iter().take(6).enumerate() {
                let path = crate::dash::art_path(u);
                let url = u.clone();
                let r = Rectangle::new().width(420.0).height(250.0).radius(10.0).fill(t.p.surface).clip().cursor(Pointer).on_click(move |_| amane::spawn(&format!("xdg-open {}", crate::niri::sh_quote(&url))));
                shots.push(bx(match path {
                    Some(p) => r.child(Rectangle::new().width(420.0).height(250.0).fill(Image::contain(p).thumbnail(840, 500))),
                    None => r.align_child(Center, Center).child(ui::text(t, t.t("Loading…"), t.p.dim).size(t.fs - 2.0)),
                }));
                let _ = i;
            }
            let row = Row::new(shots).gap(10.0);
            v.push(bx(ScrollArea::new(w::sid(&format!("st-shots:{pkg}")), row).width(width).height(250.0)));
        }
    }
    // ── описание
    let desc = app.as_ref().map(|a| a.description.clone()).unwrap_or_else(|| inf.get("desc").str_or(""));
    if !desc.is_empty() {
        v.push(bx(w::para(t, &desc, t.fs - 1.0, t.p.fg, width)));
    }
    // ── сведения
    v.push(bx(w::section(t, "Package", width)));
    let dep = inf.get("depends").str_or("");
    let rows: Vec<(&str, String)> = vec![
        ("Package", pkg.to_string()),
        ("Repository", repo),
        ("Available version", inf.get("version").str_or("")),
        ("Installed version", inf.get("localVersion").str_or("")),
        ("Installed", inf.get("installDate").str_or("")),
        ("Built", inf.get("date").str_or("")),
        ("Packager", inf.get("packager").str_or("")),
        ("Depends on", if dep == "None" { String::new() } else { dep.split_whitespace().collect::<Vec<_>>().join(", ") }),
    ];
    for (k, val) in rows.into_iter().filter(|r| !r.1.is_empty()) {
        v.push(bx(Row::new(children![Rectangle::new().width(150.0).height(18.0).child(ui::text(t, t.t(k), t.p.dim).size(t.fs - 2.0)), w::para(t, &val, t.fs - 2.0, t.p.fg, width - 162.0)]).gap(12.0)));
    }
    if inf.is_null() {
        v.push(bx(ui::text(t, t.t("Loading…"), t.p.dim).size(t.fs - 2.0)));
    }
    v
}

// полоса задач внизу: что ставится сейчас, очередь, итог, журнал
fn job_bar(t: &Tk, width: f32) -> Option<Rectangle> {
    let s = Store::read();
    let job = s.current().cloned().or_else(|| s.jobs.iter().rev().find(|j| (j.state != "queued" && j.state != "cancelled") || !j.line.is_empty()).cloned())?;
    let active = s.current().is_some();
    let queued = s.queued();
    let name = s.display_name(job.pkgs.first().map(String::as_str).unwrap_or(""));
    let launch = job.state == "done" && job.kind == "install" && s.can_launch(job.pkgs.first().map(String::as_str).unwrap_or(""));
    drop(s);
    if !active && !get("dismissed").is_empty() {
        return None;
    }
    let title = if job.kind == "upgrade" {
        t.t(match job.state.as_str() {
            "running" => "Updating the system…",
            "done" => "System updated",
            "failed" => "System update failed",
            _ => "System update cancelled",
        })
    } else {
        let verb = match (job.state.as_str(), job.kind.as_str()) {
            ("running", "install") => "Installing",
            ("running", "remove") => "Removing",
            ("running", _) => "Updating",
            ("done", "install") => "Installed",
            ("done", "remove") => "Removed",
            ("done", _) => "Updated",
            ("failed", _) => "Failed",
            _ => "Cancelled",
        };
        format!("{}: {name}", t.t(verb))
    };
    let title = if queued > 0 { format!("{title}   ·   {}: {queued}", t.t("queued")) } else { title };
    let iw = width - 48.0;
    let spin = if active {
        amane::request_frame();
        (SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0) % 1400) as f32 / 1400.0 * 360.0
    } else {
        0.0
    };
    let ic = if active { 0xF0772 } else if job.state == "done" { 0xF012C } else { 0xF0028 };
    let icol = if job.state == "failed" { t.p.urgent } else if job.state == "done" { t.p.fg } else { t.p.accent };
    let mut btns: Vec<W> = Vec::new();
    if launch {
        let p = job.pkgs[0].clone();
        btns.push(bx(Btn::new("Open").primary().build(t, "st-job-open", move || store::launch(&p))));
    }
    let show_log = !get("log").is_empty();
    btns.push(bx(Btn::new(if show_log { "Hide log" } else { "Log" }).enabled(!job.log.is_empty()).build(t, "st-job-log", move || set("log", if show_log { "" } else { "1" }))));
    if !active {
        btns.push(bx(Btn::new("").icon(ui::ic::CLOSE).build(t, "st-job-x", || {
            set("dismissed", "1");
            set("log", "");
            store::clear_finished();
        })));
    }
    let br = Row::new(btns).gap(8.0).align(Center);
    let (bw, _) = ui::size_of(&br);
    let tw = iw - t.icon - 4.0 - bw - 28.0;
    let mut info: Vec<W> = vec![bx(Row::new(children![
        w::line(t, &title, t.fs - 1.0, t.p.fg, tw - 50.0, true),
        ui::text(t, if active && job.total > 0 { format!("{}/{}", job.step, job.total) } else { String::new() }, t.p.dim).size(t.fs - 2.0)
    ])
    .gap(8.0))];
    if !job.line.is_empty() {
        info.push(bx(w::line(t, &job.line, t.fs - 3.0, if job.state == "failed" { t.p.urgent } else { t.p.dim }, tw, false)));
    }
    if active {
        // прогресс: шаги pacman, иначе бегущая полоска
        let fill = if job.total > 0 {
            Rectangle::new().width(tw * job.step as f32 / job.total as f32).height(3.0).radius(2.0).fill(t.p.accent)
        } else {
            let pos = (SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0) % 1300) as f32 / 1300.0;
            Rectangle::new().width(tw * 0.3).height(3.0).radius(2.0).fill(t.p.accent).translate(pos * tw * 1.3 - tw * 0.3, 0.0)
        };
        info.push(bx(Rectangle::new().width(tw).height(3.0).radius(2.0).fill(t.p.surface_hi2).clip().child(fill)));
    }
    let mut col: Vec<W> = vec![bx(Row::new(vec![bx(Rectangle::new().width(t.icon + 4.0).height(t.icon + 4.0).rotate(spin).align_child(Center, Center).child(ui::icon(t, ic, t.icon + 4.0, icol))), bx(Column::new(info).gap(4.0).width(tw)), bx(br)]).gap(14.0).align(Center))];
    if show_log {
        let log = w::para(t, &job.log, t.fs - 3.0, t.p.muted, iw - 20.0);
        let (_, lh) = ui::size_of(&log);
        let id = w::sid("st-joblog");
        col.push(bx(Rectangle::new().width(iw).height(200.0).radius(8.0).fill(t.p.bg).padding(10.0).child(ScrollArea::new(id, Rectangle::new().width(iw - 20.0).height(lh).child(log)).width(iw - 20.0).height(180.0))));
    }
    let c = Column::new(col).gap(8.0);
    let (_, ch) = ui::size_of(&c);
    Some(Rectangle::new().width(width).height(ch + 24.0).fill(t.p.surface).padding(Padding { top: 12.0, right: 24.0, bottom: 12.0, left: 24.0 }).child(c))
}

fn sidebar(t: &Tk, h: f32) -> Rectangle {
    let inner = 250.0 - 32.0;
    let page = get("page");
    let detail = get("detail");
    let n_up = Store::read().updates.len();
    let mut col: Vec<W> = vec![bx(Rectangle::new().width(inner).height(46.0 + 18.0).padding(Padding { top: 0.0, right: 0.0, bottom: 18.0, left: 6.0 }).child(
        Row::new(children![
            Rectangle::new().width(46.0).height(46.0).radius(14.0).fill(t.p.accent).align_child(Center, Center).child(ui::icon(t, 0xF0110, 24.0, t.p.bg)),
            Column::new(children![ui::bold(t, t.t("Software"), t.p.fg).size(t.fs + 4.0), ui::text(t, "pacman · AUR", t.p.dim).size(t.fs - 2.0)]).gap(2.0)
        ])
        .gap(12.0)
        .align(Center),
    ))];
    let item = |key: &str, label: &str, icon: u32, badge: usize| -> W {
        let sel = page == key && detail.is_empty();
        let id = format!("st-nav:{key}");
        let hov = w::hov(&id);
        let mut row: Vec<W> = vec![
            bx(Rectangle::new().width(20.0).height(38.0).align_child(Center, Center).child(ui::icon(t, icon, t.icon + 1.0, if sel { t.p.accent } else { t.p.muted }))),
            bx(w::line(t, &t.t(label), t.fs - 1.0, if sel || hov { t.p.fg } else { t.p.muted }, inner - 16.0 - 10.0 - 34.0 - if badge > 0 { 34.0 } else { 0.0 }, sel)),
        ];
        if badge > 0 {
            let b = ui::bold(t, badge.to_string(), t.p.bg).size(t.fs - 4.0);
            let (bw, _) = ui::size_of(&b);
            row.push(bx(Rectangle::new().width((bw + 10.0).max(20.0)).height(18.0).radius(9.0).fill(t.p.accent).align_child(Center, Center).child(b)));
        }
        let mut layers: Vec<W> = Vec::new();
        if sel {
            layers.push(bx(Rectangle::new().width(3.0).height(18.0).radius(2.0).fill(t.p.accent).translate(0.0, 10.0)));
        }
        layers.push(bx(Rectangle::new().width(inner).height(38.0).padding(Padding { top: 0.0, right: 10.0, bottom: 0.0, left: 16.0 }).child(Row::new(row).gap(14.0).height(38.0).align(Center))));
        let r = Rectangle::new().width(inner).height(38.0).radius(10.0).fill(if sel { t.p.surface } else if hov { crate::theme::alpha(t.p.surface, 0.6) } else { amane::Color::TRANSPARENT }).child(Stack::new(layers));
        let k = key.to_string();
        bx(w::clickable(r, &id, w::act(move || {
            set("detail", "");
            set("page", &k);
            if k != "search" {
                w::set_field("store-search", "");
                store::search("");
            }
        })))
    };
    let group = |s: &str| -> W { bx(Rectangle::new().width(inner).height(36.0).padding(Padding { top: 14.0, right: 0.0, bottom: 4.0, left: 14.0 }).align_child(Start, End).child(ui::bold(t, t.t(s), t.p.dim).size(t.fs - 3.0))) };
    let mut nav: Vec<W> = vec![item("home", "Discover", 0xF0D3B, 0), group("Categories")];
    for (k, l, i) in CATEGORIES {
        nav.push(item(k, l, i, 0));
    }
    nav.push(group("Library"));
    nav.push(item("installed", "Installed", 0xF0C52, 0));
    nav.push(item("updates", "Updates", 0xF06B0, n_up));
    col.push(bx(ScrollArea::new("store-nav", Column::new(nav).gap(2.0)).width(inner).height(h - 20.0 - 64.0 - 16.0)));
    Rectangle::new().width(250.0).height(h).padding(Padding { top: 20.0, right: 16.0, bottom: 16.0, left: 16.0 }).child(Column::new(col))
}

pub fn view() -> Window {
    let tk = look::tk();
    let t = &tk;
    let (ww, wh) = amane::window_size();
    let (ww, wh) = if ww <= 0.0 { (1160.0, 780.0) } else { (ww, wh) };
    let pw = (ww - 250.0 - 10.0).max(400.0);
    let ph = (wh - 20.0).max(300.0);
    let cw = pw - 72.0;
    let detail = get("detail");
    let page = Some(get("page")).filter(|x| !x.is_empty()).unwrap_or_else(|| "home".into());
    // поиск: текст поля → запрос (с задержкой в store::search)
    let q = w::field_text("store-search");
    if q != Store::read().query {
        let q2 = q.clone();
        std::thread::spawn(move || {
            store::search(&q2);
            if !q2.trim().is_empty() {
                set("page", "search");
            } else if get("page") == "search" {
                set("page", "home");
            }
        });
    }
    let mut parts: Vec<W> = Vec::new();
    if detail.is_empty() {
        parts.push(bx(Rectangle::new().width(pw).height(68.0).padding(Padding { top: 22.0, right: 36.0, bottom: 4.0, left: 36.0 }).child(w::field(
            t,
            "store-search",
            cw,
            "Search apps and packages — repositories and AUR",
            ui::ic::SEARCH,
            |v| store::search(&v),
        ))));
    }
    let body: Vec<W> = if !detail.is_empty() {
        let aur = !get("aur").is_empty();
        detail_page(t, cw, &detail, aur)
    } else {
        match page.as_str() {
            "home" => home(t, cw),
            "search" => search_page(t, cw),
            "installed" => installed_page(t, cw),
            "updates" => updates_page(t, cw),
            k => category(t, cw, k),
        }
    };
    let jb = job_bar(t, pw);
    let jh = jb.as_ref().map(|j| ui::size_of(j).1).unwrap_or(0.0);
    let col = Column::new(body).gap(10.0);
    let (_, ch) = ui::size_of(&col);
    let top = if detail.is_empty() { 68.0 } else { 0.0 };
    let scroll_id = w::sid(&format!("store-page:{page}:{detail}"));
    let content = Rectangle::new().width(pw).height(ch + 54.0).padding(Padding { top: if detail.is_empty() { 14.0 } else { 24.0 }, right: 36.0, bottom: 40.0, left: 36.0 }).child(col);
    parts.push(bx(ScrollArea::new(scroll_id, content).width(pw).height((ph - top - jh).max(100.0))));
    if let Some(j) = jb {
        parts.push(bx(j));
    }
    let panel = Rectangle::new()
        .width(pw)
        .height(ph)
        .radius(16.0)
        .fill(crate::theme::mix(t.panel, t.p.surface, 0.5))
        .border(1.0, t.p.surface_hi)
        .clip()
        .child(Column::new(parts));
    Window::new()
        .title("Software")
        .size(1160.0, 780.0)
        .resizable(true)
        .on_key(|k| {
            if k == Key::Escape {
                if !get("detail").is_empty() {
                    set("detail", "");
                } else {
                    close();
                }
            }
        })
        .child(
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .fill(t.panel)
                .child(Row::new(children![sidebar(t, wh), Rectangle::new().width(pw + 10.0).height(wh).padding(Padding { top: 10.0, right: 10.0, bottom: 10.0, left: 0.0 }).child(panel)])),
        )
}

