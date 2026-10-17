// подключённые устройства ввода (data/input-devices.py), как Devices.qml: опрашиваются раз в 3 с,
// пока их показывает страница «Периферия». И проверка геймпада: чтение /dev/input/jsN.

use std::io::Read;
use std::os::unix::fs::OpenOptionsExt;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use amane::Service;

use crate::json::Json;

#[derive(Default)]
pub struct Devices {
    pub list: Vec<Json>,
}

impl Devices {
    pub fn of(&self, kind: &str) -> Vec<Json> {
        self.list.iter().filter(|d| d.get("kind").str() == Some(kind)).cloned().collect()
    }
}

fn last_need() -> &'static Mutex<Option<Instant>> {
    static N: OnceLock<Mutex<Option<Instant>>> = OnceLock::new();
    N.get_or_init(|| Mutex::new(None))
}

// вид на экране — опрашивать
pub fn need() {
    *last_need().lock().unwrap() = Some(Instant::now());
}

pub fn kind_icon(kind: &str) -> u32 {
    match kind {
        "keyboard" => 0xF030C,
        "mouse" => 0xF037D,
        "touchpad" => 0xF0741,
        "tablet" => 0xF03EB,
        "gamepad" => 0xF0EB5,
        "printer" => 0xF042A,
        _ => 0xF0335,
    }
}

pub fn bus_label(d: &Json) -> &'static str {
    if d.get("bus").str() == Some("bluetooth") {
        return "Bluetooth";
    }
    if d.get("wireless").bool_or(false) {
        return "Wireless receiver";
    }
    match d.get("bus").str().unwrap_or("") {
        "usb" => "USB",
        "ps2" | "i2c" | "builtin" => "Built-in",
        _ => "Connected",
    }
}

fn fetch() {
    let script = crate::settings::home().join(".config/amane/data/input-devices.py");
    let out = amane::output(&format!("python3 {}", crate::niri::sh_quote(&script.to_string_lossy())));
    if let Some(Json::Arr(next)) = Json::parse(out.trim()) {
        if Devices::read().list != next {
            Devices::write().list = next;
        }
    }
}

impl Service for Devices {
    fn new() -> Self {
        Devices::default()
    }

    fn listen() {
        fetch();
        loop {
            std::thread::sleep(Duration::from_millis(500));
            let on = last_need().lock().unwrap().is_some_and(|t| t.elapsed() < Duration::from_secs(2));
            if on {
                fetch();
                std::thread::sleep(Duration::from_millis(2500));
            }
        }
    }
}

// ── проверка геймпада

#[derive(Default)]
pub struct Pad {
    pub node: String,
    pub axes: Vec<f32>,
    pub buttons: Vec<bool>,
}

static GEN: AtomicU64 = AtomicU64::new(0);

// событие js: u32 время, i16 значение, u8 тип (1 кнопка, 2 ось, 0x80 — начальное), u8 номер
pub fn apply_event(p: &mut Pad, e: &[u8]) {
    let value = i16::from_le_bytes([e[4], e[5]]);
    let typ = e[6] & !0x80;
    let num = e[7] as usize;
    match typ {
        1 => {
            if p.buttons.len() <= num {
                p.buttons.resize(num + 1, false);
            }
            p.buttons[num] = value != 0;
        }
        2 => {
            if p.axes.len() <= num {
                p.axes.resize(num + 1, 0.0);
            }
            p.axes[num] = (value as f32 / 32767.0).clamp(-1.0, 1.0);
        }
        _ => {}
    }
}

pub fn test_start(node: &str) {
    let g = GEN.fetch_add(1, Ordering::SeqCst) + 1;
    let node = node.rsplit('/').next().unwrap_or(node).to_string();
    *Pad::write() = Pad { node: node.clone(), ..Default::default() };
    std::thread::spawn(move || {
        // O_NONBLOCK: поток сам проверяет, не пора ли остановиться
        let Ok(mut f) = std::fs::OpenOptions::new().read(true).custom_flags(0o4000).open(format!("/dev/input/{node}")) else {
            test_stop();
            return;
        };
        let mut buf = [0u8; 8 * 64];
        let mut last = Instant::now();
        let mut local = Pad { node: node.clone(), ..Default::default() };
        let mut dirty = true;
        while GEN.load(Ordering::SeqCst) == g {
            match f.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    for e in buf[..n].chunks_exact(8) {
                        apply_event(&mut local, e);
                    }
                    dirty = true;
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => std::thread::sleep(Duration::from_millis(15)),
                Err(_) => break, // геймпад отключили
            }
            if dirty && last.elapsed() >= Duration::from_millis(33) && GEN.load(Ordering::SeqCst) == g {
                let mut p = Pad::write();
                p.axes = local.axes.clone();
                p.buttons = local.buttons.clone();
                last = Instant::now();
                dirty = false;
            }
        }
        if GEN.load(Ordering::SeqCst) == g {
            test_stop();
        }
    });
}

pub fn test_stop() {
    GEN.fetch_add(1, Ordering::SeqCst);
    if !Pad::read().node.is_empty() {
        *Pad::write() = Pad::default();
    }
}

impl Service for Pad {
    fn new() -> Self {
        Pad::default()
    }

    fn listen() {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn js_events() {
        let mut p = Pad::default();
        apply_event(&mut p, &[0, 0, 0, 0, 1, 0, 0x81, 3]);
        apply_event(&mut p, &[0, 0, 0, 0, 0x01, 0x80, 2, 1]);
        assert_eq!(p.buttons, vec![false, false, false, true]);
        assert_eq!(p.axes.len(), 2);
        assert!((p.axes[1] + 1.0).abs() < 0.001);
        let d = Json::parse(r#"{"bus":"usb","wireless":true}"#).unwrap();
        assert_eq!(bus_label(&d), "Wireless receiver");
    }
}
