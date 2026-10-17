// запись экрана через gpu-screen-recorder (Recorder.qml + RecorderMenu.qml).
// Alt+Z — меню: Enter — начать/остановить, P — пауза, R — сохранить повтор, Esc — закрыть

use std::io::Read;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use amane::{Animation, Center, Color, Column, End, Full, Key, Keyboard, Layer, LayerWindow, Monitor, Padding, Parent, Pointer, Rectangle, Row, Service, Shadow, Stack, Start, Widget, Zone, children};

use crate::json::Json;
use crate::look::{self, Tk};
use crate::niri::{Niri, sh_quote};
use crate::settings::{self, Settings};
use crate::ui;

type W = Box<dyn Widget>;

fn bx(w: impl Widget + 'static) -> W {
    Box::new(w)
}

#[derive(Clone, PartialEq)]
pub struct Cfg {
    pub target: String, // имя монитора | "region" | "window"; пусто — основной
    pub audio: String,  // none | system | mic | both
    pub fps: i64,
    pub quality: String, // high | very_high | ultra
    pub cursor: bool,
    pub countdown: bool,
    pub replay_seconds: i64,
    pub encoder: String, // cpu | gpu (на RX 580 аппаратный кодер вешает видеокарту)
}

impl Default for Cfg {
    fn default() -> Self {
        Cfg { target: String::new(), audio: "both".into(), fps: 60, quality: "very_high".into(), cursor: true, countdown: false, replay_seconds: 30, encoder: "cpu".into() }
    }
}

pub struct Recorder {
    pub cfg: Cfg,
    pub recording: bool,
    pub replay: bool,
    pub paused: bool,
    pub started: Option<Instant>,
    pub paused_total: Duration,
    pub paused_at: Option<Instant>,
    pub countdown: i64,
    pub region: String,
    // меню
    pub open: bool,
    pub output: String,
    pub anim: Animation,
}

static REC: Mutex<Option<u32>> = Mutex::new(None);
static REPLAY: Mutex<Option<u32>> = Mutex::new(None);

fn cfg_path() -> std::path::PathBuf {
    settings::path().with_file_name("recorder.json")
}

fn load_cfg() -> Cfg {
    let d = Cfg::default();
    let Some(j) = std::fs::read_to_string(cfg_path()).ok().and_then(|t| Json::parse(&t)) else { return d };
    Cfg {
        target: j.get("target").str_or(&d.target),
        audio: j.get("audio").str_or(&d.audio),
        fps: j.get("fps").num_or(d.fps as f64) as i64,
        quality: j.get("quality").str_or(&d.quality),
        cursor: j.get("cursor").bool_or(d.cursor),
        countdown: j.get("countdown").bool_or(d.countdown),
        replay_seconds: j.get("replaySeconds").num_or(d.replay_seconds as f64) as i64,
        encoder: j.get("encoder").str_or(&d.encoder),
    }
}

fn save_cfg(c: &Cfg) {
    let j = Json::Obj(vec![
        ("target".into(), Json::Str(c.target.clone())),
        ("audio".into(), Json::Str(c.audio.clone())),
        ("fps".into(), Json::Num(c.fps as f64)),
        ("quality".into(), Json::Str(c.quality.clone())),
        ("cursor".into(), Json::Bool(c.cursor)),
        ("countdown".into(), Json::Bool(c.countdown)),
        ("replaySeconds".into(), Json::Num(c.replay_seconds as f64)),
        ("encoder".into(), Json::Str(c.encoder.clone())),
    ]);
    let _ = std::fs::write(cfg_path(), j.pretty_with(4));
}

pub fn set(f: impl FnOnce(&mut Cfg)) {
    let c = {
        let mut r = Recorder::write();
        f(&mut r.cfg);
        r.cfg.clone()
    };
    save_cfg(&c);
}

fn videos() -> String {
    settings::home().join("Видео").to_string_lossy().to_string()
}

fn primary() -> String {
    let outs = Niri::read().s.outputs.clone();
    Settings::read().c.primary(&outs)
}

pub fn args(c: &Cfg, region: &str, replay: bool, stamp: &str) -> Vec<String> {
    let w = match c.target.as_str() {
        "region" => "region".to_string(),
        "window" => "portal".to_string(),
        "" => primary(),
        t => t.to_string(),
    };
    let mut a: Vec<String> = vec!["gpu-screen-recorder".into(), "-w".into(), w.clone()];
    if w == "region" {
        a.extend(["-region".into(), region.into()]);
    }
    if w == "portal" {
        a.extend(["-restore-portal-session".into(), "yes".into()]);
    }
    a.extend(["-f", &c.fps.to_string(), "-q", &c.quality, "-cursor", if c.cursor { "yes" } else { "no" }, "-c", "mp4", "-ac", "aac"].map(String::from));
    a.extend(["-encoder".into(), if c.encoder == "gpu" { "gpu".into() } else { "cpu".into() }, "-k".into(), "h264".into()]);
    let dev = match c.audio.as_str() {
        "system" => Some("default_output"),
        "mic" => Some("default_input"),
        "both" => Some("default_output|default_input"),
        _ => None,
    };
    if let Some(d) = dev {
        a.extend(["-a".into(), d.into()]);
    }
    a.extend(["-sc".into(), settings::home().join(".config/amane/data/gsr-saved.sh").to_string_lossy().to_string()]);
    if replay {
        a.extend(["-r".into(), c.replay_seconds.to_string(), "-replay-storage".into(), "ram".into(), "-o".into(), format!("{}/Replays", videos())]);
    } else {
        a.extend(["-o".into(), format!("{}/Recordings/Recording_{stamp}.mp4", videos())]);
    }
    a
}

fn stamp() -> String {
    let c = crate::clock::Clock::read().now();
    format!("{:04}-{:02}-{:02}_{:02}-{:02}-{:02}", c.year, c.month, c.day, c.hour, c.minute, c.second)
}

fn fail(what: &str, err: &str) {
    let lines: Vec<&str> = err.trim().lines().collect();
    let msg = lines[lines.len().saturating_sub(3)..].join("\n");
    let msg = if msg.is_empty() { "unknown error".to_string() } else { msg };
    amane::spawn(&format!("notify-send -a Recorder -u critical {} {}", sh_quote(what), sh_quote(&msg)));
}

// запустить gpu-screen-recorder и следить за выходом
fn run(replay: bool) {
    let c = Recorder::read().cfg.clone();
    let region = Recorder::read().region.clone();
    let a = args(&c, &region, replay, &stamp());
    let dir = format!("{}/{}", videos(), if replay { "Replays" } else { "Recordings" });
    let _ = std::fs::create_dir_all(&dir);
    let Ok(mut child): Result<Child, _> = Command::new(&a[0]).args(&a[1..]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::piped()).spawn() else {
        fail(if replay { "Replay failed" } else { "Recording failed" }, "gpu-screen-recorder is not installed");
        return;
    };
    let pid = child.id();
    *(if replay { &REPLAY } else { &REC }).lock().unwrap() = Some(pid);
    {
        let mut r = Recorder::write();
        if replay {
            r.replay = true;
        } else {
            r.recording = true;
            r.paused = false;
            r.started = Some(Instant::now());
            r.paused_total = Duration::ZERO;
            r.paused_at = None;
        }
    }
    std::thread::spawn(move || {
        let mut err = String::new();
        if let Some(mut e) = child.stderr.take() {
            let _ = e.read_to_string(&mut err);
        }
        let code = child.wait().ok().and_then(|s| s.code());
        *(if replay { &REPLAY } else { &REC }).lock().unwrap() = None;
        {
            let mut r = Recorder::write();
            if replay {
                r.replay = false;
            } else {
                r.recording = false;
                r.paused = false;
            }
        }
        if !matches!(code, Some(0) | Some(130) | Some(2) | None) {
            fail(if replay { "Replay failed" } else { "Recording failed" }, &err);
        }
    });
}

fn signal(pid: Option<u32>, sig: &str) {
    if let Some(p) = pid {
        let _ = Command::new("kill").arg(format!("-{sig}")).arg(p.to_string()).status();
    }
}

pub fn elapsed() -> u64 {
    let r = Recorder::read();
    let Some(s) = r.started.filter(|_| r.recording) else { return 0 };
    let paused = r.paused_total + r.paused_at.map(|p| p.elapsed()).unwrap_or_default();
    (s.elapsed().saturating_sub(paused)).as_secs()
}

pub fn elapsed_text() -> String {
    let e = elapsed();
    format!("{}:{:02}", e / 60, e % 60)
}

fn begin() {
    if Recorder::read().cfg.countdown {
        Recorder::write().countdown = 3;
        std::thread::spawn(|| {
            loop {
                std::thread::sleep(Duration::from_secs(1));
                let left = {
                    let mut r = Recorder::write();
                    if r.countdown <= 0 {
                        return; // отменили
                    }
                    r.countdown -= 1;
                    r.countdown
                };
                if left <= 0 {
                    run(false);
                    return;
                }
            }
        });
    } else {
        run(false);
    }
}

pub fn start() {
    let (rec, busy, target) = {
        let r = Recorder::read();
        (r.recording, r.countdown > 0, r.cfg.target.clone())
    };
    if rec || busy {
        return;
    }
    if target == "region" {
        std::thread::spawn(|| {
            let g = amane::output("slurp -f '%wx%h+%x+%y' -b '#00000066' -c '#d4d4d4' -w 1");
            let g = g.trim().to_string();
            if !g.is_empty() {
                Recorder::write().region = g;
                begin();
            }
        });
    } else {
        std::thread::spawn(begin);
    }
}

pub fn stop() {
    if Recorder::read().countdown > 0 {
        Recorder::write().countdown = 0;
    } else {
        signal(*REC.lock().unwrap(), "INT"); // остановить и сохранить
    }
}

pub fn toggle_record() {
    let r = Recorder::read();
    let active = r.recording || r.countdown > 0;
    drop(r);
    if active { stop() } else { start() }
}

pub fn toggle_pause() {
    if !Recorder::read().recording {
        return;
    }
    signal(*REC.lock().unwrap(), "USR2");
    let mut r = Recorder::write();
    r.paused = !r.paused;
    if r.paused {
        r.paused_at = Some(Instant::now());
    } else if let Some(p) = r.paused_at.take() {
        r.paused_total += p.elapsed();
    }
}

pub fn toggle_replay() {
    if Recorder::read().replay {
        signal(*REPLAY.lock().unwrap(), "INT");
    } else {
        std::thread::spawn(|| run(true));
    }
}

pub fn save_replay() {
    signal(*REPLAY.lock().unwrap(), "USR1");
}

pub fn open_folder() {
    let d = format!("{}/Recordings", videos());
    amane::spawn(&format!("mkdir -p {0} && xdg-open {0}", sh_quote(&d)));
}

pub fn set_open(open: bool) {
    let out = Niri::read().s.focused_output().to_string();
    let mut r = Recorder::write();
    if open == r.open {
        return;
    }
    r.open = open;
    if open {
        r.output = out;
        r.anim = look::anim(0.0, 220);
    } else {
        look::go(&mut r.anim, 0.0);
    }
}

pub fn ipc(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("hide") => set_open(false),
        Some("record") => toggle_record(),
        Some("pause") => toggle_pause(),
        Some("replay") => toggle_replay(),
        Some("saveReplay") => save_replay(),
        _ => {
            let o = !Recorder::read().open;
            set_open(o);
        }
    }
    "ok".into()
}

// меню успевает спрятаться и не попадает в запись
fn record_action() {
    let r = Recorder::read();
    let active = r.recording || r.countdown > 0;
    drop(r);
    if active {
        stop();
    } else {
        set_open(false);
        std::thread::spawn(|| {
            std::thread::sleep(Duration::from_millis(300));
            start();
        });
    }
}

// индикатор в баре: ЛКМ — стоп (или сохранить повтор), ПКМ — пауза, СКМ — меню
pub fn bar_indicator(t: &Tk) -> Option<Rectangle> {
    let r = Recorder::read();
    let (rec, replay, paused, cd, secs) = (r.recording, r.replay, r.paused, r.countdown, r.cfg.replay_seconds);
    drop(r);
    if !(rec || replay || cd > 0) {
        return None;
    }
    let text = if cd > 0 {
        format!("{} {cd}", ui::glyph(0xF044A))
    } else if rec {
        // секунды идут — перерисовать
        drop(crate::clock::Seconds::read());
        format!("{} {}", ui::glyph(if paused { 0xF03E4 } else { 0xF044A }), elapsed_text())
    } else {
        format!("{} {secs}s", ui::glyph(0xF0459))
    };
    let color = if (rec && !paused) || cd > 0 { t.p.urgent } else { t.p.dim };
    let op = if rec && !paused {
        amane::request_frame();
        let ms = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0) % 1600;
        let x = if ms < 800 { ms as f32 / 800.0 } else { (1600 - ms) as f32 / 800.0 };
        1.0 - 0.55 * (0.5 - 0.5 * (x * std::f32::consts::PI).cos())
    } else {
        1.0
    };
    Some(crate::bar::bar_text_c(t, "rec", text, t.fs, true, false, color).opacity(op).on_click(move |b| match b {
        amane::Button::Middle => set_open(true),
        amane::Button::Right => toggle_pause(),
        amane::Button::Left => {
            if rec || cd > 0 {
                stop()
            } else {
                save_replay()
            }
        }
    }))
}

impl Service for Recorder {
    fn new() -> Self {
        Recorder {
            cfg: load_cfg(),
            recording: false,
            replay: false,
            paused: false,
            started: None,
            paused_total: Duration::ZERO,
            paused_at: None,
            countdown: 0,
            region: String::new(),
            open: false,
            output: String::new(),
            anim: look::anim(0.0, 220),
        }
    }

    fn listen() {}
}

// ═════════ меню

fn on_key(k: Key) {
    match k {
        Key::Escape => set_open(false),
        Key::Enter | Key::Space => record_action(),
        Key::Character(c) => match c.to_lowercase().next().unwrap_or(' ') {
            'p' | 'з' => toggle_pause(),
            'r' | 'к' => save_replay(),
            _ => {}
        },
        _ => {}
    }
}

const H: u8 = ui::POPUP;

fn hov(id: &str) -> bool {
    ui::hovered::<H>(id)
}

fn clickable(r: Rectangle, id: &str, f: impl Fn() + 'static) -> Rectangle {
    ui::on_left(ui::track::<H>(r.cursor(Pointer), id.to_string()), f)
}

fn caption(t: &Tk, s: &str) -> amane::Text {
    ui::text(t, t.t(s).to_uppercase(), t.p.dim).size(t.fs - 2.0)
}

fn switch(t: &Tk, on: bool) -> Rectangle {
    Rectangle::new()
        .width(34.0)
        .height(20.0)
        .radius(10.0)
        .fill(if on { t.p.fg } else { t.p.surface_hi2 })
        .align_child(Start, Center)
        .child(Rectangle::new().width(14.0).height(14.0).radius(7.0).fill(if on { t.p.bg } else { t.p.dim }).translate(if on { 17.0 } else { 3.0 }, 0.0))
}

fn pills(t: &Tk, id: &str, opts: &[(String, String)], cur: &str, f: impl Fn(String) + Clone + 'static) -> Rectangle {
    let mut row: Vec<W> = Vec::new();
    for (v, l) in opts {
        let pid = format!("{id}:{v}");
        let sel = v == cur;
        let txt = ui::text(t, t.t(l), if sel { t.p.fg } else if hov(&pid) { t.p.muted } else { t.p.dim }).size(t.fs - 1.0);
        let (tw, _) = ui::size_of(&txt);
        let (f2, v2) = (f.clone(), v.clone());
        row.push(bx(clickable(Rectangle::new().width(tw + 20.0).height(24.0).radius(8.0).fill(if sel { t.p.surface_hi2 } else { Color::TRANSPARENT }).align_child(Center, Center).child(txt), &pid, move || f2(v2.clone()))));
    }
    let r = Row::new(row);
    let (w, _) = ui::size_of(&r);
    Rectangle::new().width(w + 6.0).height(30.0).radius(10.0).fill(t.p.surface).padding(3.0).child(r)
}

fn icon_toggle(t: &Tk, id: &str, icon: u32, on: bool, f: impl Fn() + 'static) -> Rectangle {
    clickable(
        Rectangle::new().width(30.0).height(30.0).radius(10.0).fill(if on { t.p.surface_hi2 } else if hov(id) { t.p.surface_hi } else { t.p.surface }).align_child(Center, Center).child(ui::icon(t, icon, t.icon, if on { t.p.fg } else { t.p.dim })),
        id,
        f,
    )
}

// плитка источника: монитор, область или окно
fn source_tile(t: &Tk, w: f32, value: &str, label: &str, kind: &str, aspect: f32, selected: bool, enabled: bool) -> Rectangle {
    let id = format!("rec-src:{value}");
    let stroke = if selected { t.p.fg } else { t.p.dim };
    let glyph: W = match kind {
        "region" => {
            let mut l: Vec<W> = Vec::new();
            // пунктир
            for i in 0..8 {
                let x = 4.0 + i as f32 * 6.0;
                l.push(bx(Rectangle::new().width(3.0).height(1.5).fill(stroke).translate(x, 4.0)));
                l.push(bx(Rectangle::new().width(3.0).height(1.5).fill(stroke).translate(x, 32.5)));
            }
            for i in 0..5 {
                let y = 4.0 + i as f32 * 6.0;
                l.push(bx(Rectangle::new().width(1.5).height(3.0).fill(stroke).translate(4.0, y)));
                l.push(bx(Rectangle::new().width(1.5).height(3.0).fill(stroke).translate(50.5, y)));
            }
            for (x, y) in [(4.0, 4.0), (52.0, 4.0), (4.0, 34.0), (52.0, 34.0)] {
                l.push(bx(Rectangle::new().width(5.0).height(5.0).fill(stroke).translate(x - 2.5, y - 2.5)));
            }
            bx(Rectangle::new().width(56.0).height(38.0).child(Stack::new(l)))
        }
        "window" => bx(Rectangle::new().width(56.0).height(38.0).align_child(Center, Center).child(
            Rectangle::new().width(50.0).height(34.0).radius(4.0).border(1.5, stroke).child(Rectangle::new().width(50.0).height(7.0).radius(4.0).fill(stroke)),
        )),
        _ => {
            let (gw, gh) = if aspect >= 56.0 / 38.0 { (56.0, 56.0 / aspect) } else { (38.0 * aspect, 38.0) };
            bx(Rectangle::new().width(56.0).height(38.0).align_child(Center, Center).child(Rectangle::new().width(gw).height(gh).radius(4.0).border(1.5, stroke)))
        }
    };
    let mut r = Rectangle::new()
        .width(w)
        .height(92.0)
        .radius(14.0)
        .fill(if selected { t.p.surface_hi } else if hov(&id) && enabled { t.p.surface_hi } else { t.p.surface })
        .padding(Padding { top: 14.0, right: 6.0, bottom: 12.0, left: 6.0 })
        .child(Column::new(vec![glyph, bx(Rectangle::new().width(w - 12.0).height(28.0).align_child(Center, End).child(crate::prefs::w::line(t, &t.t(label), t.fs - 1.0, if selected { t.p.fg } else { t.p.dim }, w - 12.0, false)))]).align(Center));
    if selected {
        r = r.border(1.5, t.p.fg);
    }
    let v = value.to_string();
    if enabled { clickable(r, &id, move || set(|c| c.target = v.clone())) } else { r }
}

fn audio_card(t: &Tk, w: f32, id: &str, icon: u32, title: &str, device: &str, on: bool, f: impl Fn() + 'static) -> Rectangle {
    let tw = w - 24.0 - 36.0 - 34.0 - 24.0;
    clickable(
        Rectangle::new().width(w).height(64.0).radius(14.0).fill(if hov(id) { t.p.surface_hi } else { t.p.surface }).padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 12.0 }).child(
            Row::new(children![
                Rectangle::new().width(36.0).height(36.0).radius(18.0).fill(if on { t.p.fg } else { t.p.surface_hi2 }).align_child(Center, Center).child(ui::icon(t, icon, t.icon + 1.0, if on { t.p.bg } else { t.p.dim })),
                Column::new(children![
                    crate::prefs::w::line(t, &t.t(title), t.fs, if on { t.p.fg } else { t.p.dim }, tw, false),
                    crate::prefs::w::line(t, if device.is_empty() { "—" } else { device }, t.fs - 3.0, t.p.dim, tw, false)
                ])
                .gap(2.0)
                .width(tw),
                switch(t, on)
            ])
            .gap(12.0)
            .height(64.0)
            .align(Center),
        ),
        id,
        f,
    )
}

pub fn view(m: &Monitor) -> LayerWindow {
    let tk = look::tk();
    let t = &tk;
    let r = Recorder::read();
    let here = r.open && r.output == m.name;
    let k = if r.output == m.name { r.anim.value() } else { 0.0 };
    let (c, recording, paused, cd, replay) = (r.cfg.clone(), r.recording, r.paused, r.countdown, r.replay);
    drop(r);
    look::appear("recorder", here, || {
        let mut x = Recorder::write();
        if x.open {
            look::go(&mut x.anim, 1.0);
        }
    });
    if !here && k <= 0.01 {
        return LayerWindow::new().width(1.0).height(1.0).layer(Layer::Overlay).namespace("rexilone-recorder").visible(false).child(Rectangle::new().width(1.0).height(1.0));
    }
    if recording {
        drop(crate::clock::Seconds::read());
    }
    let outs = Niri::read().s.outputs.clone();
    let prim = primary();
    let target = if c.target.is_empty() { prim.clone() } else { c.target.clone() };
    let sys_on = c.audio == "system" || c.audio == "both";
    let mic_on = c.audio == "mic" || c.audio == "both";
    let pw = crate::pw::Pw::read();
    let sink = pw.current(false).map(|n| n.desc).unwrap_or_default();
    let source = pw.current(true).map(|n| n.desc).unwrap_or_default();
    drop(pw);

    // ширина: плитки источников по одной на монитор
    let n_src = outs.len() + 2;
    let width = (n_src as f32 * 104.0 + (n_src as f32 - 1.0) * 8.0 + 48.0).max(540.0);
    let iw = width - 48.0;

    // ── заголовок
    let title = if recording {
        t.t(if paused { "Paused" } else { "Recording" })
    } else if cd > 0 {
        if t.c.ru() { format!("Старт через {cd}…") } else { format!("Starting in {cd}…") }
    } else {
        t.t("Record screen")
    };
    let src = match c.target.as_str() {
        "region" => t.t("Region"),
        "window" => t.t("Window"),
        _ => target.clone(),
    };
    let snd = t.t(match c.audio.as_str() {
        "none" => "no audio",
        "system" => "system audio",
        "mic" => "microphone",
        _ => "system + mic",
    });
    let sub = if recording { format!("{} · {src} · {snd}", elapsed_text()) } else { format!("{src} · {} fps · {snd}", c.fps) };
    let head = Row::new(children![
        Column::new(children![ui::bold(t, title, t.p.fg).size(t.fs + 7.0), ui::text(t, sub, if recording { t.p.rec } else { t.p.dim }).size(t.fs - 1.0)]).gap(2.0).width(iw - 30.0 * 2.0 - 12.0 * 2.0),
        icon_toggle(&t, "rec-folder", 0xF024B, false, || {
            set_open(false);
            open_folder();
        }),
        icon_toggle(&t, "rec-close", ui::ic::CLOSE, false, || set_open(false))
    ])
    .gap(12.0)
    .align(Center);

    // ── источник
    let tw = ((iw - (n_src as f32 - 1.0) * 8.0) / n_src as f32).floor().max(72.0);
    let en = !recording;
    let mut tiles: Vec<W> = Vec::new();
    for (name, w, h) in &outs {
        tiles.push(bx(source_tile(&t, tw, name, name, "monitor", *w as f32 / (*h).max(1) as f32, target == *name, en)));
    }
    tiles.push(bx(source_tile(&t, tw, "region", "Region", "region", 1.0, c.target == "region", en)));
    tiles.push(bx(source_tile(&t, tw, "window", "Window", "window", 1.0, c.target == "window", en)));
    let source_sec = Column::new(children![caption(&t, "Source"), Row::new(tiles).gap(8.0)]).gap(10.0);

    // ── звук
    let aw = (iw - 8.0) / 2.0;
    let set_audio = |sys: bool, mic: bool| {
        let a = if sys && mic { "both" } else if sys { "system" } else if mic { "mic" } else { "none" };
        set(|c| c.audio = a.into())
    };
    let audio_sec = Column::new(children![
        caption(&t, "Audio"),
        Row::new(children![
            audio_card(&t, aw, "rec-sys", ui::ic::VOL_HIGH, "System audio", &sink, sys_on, move || if en { set_audio(!sys_on, mic_on) }),
            audio_card(&t, aw, "rec-mic", ui::ic::MIC, "Microphone", &source, mic_on, move || if en { set_audio(sys_on, !mic_on) })
        ])
        .gap(8.0)
    ])
    .gap(10.0);

    // ── параметры
    let fps: Vec<(String, String)> = [30, 60, 120].iter().map(|f| (f.to_string(), format!("{f} fps"))).collect();
    let q: Vec<(String, String)> = [("high", "High"), ("very_high", "Very high"), ("ultra", "Ultra")].iter().map(|(a, b)| (a.to_string(), b.to_string())).collect();
    let p1 = pills(&t, "rec-fps", &fps, &c.fps.to_string(), move |v| if en { set(|c| c.fps = v.parse().unwrap_or(60)) });
    let p2 = pills(&t, "rec-q", &q, &c.quality, move |v| if en { set(|c| c.quality = v) });
    let (w1, _) = ui::size_of(&p1);
    let (w2, _) = ui::size_of(&p2);
    let params = Row::new(children![
        p1,
        p2,
        Rectangle::new().width((iw - w1 - w2 - 60.0 - 8.0 * 4.0).max(0.0)).height(30.0),
        icon_toggle(&t, "rec-cursor", 0xF01BF, c.cursor, move || if en { set(|c| c.cursor = !c.cursor) }),
        icon_toggle(&t, "rec-timer", 0xF13AB, c.countdown, move || if en { set(|c| c.countdown = !c.countdown) })
    ])
    .gap(8.0)
    .align(Center);
    let dim = |w: Column| -> Rectangle {
        let (ww, hh) = ui::size_of(&w);
        Rectangle::new().width(ww.max(iw)).height(hh).opacity(if en { 1.0 } else { 0.4 }).child(w)
    };

    // ── кнопка записи
    let control: W = if cd > 0 {
        bx(clickable(
            Rectangle::new().width(iw).height(52.0).radius(14.0).fill(t.p.surface).clip().child(Stack::new(children![
                Rectangle::new().width(iw * cd as f32 / 3.0).height(52.0).radius(14.0).fill(t.p.surface_hi2),
                Rectangle::new().width(iw).height(52.0).align_child(Center, Center).child(ui::bold(t, if t.c.ru() { format!("Старт через {cd}") } else { format!("Starting in {cd}") }, t.p.fg).size(t.fs + 1.0))
            ])),
            "rec-cd",
            stop,
        ))
    } else if recording {
        let dot_op = if paused {
            1.0
        } else {
            amane::request_frame();
            let ms = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0) % 1400;
            let x = if ms < 700 { ms as f32 / 700.0 } else { (1400 - ms) as f32 / 700.0 };
            1.0 - 0.7 * (0.5 - 0.5 * (x * std::f32::consts::PI).cos())
        };
        bx(Rectangle::new().width(iw).height(52.0).radius(14.0).fill(t.p.surface).padding(Padding { top: 0.0, right: 8.0, bottom: 0.0, left: 20.0 }).child(
            Row::new(children![
                Rectangle::new().width(10.0).height(10.0).radius(5.0).fill(if paused { t.p.dim } else { t.p.rec }).opacity(dot_op),
                ui::bold(t, elapsed_text(), t.p.fg).size(t.fs + 3.0),
                Rectangle::new().width(iw - 28.0 - 10.0 - 70.0 - 36.0 * 2.0 - 12.0 * 4.0).height(20.0).align_child(Start, Center).child(ui::text(t, if paused { t.t("paused") } else { String::new() }, t.p.dim).size(t.fs - 1.0)),
                clickable(
                    Rectangle::new().width(36.0).height(36.0).radius(10.0).fill(if hov("rec-pause") { t.p.surface_hi2 } else { t.p.surface_hi }).align_child(Center, Center).child(ui::icon(t, if paused { 0xF040A } else { 0xF03E4 }, t.icon, t.p.fg)),
                    "rec-pause",
                    toggle_pause
                ),
                clickable(
                    Rectangle::new().width(36.0).height(36.0).radius(10.0).fill(if hov("rec-stop") { t.p.muted } else { t.p.fg }).align_child(Center, Center).child(Rectangle::new().width(12.0).height(12.0).radius(2.0).fill(t.p.bg)),
                    "rec-stop",
                    stop
                )
            ])
            .gap(12.0)
            .height(52.0)
            .align(Center),
        ))
    } else {
        bx(clickable(
            Rectangle::new().width(iw).height(52.0).radius(14.0).fill(if hov("rec-start") { t.p.muted } else { t.p.fg }).padding(Padding { top: 0.0, right: 14.0, bottom: 0.0, left: 20.0 }).child(
                Row::new(children![
                    Rectangle::new().width(10.0).height(10.0).radius(5.0).fill(t.p.rec),
                    Rectangle::new().width(iw - 34.0 - 10.0 - 26.0 - 24.0).height(24.0).align_child(Start, Center).child(ui::bold(t, t.t("Start recording"), t.p.bg).size(t.fs + 1.0)),
                    Rectangle::new().width(26.0).height(22.0).radius(6.0).border(1.0, Color::rgba(0, 0, 0, 38)).align_child(Center, Center).child(ui::text(t, "⏎", t.p.dim).size(t.fs - 1.0))
                ])
                .gap(12.0)
                .height(52.0)
                .align(Center),
            ),
            "rec-start",
            record_action,
        ))
    };

    // ── мгновенный повтор
    let rs: Vec<(String, String)> = [15, 30, 60, 120].iter().map(|s| (s.to_string(), format!("{s}s"))).collect();
    let right: Rectangle = if replay {
        let l = ui::bold(t, t.t("Save"), t.p.bg).size(t.fs - 1.0);
        let (lw, _) = ui::size_of(&l);
        (clickable(Rectangle::new().width(lw + 24.0).height(30.0).radius(10.0).fill(if hov("rec-save") { t.p.muted } else { t.p.fg }).align_child(Center, Center).child(l), "rec-save", save_replay))
    } else {
        (pills(&t, "rec-rs", &rs, &c.replay_seconds.to_string(), |v| set(|c| c.replay_seconds = v.parse().unwrap_or(30))))
    };
    let (rw, _) = ui::size_of(&right);
    let rsub = if replay {
        if t.c.ru() { format!("пишет последние {} с · R — сохранить", c.replay_seconds) } else { format!("buffering last {}s · R to save", c.replay_seconds) }
    } else {
        t.t("keeps the last moments in memory")
    };
    let mut rep = Rectangle::new().width(iw).height(56.0).radius(14.0).fill(t.p.surface).padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 14.0 });
    if replay {
        rep = rep.border(1.0, t.p.line);
    }
    let rtw = iw - 26.0 - t.icon - 2.0 - rw - 34.0 - 10.0 * 3.0;
    let replay_card = rep.child(
        Row::new(vec![
            bx(ui::icon(t, 0xF0459, t.icon + 2.0, if replay { t.p.fg } else { t.p.dim })),
            bx(Column::new(children![crate::prefs::w::line(t, &t.t("Instant replay"), t.fs, if replay { t.p.fg } else { t.p.dim }, rtw, false), crate::prefs::w::line(t, &rsub, t.fs - 3.0, t.p.dim, rtw, false)]).gap(1.0).width(rtw)),
            bx(right),
            bx(clickable(switch(t, replay), "rec-replay", toggle_replay)),
        ])
        .gap(10.0)
        .height(56.0)
        .align(Center),
    );
    let hint = Rectangle::new().width(iw).height(16.0).align_child(Center, Center).child(ui::text(t, t.t("Enter  start / stop   ·   P  pause   ·   R  save replay   ·   Esc  close"), t.p.line).size(t.fs - 3.0));

    let column = Column::new(vec![bx(head), bx(dim(source_sec)), bx(dim(audio_sec)), bx(dim(Column::new(vec![bx(params)]))), control, bx(replay_card), bx(hint)]).gap(18.0);
    let (_, ch) = ui::size_of(&column);
    let mut layers: Vec<W> = Vec::new();
    if recording {
        // лёгкий красный отсвет сверху во время записи
        layers.push(bx(Rectangle::new().width(width).height((ch + 48.0) * 0.35).radius(22.0).fill(amane::Gradient::linear(180.0, [(0.0, Color::rgba(0xe0, 0x5d, 0x5d, 0x22)), (1.0, Color::rgba(0xe0, 0x5d, 0x5d, 0))]))));
    }
    layers.push(bx(Rectangle::new().width(width).height(ch + 48.0).padding(24.0).child(column)));
    let card = Rectangle::new()
        .width(width)
        .height(ch + 48.0)
        .radius(22.0)
        .fill(t.panel)
        .border(1.0, t.p.surface_hi2)
        .shadow(Shadow::drop("#000000").opacity(0.6).blur(40.0).offset(0.0, 12.0))
        .opacity(k)
        .scale(0.94 + 0.06 * k)
        .on_click(|_| {})
        .child(Stack::new(layers));
    LayerWindow::new()
        .width(Full)
        .height(Full)
        .layer(Layer::Overlay)
        .space(Zone::Ignore)
        .namespace("rexilone-recorder")
        .keyboard(if here { Keyboard::Exclusive } else { Keyboard::None })
        .on_key(on_key)
        .visible(here || k > 0.01)
        .child(Rectangle::new().width(Parent).height(Parent).fill(Color::rgba(0, 0, 0, (0.45 * k * 255.0) as u8)).align_child(Center, Center).on_click(|_| set_open(false)).child(card))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recorder_args() {
        let c = Cfg { target: "DP-1".into(), audio: "both".into(), fps: 60, quality: "ultra".into(), cursor: false, countdown: false, replay_seconds: 30, encoder: "cpu".into() };
        let a = args(&c, "", false, "2026-01-02_03-04-05");
        let s = a.join(" ");
        assert!(s.starts_with("gpu-screen-recorder -w DP-1 -f 60 -q ultra -cursor no -c mp4 -ac aac -encoder cpu -k h264 -a default_output|default_input -sc "));
        assert!(s.ends_with("Recordings/Recording_2026-01-02_03-04-05.mp4"));
        let r = args(&Cfg { target: "region".into(), audio: "none".into(), ..c.clone() }, "100x100+0+0", true, "x");
        let s = r.join(" ");
        assert!(s.contains("-w region -region 100x100+0+0") && !s.contains(" -a ") && s.contains("-r 30 -replay-storage ram -o"));
        let w = args(&Cfg { target: "window".into(), ..c }, "", false, "x").join(" ");
        assert!(w.contains("-w portal -restore-portal-session yes"));
    }
}
