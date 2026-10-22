// Rexlink — связь с телефоном, планшетом и часами (как services/Rexlink.qml).
// Служба: unix-сокет $XDG_RUNTIME_DIR/rexlink/rexlink.sock, JSON-строки; события — после "subscribe".

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use amane::Service;

use crate::json::Json;

#[derive(Debug, Clone, PartialEq)]
pub struct Device {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub model: String,
    pub online: bool,
    pub battery: i64,
    pub charging: bool,
    pub notifications: i64,
    pub current: bool,
    pub raw: Json,
}

pub fn device(j: &Json) -> Device {
    Device {
        id: j.get("id").str_or(""),
        name: j.get("name").str_or(""),
        kind: j.get("kind").str_or("phone"),
        model: j.get("model").str_or(""),
        online: j.get("online").bool_or(false),
        battery: j.get("battery").num_or(-1.0) as i64,
        charging: j.get("charging").bool_or(false),
        notifications: j.get("notifications").num_or(0.0) as i64,
        current: j.get("current").bool_or(false),
        raw: j.clone(),
    }
}

#[derive(Default)]
pub struct Rexlink {
    pub installed: bool,
    pub autostart: bool,
    pub connected: bool,
    pub devices: Json,
    pub current: String,
    pub status: Json,
    pub caps: Json,
    pub media: Json,
    pub pc_media: Json,
    pub call: Json,
    pub notifs: Json,
    pub transfers: Json,
    pub settings: Json,
    pub pairing: Json,
    pub camera: Json,
    pub clips: Json,
    pub screens: Json,
    pub frames: Json,
    pub sms: Json,
    pub apk: Json,
    // данные других устройств: id → { status, media, notifs }
    pub by_dev: HashMap<String, Json>,
    // короткие сообщения службы и запросы быстрого ответа
    pub toasts: Vec<String>,
    pub toast_at: Option<std::time::Instant>,
    pub reply_requests: Vec<Json>,
}

impl Rexlink {
    pub fn dev(&self) -> Option<Device> {
        self.devices.arr().iter().map(device).find(|d| d.id == self.current)
    }
    pub fn online(&self) -> bool {
        self.dev().is_some_and(|d| d.online)
    }
    pub fn dev_for(&self, id: &str) -> Option<Device> {
        let id = if id.is_empty() { &self.current } else { id };
        self.devices.arr().iter().map(device).find(|d| d.id == *id)
    }
    pub fn status_for(&self, id: &str) -> Json {
        if !id.is_empty() && id != self.current { self.by_dev.get(id).map(|b| b.get("status").clone()).unwrap_or(Json::Null) } else { self.status.clone() }
    }
    pub fn media_for(&self, id: &str) -> Json {
        if !id.is_empty() && id != self.current { self.by_dev.get(id).map(|b| b.get("media").clone()).unwrap_or(Json::Null) } else { self.media.clone() }
    }
    pub fn notifs_for(&self, id: &str) -> Json {
        if !id.is_empty() && id != self.current { self.by_dev.get(id).map(|b| b.get("notifs").clone()).unwrap_or(Json::Arr(Vec::new())) } else { self.notifs.clone() }
    }
    pub fn ringing(&self) -> bool {
        self.call.get("state").str() == Some("ringing")
    }
    fn put_dev(&mut self, id: &str, key: &str, v: Json) {
        let e = self.by_dev.entry(id.to_string()).or_insert(Json::Obj(Vec::new()));
        e.set(key, v);
    }
}

pub fn devices() -> Vec<Device> {
    Rexlink::read().devices.arr().iter().map(device).collect()
}

pub fn connected() -> bool {
    Rexlink::read().connected
}

pub fn sock_path() -> String {
    format!("{}/rexlink/rexlink.sock", std::env::var("XDG_RUNTIME_DIR").unwrap_or_default())
}

type Cb = Box<dyn FnOnce(Option<Json>) + Send>;

struct Conn {
    writer: Mutex<Option<UnixStream>>,
    pending: Mutex<HashMap<u64, Cb>>,
    seq: Mutex<u64>,
}

fn conn() -> &'static Conn {
    static C: OnceLock<Conn> = OnceLock::new();
    C.get_or_init(|| Conn { writer: Mutex::new(None), pending: Mutex::new(HashMap::new()), seq: Mutex::new(1) })
}

// запрос к службе; ответ — в cb (в потоке чтения)
pub fn cmd_cb(name: &str, params: Json, cb: Option<Cb>) {
    let c = conn();
    let mut w = c.writer.lock().unwrap();
    let Some(s) = w.as_mut() else { return };
    let id = {
        let mut q = c.seq.lock().unwrap();
        *q += 1;
        *q
    };
    if let Some(cb) = cb {
        c.pending.lock().unwrap().insert(id, cb);
    }
    let mut m = Json::Obj(vec![("id".into(), Json::Num(id as f64)), ("cmd".into(), Json::Str(name.into()))]);
    for (k, v) in params.obj() {
        m.set(k, v.clone());
    }
    let mut line = m.pretty_with(0).replace('\n', "");
    line.push('\n');
    if s.write_all(line.as_bytes()).is_err() {
        *w = None;
    }
}

pub fn cmd(name: &str, params: Json) {
    cmd_cb(name, params, None);
}

pub fn obj(items: &[(&str, Json)]) -> Json {
    Json::Obj(items.iter().map(|(k, v)| (k.to_string(), v.clone())).collect())
}

fn dev_(id: &str) -> Vec<(&'static str, Json)> {
    if id.is_empty() { vec![] } else { vec![("device", Json::Str(id.into()))] }
}

fn with_dev(id: &str, mut extra: Vec<(&'static str, Json)>) -> Json {
    extra.extend(dev_(id));
    Json::Obj(extra.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
}

// ── действия
pub fn ring(id: &str) {
    cmd("ring", with_dev(id, vec![]));
}
pub fn select(id: &str) {
    cmd_cb("select", obj(&[("device", Json::Str(id.into()))]), Some(Box::new(|_| refresh())));
}
pub fn media_action(a: &str, id: &str, value: f64) {
    cmd("media", with_dev(id, vec![("action", Json::Str(a.into())), ("value", Json::Num(value))]));
}
pub fn pc_media_action(a: &str) {
    cmd("pc_media", obj(&[("action", Json::Str(a.into()))]));
}
pub fn call_action(a: &str) {
    let r = Rexlink::read();
    let dev = r.call.get("device").str().filter(|d| !d.is_empty()).map(String::from).unwrap_or_else(|| r.current.clone());
    drop(r);
    cmd("call", obj(&[("action", Json::Str(a.into())), ("device", Json::Str(dev))]));
}
pub fn dial(number: &str) {
    cmd("dial", obj(&[("number", Json::Str(number.into()))]));
}
pub fn notif_action(key: &str, i: i64, id: &str) {
    cmd("notif_action", with_dev(id, vec![("key", Json::Str(key.into())), ("action", Json::Num(i as f64))]));
}
pub fn notif_reply(key: &str, i: i64, text: &str, id: &str) {
    cmd("notif_reply", with_dev(id, vec![("key", Json::Str(key.into())), ("action", Json::Num(i as f64)), ("text", Json::Str(text.into()))]));
}
pub fn notif_dismiss(key: &str, id: &str) {
    {
        let mut r = Rexlink::write();
        if id.is_empty() || id == r.current {
            if let Json::Arr(v) = &mut r.notifs {
                v.retain(|n| n.get("key").str() != Some(key));
            }
        } else {
            let mut n = r.notifs_for(id);
            if let Json::Arr(v) = &mut n {
                v.retain(|x| x.get("key").str() != Some(key));
            }
            r.put_dev(id, "notifs", n);
        }
    }
    cmd("notif_dismiss", with_dev(id, vec![("key", Json::Str(key.into()))]));
}
pub fn notif_dismiss_all() {
    {
        let mut r = Rexlink::write();
        if let Json::Arr(v) = &mut r.notifs {
            v.retain(|n| n.get("clearable").bool() == Some(false));
        }
    }
    cmd("notif_dismiss_all", Json::Obj(Vec::new()));
}
pub fn clipboard_pull(id: &str) {
    cmd("clipboard_pull", with_dev(id, vec![]));
}
pub fn clipboard_clear() {
    cmd("clipboard_clear", Json::Obj(Vec::new()));
}
pub fn send_files(paths: &[String], id: &str) {
    cmd("send_files", with_dev(id, vec![("paths", Json::Arr(paths.iter().map(|p| Json::Str(p.clone())).collect()))]));
}
pub fn transfer_cancel(fid: &str) {
    cmd("transfer_cancel", obj(&[("fid", Json::Str(fid.into()))]));
}
pub fn transfers_clear() {
    cmd("transfers_clear", Json::Obj(Vec::new()));
}
pub fn sms_refresh() {
    cmd("sms_threads", Json::Obj(Vec::new()));
}
pub fn sms_open(thread: &str) {
    cmd("sms_open", obj(&[("thread", Json::Str(thread.into()))]));
}
pub fn sms_send(address: &str, body: &str) {
    cmd("sms_send", obj(&[("address", Json::Str(address.into())), ("body", Json::Str(body.into()))]));
}
pub fn camera_start(id: &str) {
    cmd("camera_start", with_dev(id, vec![]));
}
pub fn camera_stop() {
    cmd("camera_stop", Json::Obj(Vec::new()));
}
pub fn camera_switch(facing: &str) {
    cmd("camera_switch", obj(&[("facing", Json::Str(facing.into()))]));
}
pub fn screen_start(id: &str) {
    cmd("screen_start", with_dev(id, vec![]));
}
pub fn screen_stop(id: &str) {
    cmd("screen_stop", with_dev(id, vec![]));
}
// устройство как второй монитор ПК (via: "" — сама служба выберет USB или Wi-Fi)
pub fn display_start(id: &str) {
    cmd("display_start", with_dev(id, vec![]));
}
pub fn display_stop(id: &str) {
    cmd("display_stop", with_dev(id, vec![]));
}
pub fn screen_off(off: bool, id: &str) {
    cmd("screen_off", with_dev(id, vec![("off", Json::Bool(off))]));
}
pub fn input(ev: Json) {
    cmd("input", ev);
}
pub fn key(k: &str) {
    cmd("input", obj(&[("kind", Json::Str("key".into())), ("key", Json::Str(k.into()))]));
}
pub fn adb_info() {
    cmd("adb_info", Json::Obj(Vec::new()));
}
pub fn adb_pair(port: &str, code: &str) {
    cmd("adb_pair", obj(&[("port", Json::Num(port.trim().parse().unwrap_or(0.0))), ("code", Json::Str(code.into()))]));
}
pub fn adb_connect(port: &str) {
    cmd("adb_connect", obj(&[("port", Json::Num(port.trim().parse().unwrap_or(0.0)))]));
}
pub fn update_device(id: &str) {
    cmd("update_device", with_dev(id, vec![]));
}
pub fn rename(id: &str, name: &str) {
    cmd_cb("rename", obj(&[("device", Json::Str(id.into())), ("name", Json::Str(name.into()))]), Some(Box::new(|_| refresh())));
}
pub fn forget(id: &str) {
    cmd_cb("forget", obj(&[("device", Json::Str(id.into()))]), Some(Box::new(|_| refresh())));
}
pub fn pair_answer(accept: bool) {
    let id = Rexlink::read().pairing.get("id").str_or("");
    cmd_cb(
        "pair_answer",
        obj(&[("device", Json::Str(id)), ("accept", Json::Bool(accept))]),
        Some(Box::new(|_| Rexlink::write().pairing = Json::Obj(Vec::new()))),
    );
}
pub fn set(key: &str, value: Json) {
    cmd("set", obj(&[("key", Json::Str(key.into())), ("value", value)]));
}
pub fn set_download_dir(path: &str) {
    cmd("download_dir", obj(&[("path", Json::Str(path.into()))]));
}
// смотреть видеоканал ("screen:<id>" | "camera"): пока смотрим, служба присылает кадры
pub fn watch(channel: &str, on: bool) {
    cmd("frames", obj(&[("channel", Json::Str(channel.into())), ("on", Json::Bool(on))]));
}
// порты Rexlink в файрволе (ufw)
pub fn open_firewall() {
    std::thread::spawn(|| {
        amane::output("pkexec sh -c 'ufw allow 47820/tcp comment Rexlink && ufw allow 47821/udp comment Rexlink'");
        cmd_cb("firewall_check", Json::Obj(Vec::new()), Some(Box::new(|_| cmd_cb("settings", Json::Obj(Vec::new()), Some(Box::new(|r| {
            if let Some(r) = r {
                Rexlink::write().settings = r;
            }
        }))))));
    });
}
// виртуальная камера: модуль v4l2loopback «Rexlink Camera» (/dev/video42)
pub fn setup_webcam() {
    std::thread::spawn(|| {
        amane::output(
            r#"d="$(dirname "$(readlink -f "$HOME/.local/bin/rexlink")")/../../../rexlink/system"; pkexec sh -c 'install -Dm644 "$1/rexlink-v4l2loopback.conf" /etc/modprobe.d/rexlink-v4l2loopback.conf && install -Dm644 "$1/rexlink-modules-load.conf" /etc/modules-load.d/rexlink.conf && { modprobe -r v4l2loopback 2>/dev/null; modprobe v4l2loopback; }' sh "$(realpath "$d")""#,
        );
        cmd_cb("settings", Json::Obj(Vec::new()), Some(Box::new(|r| {
            if let Some(r) = r {
                Rexlink::write().settings = r;
            }
        })));
    });
}
pub fn start() {
    amane::spawn("systemctl --user start rexlink.service");
}
pub fn restart() {
    amane::spawn("systemctl --user restart rexlink.service");
}
pub fn set_autostart(on: bool) {
    amane::spawn(&format!("systemctl --user {} rexlink.service", if on { "enable" } else { "disable" }));
    Rexlink::write().autostart = on;
}

// ── форматирование
pub fn bytes(n: f64, ru: bool) -> String {
    let u = if ru { ["Б", "КБ", "МБ", "ГБ", "ТБ"] } else { ["B", "KB", "MB", "GB", "TB"] };
    if n <= 0.0 {
        return format!("0 {}", u[0]);
    }
    let mut n = n;
    let mut i = 0;
    while n >= 1024.0 && i < u.len() - 1 {
        n /= 1024.0;
        i += 1;
    }
    if i > 0 && n < 10.0 { format!("{n:.1} {}", u[i]) } else { format!("{n:.0} {}", u[i]) }
}

pub fn duration(ms: f64) -> String {
    if ms <= 0.0 {
        return "0:00".into();
    }
    let s = (ms / 1000.0) as u64;
    let (h, m, ss) = (s / 3600, s / 60 % 60, s % 60);
    if h > 0 { format!("{h}:{m:02}:{ss:02}") } else { format!("{m}:{ss:02}") }
}

pub fn initials(s: &str) -> String {
    let s = s.trim();
    if s.is_empty() {
        return "?".into();
    }
    if s.chars().all(|c| c.is_ascii_digit() || "+ ()-".contains(c)) {
        return "#".into();
    }
    let parts: Vec<&str> = s.split_whitespace().collect();
    let mut out: String = parts[0].chars().next().map(|c| c.to_uppercase().collect()).unwrap_or_default();
    if parts.len() > 1 {
        out += &parts[1].chars().next().map(|c| c.to_uppercase().collect::<String>()).unwrap_or_default();
    }
    out
}

pub fn kind_icon(kind: &str) -> u32 {
    match kind {
        "tablet" => 0xF04F7,
        "watch" => 0xF0954,
        _ => 0xF011C,
    }
}

pub fn battery_icon(level: i64, charging: bool) -> u32 {
    if charging {
        0xF0084
    } else if level < 0 {
        0xF0091
    } else if level >= 95 {
        0xF0079
    } else if level < 10 {
        0xF008E
    } else {
        0xF007A + (level / 10) as u32 - 1
    }
}

pub fn wifi_icon(level: i64) -> u32 {
    [0xF092F, 0xF091F, 0xF0922, 0xF0925, 0xF0928][level.clamp(0, 4) as usize]
}

pub fn cell_icon(level: i64) -> u32 {
    [0xF08BF, 0xF08BC, 0xF08BD, 0xF08BE, 0xF08BE][level.clamp(0, 4) as usize]
}

// ── запросы состояния
fn on<F: FnOnce(&mut Rexlink, Json) + Send + 'static>(name: &str, params: Json, f: F) {
    cmd_cb(name, params, Some(Box::new(move |r| {
        if let Some(r) = r {
            f(&mut Rexlink::write(), r);
        }
    })));
}

pub fn refresh() {
    on("devices", Json::Obj(Vec::new()), |s, r| {
        let others: Vec<String> = r.arr().iter().map(device).filter(|d| d.id != s.current && d.online).map(|d| d.id).collect();
        s.devices = r;
        std::thread::spawn(move || {
            for id in others {
                refresh_other(&id);
            }
        });
    });
    on("state", Json::Obj(Vec::new()), |s, r| {
        s.current = r.get("current").str_or("");
        std::thread::spawn(refresh_device);
    });
    on("settings", Json::Obj(Vec::new()), |s, r| {
        s.settings = r;
        std::thread::spawn(sync_lang);
    });
    on("transfers", Json::Obj(Vec::new()), |s, r| s.transfers = r);
    on("pairing", Json::Obj(Vec::new()), |s, r| s.pairing = r);
    on("camera", Json::Obj(Vec::new()), |s, r| s.camera = r);
    on("clipboard_history", Json::Obj(Vec::new()), |s, r| s.clips = r);
    on("pc_media", Json::Obj(Vec::new()), |s, r| s.pc_media = r);
    on("apk", Json::Obj(Vec::new()), |s, r| s.apk = r);
    on("sms_state", Json::Obj(Vec::new()), |s, r| s.sms = r);
}

fn refresh_other(id: &str) {
    let i = id.to_string();
    on("device", obj(&[("device", Json::Str(id.into()))]), move |s, r| {
        s.put_dev(&i, "status", r.get("status").clone());
        s.put_dev(&i, "media", r.get("media").clone());
    });
    let i = id.to_string();
    on("notifications", obj(&[("device", Json::Str(id.into()))]), move |s, r| s.put_dev(&i, "notifs", r));
}

fn refresh_device() {
    let cur = Rexlink::read().current.clone();
    if cur.is_empty() {
        return;
    }
    let c2 = cur.clone();
    on("device", obj(&[("device", Json::Str(cur.clone()))]), move |s, r| {
        s.status = r.get("status").clone();
        s.caps = r.get("caps").clone();
        s.media = r.get("media").clone();
        if !r.get("call").get("state").str_or("").is_empty() {
            let mut c = r.get("call").clone();
            c.set("device", Json::Str(c2));
            s.call = c;
        }
    });
    on("notifications", obj(&[("device", Json::Str(cur.clone()))]), |s, r| s.notifs = r);
    let c3 = cur.clone();
    on("screen", obj(&[("device", Json::Str(cur))]), move |s, r| s.screens.set(&c3, r));
}

// язык уведомлений службы — как у шелла
fn sync_lang() {
    let lang = crate::settings::Settings::read().c.language.clone();
    let r = Rexlink::read();
    let ok = r.connected && !r.settings.get("name").is_null() && r.settings.get("lang").str() != Some(lang.as_str());
    drop(r);
    if ok {
        set("lang", Json::Str(lang));
    }
}

// событие службы
pub fn handle(s: &mut Rexlink, m: &Json) -> bool {
    let d = m.get("data").clone();
    let dev = d.get("device").str_or("");
    let cur = s.current.clone();
    match m.get("event").str().unwrap_or("") {
        "device_connected" | "device_disconnected" | "pair_finished" | "update" => {
            if m.get("event").str() == Some("pair_finished") {
                s.pairing = Json::Obj(Vec::new());
            }
            return true; // нужен refresh
        }
        "devices" => {
            if !d.arr().iter().any(|x| x.get("id").str() == Some(cur.as_str())) {
                s.current = d.arr().iter().find(|x| x.get("current").bool_or(false)).and_then(|x| x.get("id").str()).unwrap_or("").to_string();
            }
            s.devices = d;
        }
        "status" => {
            if dev == cur { s.status = d } else { s.put_dev(&dev, "status", d) }
        }
        "notification" => {
            let key = d.get("key").str_or("");
            let mut list = s.notifs_for(&dev);
            let mut v = vec![d.clone()];
            v.extend(list.arr().iter().filter(|n| n.get("key").str() != Some(key.as_str())).cloned());
            list = Json::Arr(v);
            if dev == cur { s.notifs = list } else { s.put_dev(&dev, "notifs", list) }
        }
        "notification_removed" => {
            let key = d.get("key").str_or("");
            let list = Json::Arr(s.notifs_for(&dev).arr().iter().filter(|n| n.get("key").str() != Some(key.as_str())).cloned().collect());
            if dev == cur { s.notifs = list } else { s.put_dev(&dev, "notifs", list) }
        }
        "media" => {
            if dev == cur { s.media = d } else { s.put_dev(&dev, "media", d) }
        }
        "pc_media" => s.pc_media = d,
        "call" => s.call = d,
        "pair_request" => s.pairing = d,
        "transfers" => s.transfers = d,
        "camera" | "camera_state" => s.camera = d,
        "screen_state" => s.screens = d,
        "display" => {
            let mut sc = s.screens.get(&dev).clone();
            if sc.is_null() {
                sc = Json::Obj(Vec::new());
            }
            sc.set("display", d);
            s.screens.set(&dev, sc);
        }
        "frame" => {
            let ch = d.get("channel").str_or("");
            s.frames.set(&ch, d);
        }
        "clips" => s.clips = d,
        "settings" => s.settings = d,
        "sms_state" => {
            if dev == cur {
                s.sms = d
            }
        }
        "sms_threads" => {
            if dev == cur {
                s.sms.set("threads", d.get("threads").clone())
            }
        }
        "sms_messages" => {
            let open = s.sms.get("thread").get("id").clone();
            let same = match (&open, d.get("thread")) {
                (Json::Num(a), Json::Num(b)) => a == b,
                (a, b) => json_str(a) == json_str(b),
            };
            if dev == cur && same {
                s.sms.set("messages", d.get("messages").clone())
            }
        }
        "toast" => {
            s.toasts.push(d.get("text").str_or(""));
            s.toast_at = Some(std::time::Instant::now());
        }
        "reply_request" => s.reply_requests.push(d),
        "show" => {
            let page = d.get("page").str_or("");
            if !page.is_empty() && page != "pair" && page != "call" {
                std::thread::spawn(move || show(&page));
            }
        }
        _ => {}
    }
    false
}

fn json_str(j: &Json) -> String {
    match j {
        Json::Str(s) => s.clone(),
        Json::Num(n) => format!("{n}"),
        _ => String::new(),
    }
}

// «открыть Rexlink» — страница «Телефон» в Настройках (с нужной вкладкой)
pub fn show(page: &str) {
    let tab = match page {
        "" | "overview" | "pair" => "",
        "call" => "calls",
        p => p,
    };
    crate::prefs::Prefs::set("tab:5", tab);
    crate::prefs::show(5);
}

impl Service for Rexlink {
    fn new() -> Self {
        Rexlink { devices: Json::Arr(Vec::new()), notifs: Json::Arr(Vec::new()), screens: Json::Obj(Vec::new()), frames: Json::Obj(Vec::new()), ..Default::default() }
    }

    fn listen() {
        loop {
            let det = amane::output("{ systemctl --user cat rexlink.service || [ -S \"$XDG_RUNTIME_DIR/rexlink/rexlink.sock\" ]; } >/dev/null 2>&1 && echo yes; systemctl --user is-enabled rexlink.service 2>/dev/null");
            {
                let installed = det.contains("yes");
                let autostart = det.contains("enabled");
                let r = Rexlink::read();
                let changed = r.installed != installed || r.autostart != autostart;
                drop(r);
                if changed {
                    let mut w = Rexlink::write();
                    w.installed = installed;
                    w.autostart = autostart;
                }
            }
            if let Ok(stream) = UnixStream::connect(sock_path()) {
                let reader = stream.try_clone().ok();
                *conn().writer.lock().unwrap() = Some(stream);
                Rexlink::write().connected = true;
                cmd("subscribe", Json::Obj(Vec::new()));
                refresh();
                if let Some(rd) = reader {
                    for line in BufReader::new(rd).lines() {
                        let Ok(line) = line else { break };
                        let Some(m) = Json::parse(&line) else { continue };
                        if let Some(id) = m.get("id").num() {
                            let cb = conn().pending.lock().unwrap().remove(&(id as u64));
                            if let Some(cb) = cb {
                                let ok = m.get("ok").bool_or(false);
                                cb(if ok { Some(m.get("result").clone()) } else { None });
                                continue;
                            }
                        }
                        let need = handle(&mut Rexlink::write(), &m);
                        if need {
                            refresh();
                        }
                    }
                }
                *conn().writer.lock().unwrap() = None;
                conn().pending.lock().unwrap().clear();
                let mut w = Rexlink::write();
                w.connected = false;
                w.devices = Json::Arr(Vec::new());
                w.notifs = Json::Arr(Vec::new());
                w.screens = Json::Obj(Vec::new());
                w.frames = Json::Obj(Vec::new());
            }
            // переподключение, если службу перезапустили
            std::thread::sleep(Duration::from_secs(4));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn st() -> Rexlink {
        let mut s = Rexlink::new();
        s.current = "a".into();
        s
    }

    #[test]
    fn events_route_by_device() {
        let mut s = st();
        handle(&mut s, &Json::parse(r#"{"event":"status","data":{"device":"a","battery":50}}"#).unwrap());
        handle(&mut s, &Json::parse(r#"{"event":"status","data":{"device":"b","battery":20}}"#).unwrap());
        assert_eq!(s.status.get("battery").num(), Some(50.0));
        assert_eq!(s.status_for("b").get("battery").num(), Some(20.0));
        handle(&mut s, &Json::parse(r#"{"event":"notification","data":{"device":"a","key":"k1","title":"x"}}"#).unwrap());
        handle(&mut s, &Json::parse(r#"{"event":"notification","data":{"device":"a","key":"k2","title":"y"}}"#).unwrap());
        handle(&mut s, &Json::parse(r#"{"event":"notification","data":{"device":"a","key":"k1","title":"x2"}}"#).unwrap());
        assert_eq!(s.notifs.arr().len(), 2);
        assert_eq!(s.notifs.at(0).get("title").str(), Some("x2"));
        handle(&mut s, &Json::parse(r#"{"event":"notification_removed","data":{"device":"a","key":"k2"}}"#).unwrap());
        assert_eq!(s.notifs.arr().len(), 1);
        assert!(handle(&mut s, &Json::parse(r#"{"event":"device_connected","data":{}}"#).unwrap()));
    }

    #[test]
    fn devices_event_picks_current() {
        let mut s = st();
        s.current = "gone".into();
        handle(&mut s, &Json::parse(r#"{"event":"devices","data":[{"id":"x","current":false},{"id":"y","current":true}]}"#).unwrap());
        assert_eq!(s.current, "y");
    }

    #[test]
    fn formats() {
        assert_eq!(bytes(0.0, false), "0 B");
        assert_eq!(bytes(1536.0, false), "1.5 KB");
        assert_eq!(bytes(5.0 * 1024.0 * 1024.0 * 1024.0 * 20.0, true), "100 ГБ");
        assert_eq!(duration(65_000.0), "1:05");
        assert_eq!(duration(3_725_000.0), "1:02:05");
        assert_eq!(initials("Ivan Petrov"), "IP");
        assert_eq!(initials("+7 999 123"), "#");
        assert_eq!(initials(""), "?");
        assert_eq!(battery_icon(55, false), 0xF007E);
        assert_eq!(battery_icon(100, false), 0xF0079);
        assert_eq!(wifi_icon(9), 0xF0928);
    }
}
