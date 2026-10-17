// Телефон (Rexlink): служба — часть системы, окна нет — весь интерфейс здесь (PhonePage.qml и Phone*Tab.qml).
// Главная: устройство, состояние, медиа, устройства; подстраницы — по функциям.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use amane::{Button, Center, Column, End, Image, Key, Padding, Rectangle, Row, ScrollArea, Service, Stack, Start, Weight, children};

use super::super::w::{self, Btn, Card, W, bx};
use super::{Out, set_tab, tab};
use crate::clock::{self, Clock};
use crate::dotfiles::{self, Dotfiles};
use crate::json::Json;
use crate::look::Tk;
use crate::rexlink::{self as rl, Rexlink, obj};
use crate::settings::{self, Settings};
use crate::theme::alpha;
use crate::ui::{self, ic};

const PAGE: usize = 5;
const FOLDER: u32 = 0xF024B;

const SECTIONS: [(&str, &str, u32); 8] = [
    ("notifications", "Notifications", 0xF009A),
    ("messages", "Messages", 0xF0369),
    ("calls", "Calls", 0xF03F2),
    ("files", "Files", 0xF0256),
    ("clipboard", "Clipboard", 0xF014D),
    ("camera", "Webcam", 0xF05A0),
    ("screen", "Device screen", 0xF0379),
    ("options", "Rexlink settings", 0xF0493),
];

// ── общее

pub fn kind_name(kind: &str) -> &'static str {
    match kind {
        "tablet" => "Tablet",
        "watch" => "Watch",
        _ => "Phone",
    }
}

fn now_ms() -> f64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as f64).unwrap_or(0.0)
}

// «сейчас», «5 мин», «14:30», «вчера», «3 мар», «03.03.24» (Rexlink.ago)
pub fn ago(ms: f64, now: f64, offset: i64, ru: bool) -> String {
    if ms <= 0.0 {
        return String::new();
    }
    let min = ((now - ms) / 60000.0).floor() as i64;
    if min < 1 {
        return if ru { "сейчас" } else { "now" }.into();
    }
    if min < 60 {
        return if ru { format!("{min} мин") } else { format!("{min} min") };
    }
    let d = clock::civil((ms / 1000.0) as i64, offset);
    let n = clock::civil((now / 1000.0) as i64, offset);
    let y = clock::civil((now / 1000.0) as i64 - 86400, offset);
    let same = |a: &clock::Civil, b: &clock::Civil| a.year == b.year && a.month == b.month && a.day == b.day;
    if same(&d, &n) {
        return clock::format("HH:mm", &d, ru);
    }
    if same(&d, &y) {
        return if ru { "вчера" } else { "yesterday" }.into();
    }
    clock::format(if d.year == n.year { "d MMM" } else { "dd.MM.yy" }, &d, ru)
}

fn ago_t(t: &Tk, ms: f64) -> String {
    ago(ms, now_ms(), Clock::read().offset, t.c.ru())
}

fn plural_n(t: &Tk, n: usize) -> String {
    crate::i18n::plural(t.c.ru(), n as i64, "notification", "notifications", "уведомление", "уведомления", "уведомлений").to_string()
}

fn file_path(url: &str) -> String {
    url.strip_prefix("file://").unwrap_or(url).split('?').next().unwrap_or("").to_string()
}

// пустой список: иконка, текст, подсказка — по центру
fn empty(t: &Tk, w: f32, icon: u32, text: &str, hint: &str) -> Rectangle {
    let tw = w.min(560.0);
    let mut c: Vec<W> = vec![bx(ui::icon(t, icon, 40.0, t.p.dim)), bx(center_para(t, &t.t(text), t.fs + 1.0, t.p.fg, tw))];
    if !hint.is_empty() {
        c.push(bx(center_para(t, &t.t(hint), t.fs - 2.0, t.p.dim, tw)));
    }
    let col = Column::new(c).gap(8.0).align(Center);
    let (_, h) = w::wh(&col);
    Rectangle::new().width(w).height(h + 48.0).align_child(Center, Center).child(col)
}

fn center_para(t: &Tk, s: &str, size: f32, color: amane::Color, width: f32) -> Rectangle {
    let p = w::para(t, s, size, color, width);
    let (pw, ph) = w::wh(&p);
    let one = w::raw(t, s, size, color);
    let (ow, _) = w::wh(&one);
    if ow <= width { Rectangle::new().width(width).height(ph).align_child(Center, Center).child(one) } else { Rectangle::new().width(pw).height(ph).child(p) }
}

fn sw_rl(t: &Tk, id: &str, key: &'static str, def: bool) -> Rectangle {
    let on = Rexlink::read().settings.get(key).bool_or(def);
    w::switch(t, id, on, move |v| rl::set(key, Json::Bool(v)))
}

fn sw_shell(t: &Tk, key: &'static str, def: bool) -> Rectangle {
    let on = Settings::read().c.module_on(key, def);
    w::switch(t, &format!("mod:{key}"), on, move |v| settings::save_path(&["barModules", key], Json::Bool(v)))
}

fn show_apk() {
    amane::spawn(r#"sh -c 'xdg-open "$(dirname "$(readlink -f "$HOME/.local/bin/rexlink")")/../../../rexlink"'"#);
}

// выбор файлов: yazi в терминале (Enter / Space — выбрать, затем Enter)
fn pick_files() {
    static BUSY: Mutex<bool> = Mutex::new(false);
    if !Rexlink::read().online() || std::mem::replace(&mut *BUSY.lock().unwrap(), true) {
        return;
    }
    std::thread::spawn(|| {
        let out = amane::output(r#"sh -c 'f=$(mktemp); foot --app-id=rexlink-pick --title="Rexlink" yazi --chooser-file="$f" "$HOME" >/dev/null 2>&1; cat "$f"; rm -f "$f"'"#);
        *BUSY.lock().unwrap() = false;
        let paths: Vec<String> = out.lines().filter(|l| !l.trim().is_empty()).map(String::from).collect();
        if !paths.is_empty() {
            rl::send_files(&paths, "");
            set_tab(PAGE, "files");
        }
    });
}

// ── живая картинка (экран или камера). Служба пишет кадры JPEG-файлами по кругу; amane кэширует
// картинки по пути, поэтому каждый кадр — своя копия, а показываем его, когда он декодирован

struct FrameState {
    seq: f64,
    shown: Option<PathBuf>,
    pending: Option<(PathBuf, Instant)>,
}

fn frames() -> &'static Mutex<HashMap<String, FrameState>> {
    static F: std::sync::OnceLock<Mutex<HashMap<String, FrameState>>> = std::sync::OnceLock::new();
    F.get_or_init(|| Mutex::new(HashMap::new()))
}

fn frame_dir() -> PathBuf {
    PathBuf::from(std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into())).join("amane-frames")
}

fn frame(ch: &str, f: &Json) -> Option<PathBuf> {
    let mut all = frames().lock().unwrap();
    let st = all.entry(ch.to_string()).or_insert(FrameState { seq: -1.0, shown: None, pending: None });
    let seq = f.get("seq").num_or(-1.0);
    let src = f.get("path").str_or("");
    if seq != st.seq && st.pending.is_none() && !src.is_empty() {
        let dir = frame_dir();
        let _ = std::fs::create_dir_all(&dir);
        let dst = dir.join(format!("{}-{seq}.jpg", ch.replace([':', '/'], "_")));
        if std::fs::copy(&src, &dst).is_ok() {
            st.pending = Some((dst, Instant::now()));
            st.seq = seq;
        }
    }
    if let Some((p, at)) = st.pending.take() {
        if Image::loaded(&p) {
            if let Some(old) = st.shown.replace(p) {
                let _ = std::fs::remove_file(old);
            }
        } else if at.elapsed() > Duration::from_secs(2) {
            let _ = std::fs::remove_file(&p);
        } else {
            st.pending = Some((p, at));
        }
        amane::request_frame();
    }
    st.shown.clone()
}

fn drop_frames() {
    let mut all = frames().lock().unwrap();
    if !all.is_empty() {
        all.clear();
        let _ = std::fs::remove_dir_all(frame_dir());
    }
}

// какой видеоканал смотрим: пока смотрим, служба присылает кадры
fn want_channel(ch: &str, connected: bool) {
    static WATCHED: Mutex<(String, bool)> = Mutex::new((String::new(), false));
    let mut w = WATCHED.lock().unwrap();
    let want = if connected { ch.to_string() } else { String::new() };
    if w.0 == want && w.1 == connected {
        return;
    }
    let old = std::mem::replace(&mut w.0, want.clone());
    let was = std::mem::replace(&mut w.1, connected);
    if want.is_empty() {
        drop_frames();
    }
    std::thread::spawn(move || {
        if !old.is_empty() && was {
            rl::watch(&old, false);
        }
        if !want.is_empty() {
            rl::watch(&want, true);
        }
    });
}

// ушли со страницы или закрыли Настройки — перестать смотреть
pub fn leave() {
    want_channel("", Rexlink::read().connected);
}

// ═════════ страница

pub fn page(t: &Tk, w: f32, fill_h: f32) -> Out {
    let tb = tab(PAGE);
    let tb = if SECTIONS.iter().any(|s| s.0 == tb) { tb } else { String::new() };
    let r = Rexlink::read();
    let cur = r.current.clone();
    let connected = r.connected;
    let ch = match tb.as_str() {
        "camera" if r.camera.get("running").bool_or(false) => "camera".to_string(),
        "screen" if r.screens.get(&cur).get("running").bool_or(false) && !cur.is_empty() => format!("screen:{cur}"),
        _ => String::new(),
    };
    let toast = r.toast_at.filter(|a| a.elapsed() < Duration::from_millis(3200)).and_then(|_| r.toasts.last().cloned());
    drop(r);
    want_channel(&ch, connected);
    let mut items: Vec<W> = Vec::new();
    // подсказки службы («SMS отправлено», «Файл получен»…)
    if let Some(text) = toast {
        amane::request_frame();
        let l = w::raw(t, text, t.fs - 1.0, t.p.fg);
        let (lw, _) = w::wh(&l);
        items.push(bx(Rectangle::new().width(w).height(40.0).align_child(Center, Center).child(
            Rectangle::new().width((lw + 36.0).min(w - 80.0)).height(40.0).radius(10.0).fill(t.p.surface_hi).border(1.0, t.p.surface_hi2).align_child(Center, Center).clip().child(l),
        )));
    }
    common(t, w, &mut items);
    match tb.as_str() {
        "notifications" => notifs_tab(t, w, &mut items),
        "messages" => messages_tab(t, w, fill_h, &mut items),
        "calls" => calls_tab(t, w, &mut items),
        "files" => files_tab(t, w, &mut items),
        "clipboard" => clipboard_tab(t, w, &mut items),
        "camera" => camera_tab(t, w, &mut items),
        "screen" => screen_tab(t, w, fill_h, &mut items),
        "options" => options_tab(t, w, &mut items),
        _ => {
            if connected {
                home(t, w, &mut items)
            }
        }
    }
    let crumb = SECTIONS.iter().find(|s| s.0 == tb).map(|s| t.t(s.1)).unwrap_or_default();
    let subtitle = if tb.is_empty() { "Rexlink — notifications, messages, calls, files, clipboard, webcam and screen of your Android devices".to_string() } else { String::new() };
    Out { crumb, subtitle, items }
}

// служба, файрвол, сопряжение — над всеми вкладками
fn common(t: &Tk, w: f32, items: &mut Vec<W>) {
    let r = Rexlink::read();
    let (connected, installed) = (r.connected, r.installed);
    let fw = r.settings.get("firewall").clone();
    let pairing = r.pairing.clone();
    drop(r);
    if !connected {
        let missing = Dotfiles::read().missing_packages.clone();
        let desc = if !missing.is_empty() {
            format!("{}: {}", t.t("Install the missing packages first"), missing.join(", "))
        } else if installed {
            t.t("Start it to connect your devices (rexlink.service)")
        } else {
            t.t("Run ./install.sh from the dotfiles folder — it sets up rexlink.service")
        };
        let ctrl = if !missing.is_empty() {
            Btn::new("Install packages").primary().build(t, "ph-pkgs", dotfiles::install_packages)
        } else if installed {
            Btn::new("Start").primary().build(t, "ph-start", rl::start)
        } else {
            Btn::new("Check again").build(t, "ph-detect", rl::refresh)
        };
        items.push(bx(Card::new(0xF011C, if installed { "Rexlink service is not running" } else { "Rexlink service is not set up" }, &desc).ctrl(ctrl).build(t, w)));
    }
    // файрвол закрывает порты — устройства найдут ПК, но не подключатся
    if connected && fw.get("blocked").bool() == Some(true) {
        let tool = fw.get("tool").str_or("");
        let tw = w - 36.0 - 40.0 - if tool == "ufw" { 130.0 } else { 0.0 };
        let mut row: Vec<W> = vec![
            bx(ui::icon(t, 0xF0565, t.icon + 4.0, t.p.urgent)),
            bx(Column::new(children![
                w::line(t, &format!("{} ({tool})", t.t("The firewall blocks Rexlink")), t.fs, t.p.fg, tw, true),
                w::para(t, &t.t("Devices see the computer but can't connect. Open TCP 47820 and UDP 47821"), t.fs - 2.0, t.p.dim, tw)
            ])
            .gap(2.0)),
        ];
        if tool == "ufw" {
            row.push(bx(Btn::new("Open ports").primary().build(t, "ph-fw", rl::open_firewall)));
        }
        let rw = Row::new(row).gap(16.0).align(Center);
        let (_, rh) = w::wh(&rw);
        items.push(bx(Rectangle::new().width(w).height(rh + 28.0).radius(10.0).fill(alpha(t.p.urgent, 0.12)).border(1.0, t.p.urgent).padding(Padding { top: 14.0, right: 18.0, bottom: 14.0, left: 18.0 }).child(rw)));
    }
    // запрос сопряжения
    if !pairing.get("id").str_or("").is_empty() {
        let code = pairing.get("code").str_or("");
        let code = if code.len() == 6 { format!("{} {}", &code[..3], &code[3..]) } else { code };
        let codew = w::raw(t, code, t.fs + 8.0, t.p.fg).weight(Weight::Bold);
        let btns = Row::new(children![Btn::new("Decline").build(t, "pair-no", || rl::pair_answer(false)), Btn::new("Pair").primary().build(t, "pair-yes", || rl::pair_answer(true))]).gap(8.0);
        let (cw, _) = w::wh(&codew);
        let (bw, _) = w::wh(&btns);
        let tw = w - 32.0 - 40.0 - cw - bw - 14.0 * 3.0;
        items.push(bx(Rectangle::new().width(w).height(76.0).radius(10.0).fill(t.p.surface_hi).border(1.0, t.p.accent).padding(Padding { top: 0.0, right: 14.0, bottom: 0.0, left: 18.0 }).child(
            Row::new(children![
                ui::icon(t, 0xF0337, t.icon + 6.0, t.p.accent),
                Column::new(children![
                    w::line(t, &format!("{} {}", pairing.get("name").str_or(""), t.t("wants to pair")), t.fs, t.p.fg, tw, true),
                    w::line(t, &t.t("Check that the code matches the device"), t.fs - 2.0, t.p.dim, tw, false)
                ])
                .gap(2.0),
                codew,
                btns
            ])
            .gap(14.0)
            .height(76.0)
            .align(Center),
        )));
    }
}

// ═════════ главная
fn tile(t: &Tk, w: f32, icon: u32, value: &str, label: &str, progress: f32, tint: amane::Color, click: Option<&'static str>) -> Rectangle {
    let id = format!("ph-tile:{label}");
    let h = click.is_some() && w::hov(&id);
    let mut layers: Vec<W> = vec![bx(Rectangle::new().width(w).height(96.0).padding(14.0).child(
        Column::new(children![
            Rectangle::new().width(28.0).height(28.0).radius(14.0).fill(alpha(tint, 0.14)).align_child(Center, Center).child(ui::icon(t, icon, t.icon, tint)),
            w::gap(4.0),
            w::line(t, value, t.fs + 1.0, t.p.fg, w - 28.0, true),
            w::line(t, label, t.fs - 3.0, t.p.dim, w - 28.0, false)
        ])
        .gap(2.0),
    ))];
    if progress >= 0.0 {
        layers.push(bx(Rectangle::new().width(w).height(96.0).align_child(Start, End).padding(1.0).child(Rectangle::new().width((w - 2.0) * progress.clamp(0.0, 1.0)).height(3.0).radius(2.0).fill(tint))));
    }
    let r = Rectangle::new().width(w).height(96.0).radius(12.0).fill(if h { t.p.surface_hi } else { t.p.surface }).clip().child(Stack::new(layers));
    match click {
        Some(k) => w::clickable(r, &id, w::act(move || set_tab(PAGE, k))),
        None => r,
    }
}

fn home(t: &Tk, w: f32, items: &mut Vec<W>) {
    let r = Rexlink::read();
    let me = r.dev();
    let online = r.online();
    let st = r.settings.clone();
    let s = r.status.clone();
    let caps = r.caps.clone();
    let notifs = r.notifs.arr().len();
    let media = r.media.clone();
    let pc_media = r.pc_media.clone();
    let camera_on = r.camera.get("running").bool_or(false);
    let screen_on = r.screens.get(&r.current).get("running").bool_or(false);
    let devices = r.devices.arr().to_vec();
    let apk = r.apk.get("versionName").str_or("");
    let call = r.call.clone();
    let transfers_active = r.transfers.arr().iter().any(|x| x.get("state").str() == Some("active"));
    drop(r);
    let mraw = me.as_ref().map(|d| d.raw.clone()).unwrap_or_default();

    // обновление приложения на устройстве
    let upd = mraw.get("update").str_or("");
    if online && !upd.is_empty() {
        let updating = mraw.get("updating").bool_or(false);
        let id = mraw.get("id").str_or("");
        let av = mraw.get("appVersion").str_or("");
        items.push(bx(Card::new(0xF01DA, &format!("{}: {upd}", t.t("New app version for the device")), &format!("{}: {}", t.t("On the device"), if av.is_empty() { t.t("old version") } else { av }))
            .ctrl(Btn::new(if updating { "Updating…" } else { "Update" }).primary().enabled(!updating).build(t, "ph-upd", move || rl::update_device(&id)))
            .build(t, w)));
    }

    // ── устройство: рисунок телефона с зарядом, имя и состояние, быстрые действия
    if let Some(d) = &me {
        let iw = w - 48.0;
        let lvl = s.get("battery").num().map(|x| x as i64).unwrap_or(d.battery);
        let charging = s.get("charging").bool_or(false);
        let low = lvl >= 0 && lvl <= 15 && !charging;
        let tint = if !online { t.p.dim } else if low { t.p.urgent } else { t.p.accent };
        // телефон: корпус, «чёлка», экран с зарядом
        let (pw, ph) = if d.kind == "tablet" { (150.0, 108.0) } else if d.kind == "watch" { (92.0, 104.0) } else { (88.0, 168.0) };
        let fill_h = (ph - 22.0) * (lvl.max(0) as f32 / 100.0);
        let screen = Rectangle::new().width(pw - 12.0).height(ph - 12.0).radius(13.0).fill(t.p.surface_hi).clip().child(Stack::new(children![
            Rectangle::new().width(pw - 12.0).height(ph - 12.0).align_child(Start, End).child(Rectangle::new().width(pw - 12.0).height(fill_h).fill(alpha(tint, 0.18))),
            Rectangle::new().width(pw - 12.0).height(ph - 12.0).align_child(Center, Center).child(
                Column::new(children![
                    ui::icon(t, if charging { 0xF0084 } else { rl::battery_icon(lvl, charging) }, t.icon + 4.0, tint),
                    ui::bold(t, if lvl >= 0 && online { format!("{lvl}%") } else { "—".into() }, t.p.fg).size(t.fs + 6.0)
                ])
                .gap(2.0)
                .align(Center)
            )
        ]));
        let mut body: Vec<W> = vec![bx(screen)];
        if d.kind != "tablet" && d.kind != "watch" {
            body.push(bx(Rectangle::new().width(pw).height(ph).align_child(Center, Start).padding(Padding { top: 10.0, right: 0.0, bottom: 0.0, left: 0.0 }).child(Rectangle::new().width(22.0).height(5.0).radius(3.0).fill(t.p.surface_hi2))));
        }
        let phone = Rectangle::new().width(pw).height(ph).radius(18.0).fill(t.p.bg).border(2.0, if online { tint } else { t.p.surface_hi2 }).align_child(Center, Center).child(Stack::new(body));

        let tw = iw - pw - 24.0;
        let chip = |icon: u32, text: String, c: amane::Color| -> W {
            let l = Row::new(children![ui::icon(t, icon, t.fs - 1.0, c), ui::text(t, text, c).size(t.fs - 2.0)]).gap(6.0).align(Center);
            let (lw, _) = w::wh(&l);
            bx(Rectangle::new().width(lw + 18.0).height(24.0).radius(12.0).fill(alpha(c, 0.12)).align_child(Center, Center).child(l))
        };
        let mut chips: Vec<W> = vec![chip(0xF0765, t.t(if online { "connected" } else { "offline" }), if online { t.p.accent } else { t.p.dim })];
        if online {
            chips.push(chip(0xF033E, t.t("secure connection"), t.p.muted));
            let addr = mraw.get("address").str_or("");
            if !addr.is_empty() {
                chips.push(chip(0xF0318, addr, t.p.muted));
            }
        }
        let mut right: Vec<W> = vec![
            bx(w::line(t, &d.name, t.fs + 8.0, t.p.fg, tw - if online { 96.0 } else { 0.0 }, true)),
            bx(w::line(t, &[t.t(kind_name(&d.kind)), d.model.clone()].into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join("  ·  "), t.fs - 1.0, t.p.dim, tw, false)),
            bx(Row::new(chips).gap(6.0)),
        ];
        if !online {
            right.push(bx(w::para(t, &t.t("Offline — connects by itself once it's on the same network"), t.fs - 2.0, t.p.dim, tw)));
        }
        if online {
            // быстрые действия: плитки с иконкой
            let n = 5.0;
            let aw = ((tw - 8.0 * (n - 1.0)) / n).floor();
            let qa = |id: &'static str, icon: u32, label: &str, on: bool, f: Box<dyn Fn()>| -> W {
                let hov = w::hov(id);
                let r = Rectangle::new()
                    .width(aw)
                    .height(64.0)
                    .radius(12.0)
                    .fill(if on { t.p.accent } else if hov { t.p.surface_hi2 } else { t.p.surface_hi })
                    .align_child(Center, Center)
                    .child(Column::new(children![ui::icon(t, icon, t.icon + 2.0, if on { t.p.bg } else { t.p.fg }), Rectangle::new().width(aw - 8.0).height(16.0).align_child(Center, Center).clip().child(ui::text(t, t.t(label), if on { t.p.bg } else { t.p.muted }).size(t.fs - 3.0))]).gap(5.0).align(Center));
                bx(w::clickable(r, id, w::act(f)))
            };
            let (c1, c2, c3) = (d.id.clone(), d.id.clone(), d.id.clone());
            let ringing = mraw.get("ringing").bool_or(false);
            right.push(bx(Rectangle::new().width(tw).height(6.0)));
            right.push(bx(Row::new(vec![
                qa("ph-q-find", 0xF08D3, "Find", ringing, Box::new(move || rl::ring(&c1))),
                qa("ph-q-send", 0xF0552, "Send files", false, Box::new(pick_files)),
                qa(
                    "ph-q-screen",
                    0xF0379,
                    "Screen",
                    screen_on,
                    Box::new(move || {
                        set_tab(PAGE, "screen");
                        if !screen_on {
                            rl::screen_start(&c2);
                        }
                    }),
                ),
                qa("ph-q-cam", 0xF05A0, if camera_on { "Webcam on" } else { "Webcam" }, camera_on, Box::new(move || if camera_on { rl::camera_stop() } else { rl::camera_start(&c3) })),
                qa("ph-q-clip", 0xF014D, "Clipboard", false, Box::new(|| rl::clipboard_pull(""))),
            ])
            .gap(8.0)));
        }
        let rc = Column::new(right).gap(6.0);
        let (_, rh) = w::wh(&rc);
        let hh = rh.max(ph);
        items.push(bx(Rectangle::new()
            .width(w)
            .height(hh + 44.0)
            .radius(16.0)
            .fill(t.p.surface)
            .padding(Padding { top: 22.0, right: 24.0, bottom: 22.0, left: 24.0 })
            .child(Row::new(vec![bx(Rectangle::new().width(pw).height(hh).align_child(Center, Center).child(phone)), bx(Rectangle::new().width(tw).height(hh).align_child(Start, Center).child(rc))]).gap(24.0))));

        if online {
            // плашки состояния
            let blabel = if charging {
                t.t(match s.get("plug").str().unwrap_or("") {
                    "ac" => "Charging · mains",
                    "usb" => "Charging · USB",
                    "wireless" => "Charging · wireless",
                    _ => "Charging",
                })
            } else if let Some(temp) = s.get("temp").num().filter(|x| *x != 0.0) {
                format!("{} · {temp:.1}°C", t.t("Battery"))
            } else {
                t.t("Battery")
            };
            let net = s.get("net").str_or("");
            let (wifi, cell) = (s.get("wifi").clone(), s.get("cell").clone());
            let (nicon, nval, nlab) = match net.as_str() {
                "wifi" => (rl::wifi_icon(wifi.get("level").num_or(0.0) as i64), Some(wifi.get("ssid").str_or("")).filter(|x| !x.is_empty()).unwrap_or("Wi-Fi".into()), format!("Wi-Fi · {}/4", wifi.get("level").num_or(0.0))),
                "cell" => (
                    rl::cell_icon(cell.get("level").num_or(0.0) as i64),
                    Some(cell.get("operator").str_or("")).filter(|x| !x.is_empty()).unwrap_or_else(|| t.t("Mobile network")),
                    format!("{} · {}/4", cell.get("gen").str_or(""), cell.get("level").num_or(0.0)),
                ),
                _ => (0xF092E, t.t("No network"), t.t("Offline")),
            };
            let op = cell.get("operator").str_or("");
            let show_cell = caps.arr().iter().any(|c| c.str() == Some("calls")) || !op.is_empty();
            let n = if show_cell { 4.0 } else { 3.0 };
            let sw = ((w - 8.0 * (n - 1.0)) / n).floor();
            let mut tiles: Vec<W> = vec![
                bx(tile(t, sw, rl::battery_icon(lvl, charging), &format!("{}%", lvl.max(0)), &blabel, lvl.max(0) as f32 / 100.0, tint, None)),
                bx(tile(t, sw, nicon, &nval, &nlab, -1.0, t.p.accent, None)),
            ];
            if show_cell {
                let (v, l) = if op.is_empty() { (t.t("No SIM"), t.t("Cellular")) } else { (op.clone(), format!("{} · {}/4", cell.get("gen").str_or(""), cell.get("level").num_or(0.0))) };
                tiles.push(bx(tile(t, sw, rl::cell_icon(cell.get("level").num_or(0.0) as i64), &v, &l, -1.0, t.p.muted, None)));
            }
            tiles.push(bx(tile(t, sw, 0xF009A, &notifs.to_string(), &plural_n(t, notifs), -1.0, t.p.accent, Some("notifications"))));
            items.push(bx(Row::new(tiles).gap(8.0)));
        }
    }

    // ── медиа
    if online && media.get("active").bool_or(false) {
        let src = me.as_ref().map(|d| kind_name(&d.kind)).unwrap_or("Phone");
        items.push(bx(media_card(t, w, &media, src, true, "ph-m", |c, v| rl::media_action(c, "", v))));
    }
    if online && pc_media.get("active").bool_or(false) && st.get("pcMedia").bool() != Some(false) {
        items.push(bx(media_card(t, w, &pc_media, "Computer", false, "pc-m", |c, _| rl::pc_media_action(c))));
    }

    // ── как подключить
    if devices.is_empty() {
        let ips: Vec<String> = st.get("ips").arr().iter().filter_map(|x| x.str().map(String::from)).collect();
        let steps = [
            t.t("Install the Rexlink app on the phone, tablet or watch (the APK is below) and open it. Any number of devices works."),
            t.t("The device and the computer must be on the same network (Wi-Fi or hotspot)."),
            format!("{} «{}» {}: {}", t.t("Pick"), st.get("name").str_or(""), t.t("in the list or enter the address"), ips.join(", ")),
            t.t("Check the six-digit code on both screens and press Pair."),
        ];
        let mut c: Vec<W> = vec![bx(w::raw(t, t.t("How to connect"), t.fs + 1.0, t.p.fg).weight(Weight::Bold))];
        for (i, s) in steps.iter().enumerate() {
            c.push(bx(Row::new(children![
                Rectangle::new().width(22.0).height(22.0).radius(11.0).fill(t.p.surface_hi2).align_child(Center, Center).child(w::raw(t, (i + 1).to_string(), t.fs - 3.0, t.p.fg)),
                w::para(t, s, t.fs - 1.0, t.p.muted, w - 40.0 - 34.0)
            ])
            .gap(12.0)));
        }
        let col = Column::new(c).gap(10.0);
        let (_, ch) = w::wh(&col);
        items.push(bx(Rectangle::new().width(w).height(ch + 36.0).radius(12.0).fill(t.p.surface).padding(Padding { top: 18.0, right: 20.0, bottom: 18.0, left: 20.0 }).child(col)));
        let desc = if apk.is_empty() {
            t.t("rexlink.apk not found next to the service")
        } else {
            format!("rexlink.apk   ·   {} {apk}   ·   {}", t.t("version"), t.t("send it to the phone or install with adb install"))
        };
        let mut card = Card::new(0xF0032, "App for the device", &desc);
        if !apk.is_empty() {
            card = card.ctrl(Btn::new("Show file").icon(FOLDER).build(t, "ph-apk", show_apk));
        }
        items.push(bx(card.build(t, w)));
    }

    // ── устройства
    if !devices.is_empty() {
        items.push(bx(w::section(t, "Devices", w)));
    }
    for dj in &devices {
        let d = rl::device(dj);
        let edit_key = format!("ph-edit:{}", d.id);
        let editing = super::super::Prefs::flag(&edit_key);
        let mut ctrl: Vec<W> = Vec::new();
        let upd = dj.get("update").str_or("");
        if !editing && !upd.is_empty() && d.online {
            let updating = dj.get("updating").bool_or(false);
            let id = d.id.clone();
            let label = if updating { t.t("Updating…") } else { format!("{} {upd}", t.t("Update to")) };
            ctrl.push(bx(Btn::new(&label).enabled(!updating).build(t, &format!("dupd:{}", d.id), move || rl::update_device(&id))));
        }
        if !editing && !d.current {
            let id = d.id.clone();
            ctrl.push(bx(Btn::new("Make current").build(t, &format!("dcur:{}", d.id), move || rl::select(&id))));
        }
        if !editing && d.online {
            let id = d.id.clone();
            ctrl.push(bx(Btn::new("").icon(0xF08D3).build(t, &format!("dring:{}", d.id), move || rl::ring(&id))));
        }
        let field_id = format!("dname:{}", d.id);
        let (id1, fid1, ek1, name1) = (d.id.clone(), field_id.clone(), edit_key.clone(), d.name.clone());
        ctrl.push(bx(Btn::new("").icon(if editing { 0xF012C } else { 0xF03EB }).primary_if(editing).build(t, &format!("dedit:{}", d.id), move || {
            if super::super::Prefs::flag(&ek1) {
                rl::rename(&id1, &w::field_text(&fid1));
                super::super::Prefs::set(&ek1, "");
            } else {
                w::set_field(&fid1, &name1);
                super::super::Prefs::set(&ek1, "1");
            }
        })));
        if !editing {
            let id = d.id.clone();
            ctrl.push(bx(Btn::new("").icon(ic::TRASH).danger().build(t, &format!("dforget:{}", d.id), move || rl::forget(&id))));
        }
        let crow = Row::new(ctrl).gap(6.0).align(Center);
        let (cw, _) = w::wh(&crow);
        let tw = w - 30.0 - t.icon - 6.0 - cw - 14.0 * 2.0;
        let mid: W = if editing {
            let (id2, ek2) = (d.id.clone(), edit_key.clone());
            bx(w::field(t, &field_id, tw, "", 0, move |v| {
                rl::rename(&id2, &v);
                super::super::Prefs::set(&ek2, "");
            }))
        } else {
            let title = format!("{}{}", d.name, if d.current { format!("   ·   {}", t.t("current")) } else { String::new() });
            let bat = if d.battery >= 0 { format!("{}%{}", d.battery, if d.charging { " ⚡" } else { "" }) } else { String::new() };
            let av = dj.get("appVersion").str_or("");
            let desc = [t.t(kind_name(&d.kind)), d.model.clone(), t.t(if d.online { "online" } else { "offline" }), bat, if av.is_empty() { String::new() } else { format!("Rexlink {av}") }]
                .into_iter()
                .filter(|x| !x.is_empty())
                .collect::<Vec<_>>()
                .join("  ·  ");
            bx(Column::new(children![w::line(t, &title, t.fs, t.p.fg, tw, d.current), w::line(t, &desc, t.fs - 2.0, t.p.dim, tw, false)]).gap(2.0))
        };
        let mut r = Rectangle::new().width(w).height(64.0).radius(10.0).fill(t.p.surface).padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 18.0 });
        if d.current {
            r = r.border(1.0, t.p.accent);
        }
        items.push(bx(r.child(Row::new(vec![bx(ui::icon(t, rl::kind_icon(&d.kind), t.icon + 6.0, if d.online { t.p.accent } else { t.p.dim })), mid, bx(crow)]).gap(14.0).height(64.0).align(Center))));
    }

    // ── разделы: плитки в две колонки
    items.push(bx(w::section(t, "Features", w)));
    let ringing = call.get("state").str() == Some("ringing");
    let clip_on = st.get("clipboard").bool_or(true);
    let cw = w::width_for(2, w, 8.0);
    let mut tiles: Vec<W> = Vec::new();
    for (key, label, icon) in SECTIONS {
        let desc = match key {
            "notifications" => if notifs > 0 { format!("{notifs} {}", plural_n(t, notifs)) } else { t.t("No notifications") },
            "messages" => t.t("SMS: conversations, replies, new messages"),
            "calls" => {
                if ringing {
                    let who = Some(call.get("name").str_or("")).filter(|x| !x.is_empty()).unwrap_or_else(|| call.get("number").str_or(""));
                    format!("{}: {who}", t.t("Incoming"))
                } else {
                    t.t("Answer and decline, dial a number")
                }
            }
            "files" => t.t(if transfers_active { "Transferring…" } else { "Send files to the device and receive them from it" }),
            "clipboard" => t.t(if clip_on { "Shared   ·   text and images both ways" } else { "Off" }),
            "camera" => t.t(if camera_on { "On" } else { "The device camera as a webcam for calls and OBS" }),
            "screen" => t.t(if screen_on { "Showing" } else { "See and control the device screen with mouse and keyboard" }),
            _ => t.t("Sync, screen quality, files folder, bar, screencast"),
        };
        tiles.push(bx(w::tile(t, &format!("ph-sec:{key}"), cw, icon, label, &desc, move || set_tab(PAGE, key))));
    }
    items.push(bx(w::grid(tiles, 2, 8.0)));
}

// плеер: обложка, название, позиция, кнопки (телефон — с перемоткой, ПК — без)
fn media_card(t: &Tk, w: f32, m: &Json, source: &str, seekable: bool, id: &'static str, cmd: fn(&str, f64)) -> Rectangle {
    let len = m.get("len").num_or(0.0);
    let playing = m.get("playing").bool_or(false);
    let at = m.get("at").num_or(0.0);
    let pos = if len > 0.0 { (m.get("pos").num_or(0.0) + if playing && at > 0.0 { now_ms() - at } else { 0.0 }).min(len) } else { 0.0 };
    if playing {
        amane::request_frame();
    }
    let art = file_path(&m.get("art").str_or(""));
    let cover = Rectangle::new().width(68.0).height(68.0).radius(8.0).fill(t.p.surface_hi).clip().align_child(Center, Center);
    let cover = if art.is_empty() { cover.child(ui::icon(t, 0xF075A, t.icon, t.p.dim)) } else { cover.fill(Image::cover(art).thumbnail(136, 136)) };
    let btns = Row::new(children![
        Btn::new("").icon(0xF04AE).build(t, &format!("{id}-prev"), move || cmd("prev", 0.0)),
        Btn::new("").icon(if playing { 0xF03E4 } else { 0xF040A }).primary().build(t, &format!("{id}-play"), move || cmd("toggle", 0.0)),
        Btn::new("").icon(0xF04AD).build(t, &format!("{id}-next"), move || cmd("next", 0.0))
    ])
    .gap(6.0);
    let (bw, _) = w::wh(&btns);
    let tw = w - 28.0 - 68.0 - bw - 32.0;
    let app = m.get("app").str_or("");
    let mut col: Vec<W> = vec![
        bx(w::line(t, &format!("{}{}", t.t(source), if app.is_empty() { String::new() } else { format!("   ·   {app}") }), t.fs - 3.0, t.p.dim, tw, false)),
        bx(w::line(t, &Some(m.get("title").str_or("")).filter(|x| !x.is_empty()).unwrap_or_else(|| t.t("Nothing playing")), t.fs, t.p.fg, tw, true)),
    ];
    let sub = [m.get("artist").str_or(""), m.get("album").str_or("")].into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join(" — ");
    if !sub.is_empty() {
        col.push(bx(w::line(t, &sub, t.fs - 2.0, t.p.muted, tw, false)));
    }
    if seekable && len > 0.0 {
        let l1 = w::raw(t, rl::duration(pos), t.fs - 3.0, t.p.dim);
        let l2 = w::raw(t, rl::duration(len), t.fs - 3.0, t.p.dim);
        let barw = tw - w::wh(&l1).0 - w::wh(&l2).0 - 16.0;
        static SEEK_X: Mutex<f32> = Mutex::new(0.0);
        let bar = Rectangle::new()
            .width(barw)
            .height(16.0)
            .align_child(Start, Center)
            .cursor(amane::Pointer)
            .on_move(|p| *SEEK_X.lock().unwrap() = p.x)
            .on_click(move |_| {
                let x = *SEEK_X.lock().unwrap();
                cmd("seek", (len * (x / barw).clamp(0.0, 1.0) as f64).round());
            })
            .child(Rectangle::new().width(barw).height(4.0).radius(2.0).fill(t.p.surface_hi2).child(Rectangle::new().width(barw * (pos / len) as f32).height(4.0).radius(2.0).fill(t.p.accent)));
        col.push(bx(Row::new(children![l1, bar, l2]).gap(8.0).align(Center)));
    }
    Rectangle::new()
        .width(w)
        .height(96.0)
        .radius(10.0)
        .fill(t.p.surface)
        .padding(14.0)
        .child(Row::new(children![cover, Column::new(col).gap(3.0).width(tw), btns]).gap(16.0).height(68.0).align(Center))
}

// ═════════ уведомления
fn notif_card(t: &Tk, w: f32, n: &Json) -> Rectangle {
    let key = n.get("key").str_or("");
    let dev = n.get("device").str_or("");
    let reply_key = format!("ph-reply:{key}");
    let replying = super::super::Prefs::get(&reply_key);
    let iw = w - 32.0;
    let icon = file_path(&n.get("icon").str_or(""));
    let ibox = Rectangle::new().width(34.0).height(34.0).radius(9.0).fill(t.p.surface_hi).align_child(Center, Center).clip();
    let ibox = if icon.is_empty() { ibox.child(ui::icon(t, 0xF009A, t.icon, t.p.dim)) } else { ibox.child(Rectangle::new().width(22.0).height(22.0).fill(Image::contain(icon))) };
    let clearable = n.get("clearable").bool() != Some(false);
    let tw = iw - 34.0 - 14.0 - if clearable { 50.0 } else { 0.0 };
    let mut text: Vec<W> = vec![bx(w::raw(t, format!("{}   {}", n.get("app").str_or(""), ago_t(t, n.get("time").num_or(0.0))), t.fs - 3.0, t.p.dim))];
    let title = n.get("title").str_or("");
    if !title.is_empty() {
        text.push(bx(w::line(t, &title, t.fs - 1.0, t.p.fg, tw, true)));
    }
    let body = n.get("text").str_or("");
    if !body.is_empty() {
        let lines: Vec<&str> = body.lines().take(4).collect();
        text.push(bx(w::para(t, &lines.join("\n"), t.fs - 2.0, t.p.muted, tw)));
    }
    let mut top: Vec<W> = vec![bx(ibox), bx(Column::new(text).gap(2.0).width(tw))];
    if clearable {
        let (k, d) = (key.clone(), dev.clone());
        top.push(bx(Btn::new("").icon(ic::CLOSE).build(t, &format!("nx:{key}"), move || rl::notif_dismiss(&k, &d))));
    }
    let mut col: Vec<W> = vec![bx(Row::new(top).gap(14.0))];
    let actions = n.get("actions").arr().to_vec();
    if replying.is_empty() && !actions.is_empty() {
        let mut row: Vec<W> = Vec::new();
        for a in &actions {
            let i = a.get("i").num_or(0.0) as i64;
            let (k, d, rk) = (key.clone(), dev.clone(), reply_key.clone());
            let reply = a.get("reply").bool_or(false);
            let mut b = Btn::new(Box::leak(a.get("title").str_or("").into_boxed_str()));
            if reply {
                b = b.icon(0xF045A);
            }
            row.push(bx(b.build(t, &format!("na:{key}:{i}"), move || {
                if reply {
                    super::super::Prefs::set(&rk, &i.to_string());
                } else {
                    rl::notif_action(&k, i, &d)
                }
            })));
        }
        col.push(bx(Rectangle::new().width(iw).height(36.0).padding(Padding { top: 0.0, right: 0.0, bottom: 0.0, left: 48.0 }).child(Row::new(row).gap(6.0))));
    }
    if !replying.is_empty() {
        let i: i64 = replying.parse().unwrap_or(0);
        let fid = format!("nr:{key}");
        let send = {
            let (k, d, rk, fid) = (key.clone(), dev.clone(), reply_key.clone(), fid.clone());
            move |v: String| {
                if !v.trim().is_empty() {
                    rl::notif_reply(&k, i, &v, &d);
                }
                w::set_field(&fid, "");
                super::super::Prefs::set(&rk, "");
            }
        };
        let s2 = send.clone();
        let f2 = fid.clone();
        let rk = reply_key.clone();
        col.push(bx(Rectangle::new().width(iw).height(38.0).padding(Padding { top: 0.0, right: 0.0, bottom: 0.0, left: 48.0 }).child(
            Row::new(children![
                w::field(t, &fid, iw - 48.0 - 100.0, "Reply…", 0xF045A, send),
                Btn::new("").icon(0xF048A).primary().build(t, &format!("ns:{key}"), move || s2(w::field_text(&f2))),
                Btn::new("").icon(ic::CLOSE).build(t, &format!("nc:{key}"), move || super::super::Prefs::set(&rk, ""))
            ])
            .gap(6.0)
            .align(Center),
        )));
    }
    let c = Column::new(col).gap(8.0);
    let (_, ch) = w::wh(&c);
    Rectangle::new().width(w).height(ch + 28.0).radius(10.0).fill(t.p.surface).padding(Padding { top: 14.0, right: 16.0, bottom: 14.0, left: 16.0 }).child(c)
}

fn notifs_tab(t: &Tk, w: f32, items: &mut Vec<W>) {
    let r = Rexlink::read();
    let list = r.notifs.arr().to_vec();
    let online = r.online();
    let name = r.dev().map(|d| d.name).unwrap_or_default();
    drop(r);
    let head = if !online {
        t.t("The device is not connected")
    } else if !list.is_empty() {
        format!("{} {}   ·   {name}", list.len(), plural_n(t, list.len()))
    } else {
        String::new()
    };
    let mut row: Vec<W> = vec![bx(Rectangle::new().width(w - 140.0).height(36.0).align_child(Start, Center).child(w::raw(t, head, t.fs - 1.0, t.p.dim)))];
    if list.iter().any(|n| n.get("clearable").bool() != Some(false)) {
        row.push(bx(Rectangle::new().width(140.0).height(36.0).align_child(End, Center).child(Btn::new("Clear all").icon(ic::TRASH).build(t, "n-clear", rl::notif_dismiss_all))));
    }
    items.push(bx(Row::new(row)));
    if list.is_empty() {
        items.push(bx(empty(t, w, 0xF009B, "No notifications", "The Rexlink app on the device needs notification access")));
    }
    for n in &list {
        items.push(bx(notif_card(t, w, n)));
    }
    items.push(bx(w::gap(10.0)));
    items.push(bx(Card::new(0xF0379, "Show them on the desktop", "As regular pop-up notifications, with actions and quick reply").ctrl(sw_rl(t, "n-mirror", "mirrorToDesktop", true)).build(t, w)));
}

// ═════════ сообщения: слева разговоры, справа переписка
fn avatar(t: &Tk, name: &str) -> Rectangle {
    Rectangle::new().width(38.0).height(38.0).radius(19.0).fill(t.p.surface_hi2).align_child(Center, Center).child(w::raw(t, rl::initials(name), t.fs - 1.0, t.p.fg).weight(Weight::Bold))
}

static MSG_OFF: Mutex<f32> = Mutex::new(0.0);

fn messages_tab(t: &Tk, w: f32, h: f32, items: &mut Vec<W>) {
    // при открытии вкладки (и смене устройства) — свежий список
    static SEEN: Mutex<String> = Mutex::new(String::new());
    let r = Rexlink::read();
    let online = r.online();
    let key = format!("{}|{online}", r.current);
    let sms = r.sms.clone();
    drop(r);
    {
        let mut s = SEEN.lock().unwrap();
        if *s != key {
            *s = key;
            if online {
                std::thread::spawn(rl::sms_refresh);
            }
        }
    }
    let thread = sms.get("thread").clone();
    let opened = !thread.get("id").is_null();
    let q = w::field_text("sms-search").to_lowercase();

    // ── разговоры
    let lw = 300.0;
    let head = Row::new(children![
        w::field(t, "sms-search", lw - 2.0 * 46.0, "Search", ic::SEARCH, |_| {}),
        Btn::new("").icon(0xF0450).enabled(online).build(t, "sms-refresh", rl::sms_refresh),
        Btn::new("").icon(0xF0415).primary().enabled(online).build(t, "sms-new", || rl::sms_open(""))
    ])
    .gap(6.0)
    .align(Center);
    let tid = thread.get("id").clone();
    let mut rows: Vec<W> = Vec::new();
    for th in sms.get("threads").arr() {
        let name = Some(th.get("name").str_or("")).filter(|x| !x.is_empty()).unwrap_or_else(|| th.get("address").str_or(""));
        let hay = format!("{} {} {}", th.get("name").str_or(""), th.get("address").str_or(""), th.get("snippet").str_or("")).to_lowercase();
        if !q.is_empty() && !hay.contains(&q) {
            continue;
        }
        let id = th.get("id").clone();
        let sel = crate::json::Json::Str(format!("{}", json_id(&tid))) == crate::json::Json::Str(json_id(&id));
        let hid = format!("sms-th:{}", json_id(&id));
        let hv = w::hov(&hid);
        let unread = th.get("unread").num_or(0.0) > 0.0;
        let when = w::raw(t, ago_t(t, th.get("date").num_or(0.0)), t.fs - 4.0, t.p.dim);
        let (ww, _) = w::wh(&when);
        let tw = lw - 20.0 - 38.0 - 12.0;
        let mut snip: Vec<W> = vec![bx(w::line(t, &th.get("snippet").str_or("").replace('\n', " "), t.fs - 3.0, t.p.dim, tw - if unread { 14.0 } else { 0.0 }, false))];
        if unread {
            snip.push(bx(Rectangle::new().width(8.0).height(8.0).radius(4.0).fill(t.p.accent)));
        }
        let r = Rectangle::new()
            .width(lw)
            .height(62.0)
            .radius(10.0)
            .fill(if sel { t.p.surface_hi } else if hv { t.p.surface } else { alpha(t.p.surface, 0.0) })
            .padding(Padding { top: 0.0, right: 10.0, bottom: 0.0, left: 10.0 })
            .child(
                Row::new(children![
                    avatar(t, &name),
                    Column::new(children![
                        Row::new(children![w::line(t, &name, t.fs - 1.0, t.p.fg, tw - ww - 6.0, unread), when]).gap(6.0).align(Center),
                        Row::new(snip).gap(6.0).align(Center)
                    ])
                    .gap(2.0)
                ])
                .gap(12.0)
                .height(62.0)
                .align(Center),
            );
        let open = json_id(&id);
        rows.push(bx(w::clickable(r, &hid, w::act(move || rl::sms_open(&open)))));
    }
    let list_h = h - 46.0;
    let list: W = if rows.is_empty() {
        bx(Rectangle::new().width(lw).height(list_h).align_child(Center, Center).child(empty(
            t,
            lw - 20.0,
            0xF0369,
            if online { "No messages" } else { "The device is not connected" },
            if online { "The app on the phone needs SMS access" } else { "" },
        )))
    } else {
        bx(ScrollArea::new(w::sid("sms-threads"), Column::new(rows).gap(2.0)).width(lw).height(list_h))
    };
    let left = Column::new(vec![bx(head), list]).gap(8.0).width(lw);

    // ── переписка
    let rw = w - lw - 12.0;
    let iw = rw - 32.0;
    let right: Rectangle = if !opened {
        Rectangle::new().width(rw).height(h).radius(12.0).fill(t.p.surface).align_child(Center, Center).child(empty(t, iw, 0xF0369, "Pick a conversation", ""))
    } else {
        let is_new = thread.get("new").bool_or(false);
        let addr = thread.get("address").str_or("");
        let tname = thread.get("name").str_or("");
        let mut col: Vec<W> = Vec::new();
        if !is_new {
            let mut hdr: Vec<W> = vec![bx(avatar(t, if tname.is_empty() { &addr } else { &tname }))];
            let mut c: Vec<W> = vec![bx(w::line(t, if tname.is_empty() { &addr } else { &tname }, t.fs, t.p.fg, iw - 38.0 - 60.0 - 24.0, true))];
            if !tname.is_empty() && !addr.is_empty() {
                c.push(bx(w::raw(t, addr.clone(), t.fs - 2.0, t.p.dim)));
            }
            hdr.push(bx(Column::new(c).width(iw - 38.0 - 60.0 - 24.0)));
            if !addr.is_empty() {
                let a = addr.clone();
                hdr.push(bx(Btn::new("").icon(0xF03F2).build(t, "sms-dial", move || rl::dial(&a))));
            }
            col.push(bx(Row::new(hdr).gap(12.0).height(40.0).align(Center)));
        } else {
            col.push(bx(w::field(t, "sms-to", iw, "Phone number", 0xF03F2, |_| {})));
        }
        col.push(bx(Rectangle::new().width(iw).height(1.0).fill(t.p.surface_hi2)));
        // пузыри; прокрутка своя — снизу вверх (новые внизу)
        let bub_max = iw * 0.72;
        let mut bubs: Vec<W> = Vec::new();
        for m in sms.get("messages").arr() {
            let mine = m.get("type").num_or(1.0) as i64 != 1;
            let typ = m.get("type").num_or(1.0) as i64;
            let body = m.get("body").str_or("");
            let one = w::raw(t, body.clone(), t.fs - 1.0, if mine { t.p.bg } else { t.p.fg });
            let (ow, _) = w::wh(&one);
            let status = match typ {
                5 => format!("   ·   {}", t.t("error")),
                4 | 6 => format!("   ·   {}", t.t("sending…")),
                _ => String::new(),
            };
            let time = w::raw(t, format!("{}{status}", ago_t(t, m.get("date").num_or(0.0))), t.fs - 4.0, if mine { alpha(t.p.bg, 0.7) } else { t.p.dim });
            let (tw, _) = w::wh(&time);
            let text: W = if ow <= bub_max - 28.0 && !body.contains('\n') { bx(one) } else { bx(w::para(t, &body, t.fs - 1.0, if mine { t.p.bg } else { t.p.fg }, bub_max - 28.0)) };
            let (bw, bh) = w::wh(text.as_ref());
            let width = bub_max.min(bw.max(tw) + 28.0);
            let b = Rectangle::new()
                .width(width)
                .height(bh + 22.0 + 14.0)
                .radius(12.0)
                .fill(if mine { t.p.accent } else { t.p.surface_hi2 })
                .padding(Padding { top: 10.0, right: 12.0, bottom: 8.0, left: 14.0 })
                .child(Column::new(vec![text, bx(Rectangle::new().width(width - 26.0).height(14.0).align_child(End, Center).child(time))]).gap(3.0));
            let line = Rectangle::new().width(iw).height(bh + 36.0 + 4.0);
            bubs.push(bx(if mine { line.align_child(End, Start).child(b) } else { line.child(b) }));
        }
        let msgs = Column::new(bubs).gap(6.0);
        let (_, total) = w::wh(&msgs);
        let fixed = 40.0 + 1.0 + 38.0 + 10.0 * 3.0;
        let view_h = (h - 32.0 - fixed).max(100.0);
        let max_off = (total - view_h).max(0.0);
        let off = MSG_OFF.lock().unwrap().clamp(0.0, max_off);
        let y = if total <= view_h { view_h - total } else { -(max_off - off) };
        col.push(bx(Rectangle::new()
            .width(iw)
            .height(view_h)
            .clip()
            .on_scroll(move |s| {
                let mut o = MSG_OFF.lock().unwrap();
                *o = (*o - s.y * 40.0).clamp(0.0, max_off);
                amane::request_frame();
            })
            .child(Rectangle::new().width(iw).height(total.max(1.0)).translate(0.0, y).child(msgs))));
        let send = move |v: String| {
            let to = if is_new { w::field_text("sms-to").trim().to_string() } else { addr.clone() };
            if v.trim().is_empty() || to.is_empty() {
                return;
            }
            rl::sms_send(&to, &v);
            w::set_field("sms-body", "");
            *MSG_OFF.lock().unwrap() = 0.0;
        };
        let s2 = send.clone();
        col.push(bx(Row::new(children![
            w::field(t, "sms-body", iw - 54.0, "SMS… (Enter — send)", 0, send),
            Btn::new("").icon(0xF048A).primary().build(t, "sms-send", move || s2(w::field_text("sms-body")))
        ])
        .gap(8.0)
        .align(Center)));
        Rectangle::new().width(rw).height(h).radius(12.0).fill(t.p.surface).padding(16.0).child(Column::new(col).gap(10.0))
    };
    items.push(bx(Row::new(children![left, right]).gap(12.0)));
}

fn json_id(j: &Json) -> String {
    match j {
        Json::Str(s) => s.clone(),
        Json::Num(n) => format!("{}", *n as i64),
        _ => String::new(),
    }
}

// ═════════ звонки
fn calls_tab(t: &Tk, w: f32, items: &mut Vec<W>) {
    let r = Rexlink::read();
    let c = r.call.clone();
    let online = r.online();
    drop(r);
    let state = c.get("state").str_or("");
    let (name, number) = (c.get("name").str_or(""), c.get("number").str_or(""));
    let who = if name.is_empty() { number.clone() } else { name.clone() };
    let title = match state.as_str() {
        "ringing" => format!("{}: {who}", t.t("Incoming")),
        "offhook" => format!("{}{}", t.t("Call"), if number.is_empty() { String::new() } else { format!(": {who}") }),
        _ => t.t("No active calls"),
    };
    let desc = if state == "ringing" && !name.is_empty() { number.clone() } else { t.t("Talk on the phone or a connected headset") };
    let mut ctrl: Vec<W> = Vec::new();
    if state == "ringing" {
        ctrl.push(bx(Btn::new("Silence").build(t, "call-silence", || rl::call_action("silence"))));
    }
    if state == "ringing" || state == "offhook" {
        ctrl.push(bx(Btn::new(if state == "ringing" { "Decline" } else { "Hang up" }).danger().build(t, "call-reject", || rl::call_action("reject"))));
    }
    if state == "ringing" {
        ctrl.push(bx(Btn::new("Answer").primary().build(t, "call-accept", || rl::call_action("accept"))));
    }
    items.push(bx(Card::new(0xF03F2, &title, &desc).ctrl(Row::new(ctrl).gap(8.0).align(Center)).build(t, w)));
    items.push(bx(w::section(t, "Dial a number", w)));
    let num = w::field_text("call-number");
    items.push(bx(Row::new(children![
        w::field(t, "call-number", w - 110.0, "+7 900 000-00-00", 0xF03F2, move |v| if online && !v.trim().is_empty() { rl::dial(v.trim()) }),
        Btn::new("Dial").icon(0xF03F2).primary().enabled(online && !num.trim().is_empty()).build(t, "call-dial", || rl::dial(w::field_text("call-number").trim()))
    ])
    .gap(8.0)
    .align(Center)));
    items.push(bx(w::gap(4.0)));
    items.push(bx(w::para(t, &t.t("The call starts on the phone. Answering and declining need the Phone permission in the app on the phone."), t.fs - 2.0, t.p.dim, w)));
    items.push(bx(w::section(t, "Notifications", w)));
    items.push(bx(Card::new(0xF03F2, "Incoming call card", "Answer or decline calls from the desktop").ctrl(sw_shell(t, "phoneCalls", true)).build(t, w)));
    items.push(bx(Card::new(0xF009A, "Calls", "Notifications about incoming and missed calls").id("calls-notif").ctrl(sw_rl(t, "c-calls", "calls", true)).build(t, w)));
}

// ═════════ файлы
fn files_tab(t: &Tk, w: f32, items: &mut Vec<W>) {
    let r = Rexlink::read();
    let dir = r.settings.get("downloadDirResolved").str_or("");
    let transfers = r.transfers.arr().to_vec();
    let online = r.online();
    drop(r);
    let ru = t.c.ru();
    let btns = Row::new(children![
        Btn::new("Folder").icon(FOLDER).build(t, "f-folder", {
            let d = dir.clone();
            move || amane::spawn(&format!("xdg-open {}", crate::niri::sh_quote(if d.is_empty() { "." } else { &d })))
        }),
        Btn::new("Send").icon(0xF0552).primary().enabled(online).build(t, "f-send", pick_files)
    ])
    .gap(8.0);
    let (bw, _) = w::wh(&btns);
    // файлы можно бросить сюда
    items.push(bx(Rectangle::new()
        .width(w)
        .height(40.0)
        .on_drop(|paths| {
            let p: Vec<String> = paths.iter().map(|x| x.to_string_lossy().to_string()).collect();
            if !p.is_empty() {
                rl::send_files(&p, "");
            }
        })
        .child(Row::new(children![w::para(t, &t.t("Drop files on this page or pick them. On the device: Share → Rexlink."), t.fs - 1.0, t.p.dim, w - bw - 8.0), btns]).gap(8.0).align(Center))));
    if transfers.is_empty() {
        items.push(bx(empty(t, w, 0xF0256, "No transfers yet", &format!("{} {dir}", t.t("Received files are saved to")))));
    }
    for tr in &transfers {
        let st = tr.get("state").str_or("");
        let active = st == "active";
        let incoming = tr.get("dir").str() == Some("in");
        let openable = st == "done" && incoming;
        let (done, size) = (tr.get("done").num_or(0.0), tr.get("size").num_or(0.0));
        let info = if active {
            format!("{} / {}   ·   {}{}", rl::bytes(done, ru), rl::bytes(size, ru), rl::bytes(tr.get("speed").num_or(0.0), ru), if ru { "/с" } else { "/s" })
        } else {
            let s = match st.as_str() {
                "done" => if incoming { "Received" } else { "Sent" },
                "error" => "Error",
                "cancelled" => "Cancelled",
                _ => "",
            };
            format!("{}{}", t.t(s), if st == "done" { format!("   ·   {}", rl::bytes(size, ru)) } else { String::new() })
        };
        let fid = tr.get("fid").str_or("");
        let path = tr.get("path").str_or("");
        let mut ctrl: Vec<W> = Vec::new();
        if active {
            let f = fid.clone();
            ctrl.push(bx(Btn::new("").icon(ic::CLOSE).build(t, &format!("tx:{fid}"), move || rl::transfer_cancel(&f))));
        }
        if openable {
            let parent = path.rsplit_once('/').map(|x| x.0.to_string()).unwrap_or_default();
            ctrl.push(bx(Btn::new("").icon(FOLDER).build(t, &format!("td:{fid}"), move || amane::spawn(&format!("xdg-open {}", crate::niri::sh_quote(&parent))))));
        }
        let crow = Row::new(ctrl).gap(6.0);
        let (cw, _) = w::wh(&crow);
        let iw = w - 32.0 - t.icon - 4.0 - cw - 32.0;
        let il = w::raw(t, info, t.fs - 3.0, t.p.dim);
        let (ilw, _) = w::wh(&il);
        let frac = if size > 0.0 { (done / size).min(1.0) } else if st == "done" { 1.0 } else { 0.0 } as f64;
        let col = st.as_str();
        let barc = if col == "error" { t.p.urgent } else if col == "done" { t.p.accent } else { t.p.accent };
        let hid = format!("tr:{fid}");
        let hv = openable && w::hov(&hid);
        let r = Rectangle::new().width(w).height(70.0).radius(10.0).fill(if hv { t.p.surface_hi } else { t.p.surface }).padding(Padding { top: 0.0, right: 14.0, bottom: 0.0, left: 18.0 }).child(
            Row::new(children![
                ui::icon(t, if incoming { 0xF01DA } else { 0xF0552 }, t.icon + 4.0, t.p.fg),
                Column::new(children![
                    Row::new(children![w::line(t, &tr.get("name").str_or(""), t.fs - 1.0, t.p.fg, iw - ilw - 8.0, false), il]).gap(8.0).align(Center),
                    Rectangle::new().width(iw).height(4.0).radius(2.0).fill(t.p.surface_hi2).child(Rectangle::new().width(iw * frac as f32).height(4.0).radius(2.0).fill(barc))
                ])
                .gap(6.0),
                crow
            ])
            .gap(16.0)
            .height(70.0)
            .align(Center),
        );
        items.push(bx(if openable {
            let p = path.clone();
            w::clickable(r, &hid, w::act(move || amane::spawn(&format!("xdg-open {}", crate::niri::sh_quote(&p)))))
        } else {
            r
        }));
    }
    if transfers.iter().any(|x| x.get("state").str() != Some("active")) {
        items.push(bx(w::gap(4.0)));
        items.push(bx(Btn::new("Clear the list").build(t, "f-clear", rl::transfers_clear)));
    }
    items.push(bx(w::section(t, "Received files", w)));
    items.push(bx(Card::new(FOLDER, "Save to", &dir)
        .ctrl(w::field(t, "f-dir", 260.0, "~/Downloads/Rexlink", 0, |v| {
            let v = v.trim().to_string();
            let p = match v.strip_prefix('~') {
                Some(rest) if rest.is_empty() || rest.starts_with('/') => format!("{}{rest}", settings::home().to_string_lossy()),
                _ => v,
            };
            if !p.is_empty() {
                rl::set_download_dir(&p);
            }
            w::set_field("f-dir", "");
        }))
        .build(t, w)));
}

// ═════════ буфер обмена
fn clipboard_tab(t: &Tk, w: f32, items: &mut Vec<W>) {
    let r = Rexlink::read();
    let st = r.settings.clone();
    let clips = r.clips.arr().to_vec();
    let online = r.online();
    drop(r);
    let need_wl = st.get("wlClipboard").bool() == Some(false);
    items.push(bx(Card::new(0xF014D, "Shared clipboard", if need_wl { "Needs the wl-clipboard package" } else { "Copy on one device — paste on the other. Repeats aren't sent back" })
        .ctrl(sw_rl(t, "cl-on", "clipboard", true))
        .build(t, w)));
    items.push(bx(Card::new(0xF02E9, "Images", "Also sync screenshots and copied pictures (up to 25 MB)").ctrl(sw_rl(t, "cl-img", "clipboardImages", true)).build(t, w)));
    let mut btns: Vec<W> = vec![bx(Btn::new("Get from the device").icon(0xF01DA).enabled(online).build(t, "cl-pull", || rl::clipboard_pull("")))];
    if !clips.is_empty() {
        btns.push(bx(Btn::new("Clear").icon(ic::TRASH).build(t, "cl-clear", rl::clipboard_clear)));
    }
    let br = Row::new(btns).gap(8.0);
    let (bw, _) = w::wh(&br);
    items.push(bx(Row::new(children![w::section(t, "History", w - bw - 8.0), Rectangle::new().width(bw).height(54.0).align_child(End, End).child(br)]).gap(8.0).align(End)));
    if clips.is_empty() {
        items.push(bx(empty(
            t,
            w,
            0xF014D,
            "Nothing synced yet",
            "Android 10+ doesn't let apps read the clipboard in the background: turn on the Rexlink accessibility service on the phone, then copied text is sent by itself.",
        )));
    }
    for c in &clips {
        let incoming = c.get("dir").str() == Some("in");
        let dev = c.get("device").str_or("");
        let meta = w::raw(t, format!("{} {}   ·   {}", t.t(if incoming { "from" } else { "to" }), if dev.is_empty() { t.t("devices") } else { dev }, c.get("time").str_or("")), t.fs - 3.0, t.p.dim);
        let (mw, _) = w::wh(&meta);
        let bw = w - 34.0 - t.icon - 16.0 * 2.0 - mw;
        let body: W = if c.get("kind").str() == Some("image") {
            let p = file_path(&c.get("url").str_or(""));
            bx(Rectangle::new().width(bw).height(160.0).align_child(Start, Center).child(Rectangle::new().width(bw.min(284.0)).height(160.0).radius(6.0).clip().fill(Image::contain(p))))
        } else {
            let text: String = c.get("text").str_or("").lines().take(4).collect::<Vec<_>>().join("\n");
            bx(w::para(t, &text, t.fs - 1.0, t.p.fg, bw))
        };
        let (_, bh) = w::wh(body.as_ref());
        let h = (bh + 28.0).max(56.0);
        items.push(bx(Rectangle::new().width(w).height(h).radius(10.0).fill(t.p.surface).padding(Padding { top: 14.0, right: 16.0, bottom: 14.0, left: 18.0 }).child(
            Row::new(vec![bx(ui::icon(t, if incoming { 0xF01DA } else { 0xF0552 }, t.icon + 2.0, t.p.dim)), body, bx(meta)]).gap(16.0),
        )));
    }
}

// ═════════ веб-камера
fn camera_tab(t: &Tk, w: f32, items: &mut Vec<W>) {
    let r = Rexlink::read();
    let c = r.camera.clone();
    let cam = r.settings.get("camera").clone();
    let vdev = r.settings.get("webcamResolved").str_or("");
    let ffmpeg = r.settings.get("ffmpeg").bool() != Some(false);
    let online = r.online();
    let fr = r.frames.get("camera").clone();
    drop(r);
    let running = c.get("running").bool_or(false);
    let btn = Btn::new(if running { "Stop" } else { "Turn on" }).icon(if running { 0xF04DB } else { 0xF05A0 }).primary_if(!running).enabled(online && ffmpeg);
    let btn = if running { btn.danger() } else { btn };
    let b = btn.build(t, "cam-toggle", move || if running { rl::camera_stop() } else { rl::camera_start("") });
    let (bw, _) = w::wh(&b);
    items.push(bx(Row::new(children![w::para(t, &t.t("Works in OBS, browsers, Telegram and Zoom — pick “Rexlink Camera” there."), t.fs - 1.0, t.p.dim, w - bw - 8.0), b]).gap(8.0).align(Center)));
    // превью
    let ph = (w * 9.0 / 16.0).min(380.0);
    let img = if running { frame("camera", &fr) } else { None };
    let mut layers: Vec<W> = Vec::new();
    match &img {
        Some(p) => {
            layers.push(bx(Rectangle::new().width(w - 12.0).height(ph - 12.0).translate(6.0, 6.0).radius(8.0).clip().fill(Image::contain(p.clone()))));
            let res = format!("{}×{}", c.get("w").num().or(fr.get("w").num()).unwrap_or(0.0), c.get("h").num().or(fr.get("h").num()).unwrap_or(0.0));
            let l = w::raw(t, res, t.fs - 2.0, amane::Color::rgb(255, 255, 255));
            let (lw, _) = w::wh(&l);
            layers.push(bx(Rectangle::new()
                .width(lw + 32.0)
                .height(26.0)
                .radius(13.0)
                .fill(amane::Color::rgba(0, 0, 0, 140))
                .translate(14.0, 14.0)
                .align_child(Center, Center)
                .child(Row::new(children![Rectangle::new().width(8.0).height(8.0).radius(4.0).fill(t.p.urgent), l]).gap(6.0).align(Center))));
        }
        None => {
            let (text, hint) = if running {
                ("Starting the camera…", "The first time, allow camera access on the device")
            } else if online {
                ("The camera is off", "")
            } else {
                ("The device is not connected", "")
            };
            layers.push(bx(Rectangle::new().width(w).height(ph).align_child(Center, Center).child(empty(t, w - 40.0, 0xF05A0, text, hint))));
        }
    }
    items.push(bx(Rectangle::new().width(w).height(ph).radius(12.0).fill(t.p.surface).clip().child(Stack::new(layers))));
    items.push(bx(w::gap(6.0)));
    let err = c.get("error").str_or("");
    let title = if vdev.is_empty() { t.t("No virtual camera") } else { format!("{}: {vdev}", t.t("Virtual camera")) };
    let desc = if !err.is_empty() {
        err
    } else if !vdev.is_empty() {
        t.t("Pick “Rexlink Camera” in the video call app")
    } else {
        t.t("Needs the v4l2loopback-dkms module (./install.sh --with-webcam). Set up loads it now and after every boot")
    };
    let mut card = Card::new(0xF0379, &title, &desc).id("cam-vdev");
    if vdev.is_empty() {
        card = card.ctrl(Btn::new("Set up").primary().build(t, "cam-setup", rl::setup_webcam));
    }
    items.push(bx(card.build(t, w)));
    items.push(bx(w::section(t, "Options", w)));
    let num = |k: &str, d: f64| format!("{}", cam.get(k).num_or(d) as i64);
    items.push(bx(Card::new(0xF0100, "Camera", "").ctrl(w::choice(t, "cam-face", &[("back", "Back"), ("front", "Front")], &cam.get("facing").str_or("back"), |v| rl::camera_switch(&v))).build(t, w)));
    items.push(bx(Card::new(0xF05A0, "Resolution", "Applies the next time the camera turns on")
        .ctrl(w::choice(t, "cam-res", &[("640", "480p"), ("1280", "720p"), ("1920", "1080p")], &num("width", 1280.0), |v| {
            let wv: f64 = v.parse().unwrap_or(1280.0);
            let hv = if wv == 640.0 { 480.0 } else if wv == 1280.0 { 720.0 } else { 1080.0 };
            rl::set("camera", obj(&[("width", Json::Num(wv)), ("height", Json::Num(hv))]))
        }))
        .build(t, w)));
    items.push(bx(Card::new(0xF040A, "Frame rate", "")
        .ctrl(w::choice(t, "cam-fps", &[("24", "24"), ("30", "30"), ("60", "60")], &num("fps", 30.0), |v| rl::set("camera", obj(&[("fps", Json::Num(v.parse().unwrap_or(30.0)))]))))
        .build(t, w)));
    items.push(bx(Card::new(0xF0467, "Rotation", "If the phone stands upright")
        .ctrl(w::choice(t, "cam-rot", &[("0", "0°"), ("90", "90°"), ("180", "180°"), ("270", "270°")], &num("rotate", 0.0), |v| {
            rl::set("camera", obj(&[("rotate", Json::Num(v.parse().unwrap_or(0.0)))]))
        }))
        .build(t, w)));
    items.push(bx(Card::new(0xF04E1, "Mirror", "").ctrl(w::switch(t, "cam-mirror", cam.get("mirror").bool_or(false), |v| rl::set("camera", obj(&[("mirror", Json::Bool(v))])))).build(t, w)));
}

// ═════════ экран устройства: картинка + мышь и клавиатура
struct Gesture {
    t0: Instant,
    pts: Vec<(f32, f32)>,
}
static GESTURE: Mutex<Option<Gesture>> = Mutex::new(None);
static POINTER: Mutex<(f32, f32)> = Mutex::new((0.5, 0.5));
static SCREEN_LIVE: Mutex<bool> = Mutex::new(false);

fn pt(x: f32, y: f32) -> Json {
    Json::Arr(vec![Json::Num(x as f64), Json::Num(y as f64)])
}

// клавиатура: печать уходит в поле ввода на устройстве
pub fn on_key(k: Key) -> bool {
    if super::super::Prefs::read().page != PAGE || tab(PAGE) != "screen" || !*SCREEN_LIVE.lock().unwrap() {
        return false;
    }
    let name = match k {
        Key::Backspace => "backspace",
        Key::Enter => "enter",
        Key::Escape => "back",
        Key::Tab => "tab",
        Key::Left => "left",
        Key::Right => "right",
        Key::Up => "up",
        Key::Down => "down",
        Key::Home => "home",
        Key::Space => {
            rl::input(obj(&[("kind", Json::Str("text".into())), ("text", Json::Str(" ".into()))]));
            return true;
        }
        Key::Character(c) => {
            rl::input(obj(&[("kind", Json::Str("text".into())), ("text", Json::Str(c.to_string()))]));
            return true;
        }
        _ => return false,
    };
    rl::key(name);
    true
}

fn screen_tab(t: &Tk, w: f32, h: f32, items: &mut Vec<W>) {
    let r = Rexlink::read();
    let sc = r.screens.get(&r.current).clone();
    let online = r.online();
    let name = r.dev().map(|d| d.name).unwrap_or_default();
    let ffmpeg = r.settings.get("ffmpeg").bool() != Some(false);
    let fr = r.frames.get(&format!("screen:{}", r.current)).clone();
    let cur = r.current.clone();
    drop(r);
    let running = sc.get("running").bool_or(false);
    let img = if running { frame(&format!("screen:{cur}"), &fr) } else { None };
    let live = running && img.is_some();
    *SCREEN_LIVE.lock().unwrap() = live;
    let off = sc.get("off").bool_or(false);

    // ── управление
    let info = if !online {
        t.t("The device is not connected")
    } else if running {
        format!("{name}   ·   {}×{}{}", sc.get("w").num_or(0.0), sc.get("h").num_or(0.0), if sc.get("source").str() == Some("adb") { "   ·   ADB" } else { "" })
    } else {
        name
    };
    let mut ctrl: Vec<W> = Vec::new();
    if running {
        ctrl.push(bx(w::choice(t, "scr-off", &[("on", "Screen on"), ("off", "Screen off")], if off { "off" } else { "on" }, |v| rl::screen_off(v == "off", ""))));
    }
    let b = Btn::new(if running { "Disconnect" } else { "Connect" }).icon(if running { 0xF04DB } else { 0xF0379 }).primary_if(!running).enabled(online && ffmpeg);
    let b = if running { b.danger() } else { b };
    ctrl.push(bx(b.build(t, "scr-toggle", move || if running { rl::screen_stop("") } else { rl::screen_start("") })));
    let cr = Row::new(ctrl).gap(8.0).align(Center);
    let (cw, _) = w::wh(&cr);
    items.push(bx(Row::new(children![w::line(t, &info, t.fs - 1.0, t.p.dim, w - cw - 8.0, false), cr]).gap(8.0).height(38.0).align(Center)));

    // ── отладка по Wi-Fi (для «экран выключен»)
    let mut used = 48.0;
    if running && sc.get("adbNeedPair").bool_or(false) && !off {
        static ASKED: Mutex<bool> = Mutex::new(false);
        if !std::mem::replace(&mut *ASKED.lock().unwrap(), true) {
            std::thread::spawn(rl::adb_info);
        }
        let ports = sc.get("adbPorts").clone();
        let (pc, pp) = (ports.get("connect").num(), ports.get("pairing").num());
        let iw = w - 36.0;
        let mut c: Vec<W> = vec![
            bx(Row::new(children![
                ui::icon(t, 0xF00E4, t.icon + 2.0, t.p.warn),
                w::line(t, &t.t("Turning the device screen off needs wireless debugging (ADB)"), t.fs, t.p.fg, iw - 100.0, true),
                Btn::new("").icon(0xF0450).build(t, "adb-info", rl::adb_info)
            ])
            .gap(12.0)
            .align(Center)),
            bx(w::para(t, &t.t("On the device: Settings → Developer options → Wireless debugging → on. The first time, tap “Pair device with pairing code” there and enter the port and code below. After that it connects by itself while wireless debugging is on."), t.fs - 2.0, t.p.dim, iw)),
        ];
        if pc.is_some() || pp.is_some() {
            let parts: Vec<String> = [pc.map(|p| format!("{} {p}", t.t("debugging port"))), pp.map(|p| format!("{} {p}", t.t("pairing port")))].into_iter().flatten().collect();
            c.push(bx(w::raw(t, format!("{}: {}", t.t("Found on the device"), parts.join("   ·   ")), t.fs - 1.0, t.p.fg)));
        }
        // порты, найденные на устройстве, — в поля (один раз)
        static FILLED: Mutex<(Option<i64>, Option<i64>)> = Mutex::new((None, None));
        {
            let mut f = FILLED.lock().unwrap();
            let want = (pp.map(|x| x as i64), pc.map(|x| x as i64));
            if *f != want {
                *f = want;
                if let Some(p) = want.0 {
                    w::set_field("adb-pport", &p.to_string());
                }
                if let Some(p) = want.1 {
                    w::set_field("adb-cport", &p.to_string());
                }
            }
        }
        let pair = || rl::adb_pair(&w::field_text("adb-pport"), w::field_text("adb-pcode").trim());
        let can_pair = !w::field_text("adb-pport").trim().is_empty() && !w::field_text("adb-pcode").trim().is_empty();
        let can_conn = !w::field_text("adb-cport").trim().is_empty();
        let left = Row::new(children![
            w::field(t, "adb-pport", 150.0, "Pairing port", 0, |_| {}),
            w::field(t, "adb-pcode", 150.0, "Code (6 digits)", 0, move |_| pair()),
            Btn::new("Pair").primary().enabled(can_pair).build(t, "adb-pair", pair)
        ])
        .gap(8.0)
        .align(Center);
        let right = Row::new(children![
            w::field(t, "adb-cport", 150.0, "Debugging port", 0, |v| rl::adb_connect(&v)),
            Btn::new("Connect").enabled(can_conn).build(t, "adb-conn", || rl::adb_connect(&w::field_text("adb-cport")))
        ])
        .gap(8.0)
        .align(Center);
        let (lw, _) = w::wh(&left);
        let (rw, _) = w::wh(&right);
        c.push(bx(Row::new(vec![bx(left), bx(Rectangle::new().width((iw - lw - rw - 16.0).max(0.0)).height(1.0)), bx(right)]).gap(8.0)));
        let col = Column::new(c).gap(10.0);
        let (_, ch) = w::wh(&col);
        items.push(bx(Rectangle::new().width(w).height(ch + 32.0).radius(10.0).fill(t.p.surface).border(1.0, t.p.warn).padding(Padding { top: 16.0, right: 18.0, bottom: 16.0, left: 18.0 }).child(col)));
        used += ch + 32.0 + 10.0;
    }

    // ── картинка и кнопки
    let bh = (h - used).max(320.0);
    let nav_w = if running { 58.0 + 10.0 } else { 0.0 };
    let aw = w - nav_w;
    let mut layers: Vec<W> = Vec::new();
    if let Some(p) = img {
        let (fw, fh) = (fr.get("w").num_or(sc.get("w").num_or(1080.0)) as f32, fr.get("h").num_or(sc.get("h").num_or(2400.0)) as f32);
        let (iw, ih) = (aw - 20.0, bh - 20.0);
        let k = (iw / fw).min(ih / fh);
        let (cw, ch) = (fw * k, fh * k);
        let (cx, cy) = ((aw - cw) / 2.0, (bh - ch) / 2.0);
        let norm = move |p: amane::Point| ((p.x / cw).clamp(0.0, 1.0), (p.y / ch).clamp(0.0, 1.0));
        layers.push(bx(Rectangle::new()
            .width(cw)
            .height(ch)
            .translate(cx, cy)
            .fill(Image::stretch(p))
            .cursor(amane::Crosshair)
            .on_move(move |p| *POINTER.lock().unwrap() = norm(p))
            .on_drag(move |p| {
                let n = norm(p);
                *POINTER.lock().unwrap() = n;
                let mut g = GESTURE.lock().unwrap();
                match g.as_mut() {
                    None => *g = Some(Gesture { t0: Instant::now(), pts: vec![n] }),
                    Some(gs) => {
                        let l = *gs.pts.last().unwrap();
                        if ((n.0 - l.0) * cw).hypot((n.1 - l.1) * ch) > 6.0 {
                            gs.pts.push(n);
                        }
                    }
                }
            })
            .on_click(move |b| {
                match b {
                    Button::Right => return rl::key("back"),
                    Button::Middle => return rl::key("home"),
                    Button::Left => {}
                }
                let p = *POINTER.lock().unwrap();
                let g = GESTURE.lock().unwrap().take();
                let Some(mut g) = g else {
                    rl::input(obj(&[("kind", Json::Str("tap".into())), ("x", Json::Num(p.0 as f64)), ("y", Json::Num(p.1 as f64))]));
                    return;
                };
                let dt = g.t0.elapsed().as_millis() as f64;
                let a = g.pts[0];
                let moved = ((p.0 - a.0) * cw).hypot((p.1 - a.1) * ch) > 8.0;
                if !moved {
                    let kind = if dt > 450.0 { "long" } else { "tap" };
                    rl::input(obj(&[("kind", Json::Str(kind.into())), ("x", Json::Num(a.0 as f64)), ("y", Json::Num(a.1 as f64))]));
                } else {
                    g.pts.push(p);
                    // не больше 30 точек: жест передаётся одним путём
                    let step = g.pts.len().div_ceil(30).max(1);
                    let n = g.pts.len();
                    let path: Vec<Json> = g.pts.iter().enumerate().filter(|(i, _)| i % step == 0 || *i == n - 1).map(|(_, q)| pt(q.0, q.1)).collect();
                    rl::input(obj(&[("kind", Json::Str("swipe".into())), ("points", Json::Arr(path)), ("duration", Json::Num(dt.clamp(60.0, 3000.0)))]));
                }
            })
            .on_scroll(|s| {
                let p = *POINTER.lock().unwrap();
                rl::input(obj(&[("kind", Json::Str("scroll".into())), ("x", Json::Num(p.0 as f64)), ("y", Json::Num(p.1 as f64)), ("dy", Json::Num(if s.y < 0.0 { 1.0 } else { -1.0 }))]));
            })));
    } else {
        let (text, hint) = if running {
            (
                "Waiting for the device…",
                if sc.get("source").str() == Some("adb") {
                    "Connecting over ADB…"
                } else {
                    "Press “Start” on the device — Android asks this without ADB. To skip the question, connect the device over USB or turn on wireless debugging."
                },
            )
        } else {
            (
                if online { "The screen is not connected" } else { "The device is not connected" },
                "Click — tap, hold — long press, drag — swipe, wheel — scroll, right button — Back, middle — Home, keyboard — typing. Control needs the Rexlink accessibility service on the device.",
            )
        };
        layers.push(bx(Rectangle::new().width(aw).height(bh).align_child(Center, Center).child(empty(t, (aw - 60.0).min(560.0), 0xF0379, text, hint))));
    }
    let pic = Rectangle::new().width(aw).height(bh).radius(12.0).fill(t.p.surface).clip().child(Stack::new(layers));
    let mut row: Vec<W> = vec![bx(pic)];
    if running {
        // кнопки навигации
        let keys = [
            (0xF004D, "back"),
            (0xF02DC, "home"),
            (0xF0570, "recents"),
            (0xF0E91, "notifications"),
            (0xF075D, "volup"),
            (0xF075E, "voldown"),
            (0xF0493, "quick"),
            (0xF033E, "lock"),
            (0xF0104, "screenshot"),
            // Ctrl+V: вставить на устройстве текст из буфера компьютера
            (0xF0192, "paste"),
        ];
        let btns: Vec<W> = keys.into_iter().map(|(i, k): (u32, &'static str)| bx(Btn::new("").icon(i).build(t, &format!("scr-k:{k}"), move || rl::key(k)))).collect();
        row.push(bx(Rectangle::new().width(58.0).height(bh).radius(12.0).fill(t.p.surface).padding(Padding { top: 12.0, right: 0.0, bottom: 0.0, left: 0.0 }).align_child(Center, Start).child(Column::new(btns).gap(6.0).align(Center))));
    }
    items.push(bx(Row::new(row).gap(10.0)));
}

// несколько карточек одним блоком: общий фон, тонкие разделители
fn group(t: &Tk, w: f32, cards: Vec<W>) -> Rectangle {
    let mut col: Vec<W> = Vec::new();
    let n = cards.len();
    for (i, c) in cards.into_iter().enumerate() {
        col.push(c);
        if i + 1 < n {
            col.push(bx(Rectangle::new().width(w).height(1.0).padding(Padding { top: 0.0, right: 18.0, bottom: 0.0, left: 56.0 }).child(Rectangle::new().width(w - 74.0).height(1.0).fill(t.p.surface_hi))));
        }
    }
    let c = Column::new(col);
    let (_, h) = w::wh(&c);
    Rectangle::new().width(w).height(h).radius(14.0).fill(t.p.surface).clip().child(c)
}

// ═════════ настройки Rexlink
fn options_tab(t: &Tk, w: f32, items: &mut Vec<W>) {
    let r = Rexlink::read();
    let st = r.settings.clone();
    let connected = r.connected;
    let autostart = r.autostart;
    let apk = r.apk.get("versionName").str_or("");
    let mut g: Vec<W> = Vec::new();
    drop(r);
    let tg = |key: &'static str, icon: u32, title: &str, desc: &str, def: bool| bx(Card::new(icon, title, desc).id(&format!("rl:{key}")).ctrl(sw_rl(t, &format!("rl-{key}"), key, def)).build(t, w));
    let shell = |key: &'static str, icon: u32, title: &str, desc: &str, def: bool| bx(Card::new(icon, title, desc).id(&format!("sh:{key}")).ctrl(sw_shell(t, key, def)).build(t, w));
    if !g.is_empty() { items.push(bx(group(t, w, std::mem::take(&mut g)))); }
    items.push(bx(w::section(t, "What to sync", w)));
    g.push(tg("notifications", 0xF009A, "Phone notifications", "Get notifications from the device", true));
    g.push(tg("mirrorToDesktop", 0xF0379, "Show them on the desktop", "As regular pop-up notifications, with actions and quick reply", true));
    g.push(tg("calls", 0xF03F2, "Calls", "Notifications about incoming and missed calls", true));
    g.push(tg("sms", 0xF0369, "New SMS", "Notify about incoming messages", true));
    let wl = st.get("wlClipboard").bool() == Some(false);
    g.push(tg("clipboard", 0xF014D, "Shared clipboard", if wl { "Needs the wl-clipboard package" } else { "Text and images both ways" }, true));
    g.push(tg("media", 0xF075A, "Device media", "Control what plays on the device", true));
    let pctl = st.get("playerctl").bool() == Some(false);
    g.push(tg("pcMedia", 0xF0379, "PC player on the device", if pctl { "Needs the playerctl package" } else { "Control the computer's music from the phone's notification shade (MPRIS)" }, true));

    if !g.is_empty() { items.push(bx(group(t, w, std::mem::take(&mut g)))); }
    items.push(bx(w::section(t, "Device screen", w)));
    let scr = st.get("screen").clone();
    let adb_ok = st.get("adb").bool_or(false) && st.get("scrcpy").bool_or(false);
    g.push(bx(Card::new(0xF00E4, "Capture over ADB", if adb_ok { "Like scrcpy, no prompt on the device — when it's on USB or wireless debugging. Otherwise Android asks “Start”" } else { "Needs the android-tools and scrcpy packages" })
        .ctrl(w::switch(t, "rl-scr-adb", scr.get("adb").bool() != Some(false), |v| rl::set("screen", obj(&[("adb", Json::Bool(v))]))))
        .build(t, w)));
    g.push(bx(Card::new(0xF05A8, "Keep the device screen on while showing", "The device doesn't sleep or lock while its screen is shown here")
        .ctrl(w::switch(t, "rl-scr-awake", scr.get("keepAwake").bool() != Some(false), |v| rl::set("screen", obj(&[("keepAwake", Json::Bool(v))]))))
        .build(t, w)));
    g.push(bx(Card::new(0xF0379, "Maximum size", "Long side of the picture, in pixels")
        .id("rl-maxsize")
        .ctrl(w::choice(t, "rl-scr-max", &[("960", "960"), ("1280", "1280"), ("1600", "1600"), ("1920", "1920")], &format!("{}", scr.get("maxSize").num_or(1280.0) as i64), |v| {
            rl::set("screen", obj(&[("maxSize", Json::Num(v.parse().unwrap_or(1280.0)))]))
        }))
        .build(t, w)));
    let ru = t.c.ru();
    g.push(bx(Card::new(0xF040A, "Bitrate", "")
        .ctrl(w::choice(
            t,
            "rl-scr-br",
            &[("4000000", if ru { "4 Мбит" } else { "4 Mbit" }), ("8000000", if ru { "8 Мбит" } else { "8 Mbit" }), ("16000000", if ru { "16 Мбит" } else { "16 Mbit" })],
            &format!("{}", scr.get("bitrate").num_or(8000000.0) as i64),
            |v| rl::set("screen", obj(&[("bitrate", Json::Num(v.parse().unwrap_or(8000000.0)))])),
        ))
        .build(t, w)));

    if !g.is_empty() { items.push(bx(group(t, w, std::mem::take(&mut g)))); }
    items.push(bx(w::section(t, "Devices", w)));
    let desc = if apk.is_empty() {
        t.t("rexlink.apk not found next to the service")
    } else {
        format!("{}: {apk}   ·   {}", t.t("Version next to the service"), t.t("over adb silently, otherwise the device downloads and installs it"))
    };
    let mut ctrl: Vec<W> = Vec::new();
    if !apk.is_empty() {
        ctrl.push(bx(Btn::new("Show file").icon(FOLDER).build(t, "rl-apk", show_apk)));
    }
    ctrl.push(bx(w::switch(t, "rl-autoupd", st.get("autoUpdateDevices").bool() != Some(false), |v| rl::set("autoUpdateDevices", Json::Bool(v)))));
    g.push(bx(Card::new(0xF01DA, "Update the app on devices", &desc).ctrl(Row::new(ctrl).gap(8.0).align(Center)).build(t, w)));

    if !g.is_empty() { items.push(bx(group(t, w, std::mem::take(&mut g)))); }
    items.push(bx(w::section(t, "In the shell", w)));
    g.push(shell("phone", 0xF011C, "Phone in the bar", "Battery and notifications; click for the phone menu, right-click to find it", true));
    g.push(shell("phonePercent", 0xF0079, "Battery percent", "Show the number next to the battery icon", true));
    g.push(shell("phoneOffline", 0xF0318, "Show when offline", "Keep the icon in the bar when the phone isn't connected", false));
    g.push(shell("phoneCalls", 0xF03F2, "Incoming call card", "Answer or decline calls from the desktop", true));

    if !g.is_empty() { items.push(bx(group(t, w, std::mem::take(&mut g)))); }
    items.push(bx(w::section(t, "Screen sharing", w)));
    g.push(shell("phoneCastHideCalls", 0xF03F2, "Hide calls from screencast", "Viewers see an empty spot instead of the incoming call card. You still see it", true));
    g.push(shell("phoneCastHideNotifs", 0xF0209, "Hide phone notifications from screencast", "Phone notifications and the phone menu in the bar are blacked out for viewers", true));

    if !g.is_empty() { items.push(bx(group(t, w, std::mem::take(&mut g)))); }
    items.push(bx(w::section(t, "Service", w)));
    let ips: Vec<String> = st.get("ips").arr().iter().filter_map(|x| x.str().map(String::from)).collect();
    let desc = if connected { format!("{} «{}»   ·   {}   ·   {} 47820", t.t("Computer"), st.get("name").str_or(""), ips.join(", "), t.t("port")) } else { "rexlink.service".into() };
    g.push(bx(Card::new(0xF0493, if connected { "Rexlink service is running" } else { "Rexlink service is not running" }, &desc)
        .ctrl(Btn::new(if connected { "Restart" } else { "Start" }).primary_if(!connected).build(t, "rl-svc", move || if connected { rl::restart() } else { rl::start() }))
        .build(t, w)));
    g.push(bx(Card::new(0xF0412, "Start with the system", "Runs the service after login (rexlink.service)").ctrl(w::switch(t, "rl-auto", autostart, rl::set_autostart)).build(t, w)));
    if connected {
        g.push(bx(Card::new(0xF0498, "Certificate fingerprint", &st.get("fingerprint").str_or("")).build(t, w)));
        let comps = [("ffmpeg", "ffmpeg"), ("wl-clipboard", "wlClipboard"), ("playerctl", "playerctl"), ("adb", "adb"), ("scrcpy", "scrcpy")];
        let mut parts: Vec<String> = comps.iter().map(|(n, k)| format!("{n} {}", if st.get(k).bool_or(false) { "✓" } else { "✗" })).collect();
        parts.push(format!("v4l2loopback {}", if st.get("webcamResolved").str_or("").is_empty() { "✗" } else { "✓" }));
        g.push(bx(Card::new(0xF02FD, "Components", &parts.join("   ·   ")).build(t, w)));
    }
    if !g.is_empty() {
        items.push(bx(group(t, w, g)));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ago_like_qml() {
        let now = 1_760_000_000_000.0; // 2025-10-09 08:53:20 UTC
        assert_eq!(ago(now - 30_000.0, now, 0, true), "сейчас");
        assert_eq!(ago(now - 5.0 * 60_000.0, now, 0, false), "5 min");
        assert_eq!(ago(now - 2.0 * 3600_000.0, now, 0, false), "06:53");
        assert_eq!(ago(now - 86_400_000.0, now, 0, true), "вчера");
        assert_eq!(ago(0.0, now, 0, true), "");
        assert_eq!(kind_name("watch"), "Watch");
        assert_eq!(json_id(&Json::Num(42.0)), "42");
    }
}
