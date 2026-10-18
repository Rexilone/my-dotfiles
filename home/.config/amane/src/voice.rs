// голосовой ввод — Voxtype (Voice.qml): служба voxtype.service, Super+H — начать/закончить запись,
// распознанный текст печатается в активное окно. По умолчанию не ставится и не запускается:
// всё включается в Настройках → Голосовой ввод. Состояние — `voxtype status --follow --format json`

use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::time::Duration;

use amane::Service;

use crate::niri::sh_quote;

#[derive(Default, Clone, PartialEq)]
pub struct Voice {
    pub installed: bool,
    pub running: bool,   // служба запущена
    pub autostart: bool, // включена при входе
    pub state: String,   // idle | recording | transcribing | stopped
    pub text: String,
    pub models: Vec<(String, bool)>, // whisper: имя, скачана ли
    pub downloading: String,
    pub busy: String, // что сейчас делается (установка, запуск…)
    pub config: Vec<(String, String)>,
}

impl Voice {
    pub fn get(&self, key: &str) -> String {
        self.config.iter().find(|(k, _)| k == key).map(|(_, v)| v.clone()).unwrap_or_default()
    }
}

pub const KEYS: [&str; 9] = [
    "whisper.model",
    "whisper.language",
    "whisper.translate",
    "whisper.on_demand_loading",
    "output.mode",
    "output.notification.on_transcription",
    "audio.max_duration_secs",
    "audio.feedback.enabled",
    "whisper.initial_prompt",
];

// «voxtype info models»: строки whisper-раздела, «installed» — скачана
pub fn parse_models(text: &str) -> Vec<(String, bool)> {
    let mut out = Vec::new();
    let mut inside = false;
    for l in text.lines() {
        let t = l.trim();
        if t == "whisper" {
            inside = true;
            continue;
        }
        if inside {
            if t.is_empty() {
                if !out.is_empty() {
                    break;
                }
                continue;
            }
            if !l.starts_with(' ') {
                break;
            }
            let installed = t.starts_with("installed");
            let name = t.trim_start_matches("installed").trim().split_whitespace().next().unwrap_or("").to_string();
            if !name.is_empty() {
                out.push((name, installed));
            }
        }
    }
    out
}

// состояние из строки status --format json
pub fn parse_state(j: &crate::json::Json) -> String {
    let s = [j.get("class"), j.get("alt"), j.get("state")].iter().filter_map(|v| v.str()).next().unwrap_or("idle").to_lowercase();
    if s.contains("record") {
        "recording"
    } else if s.contains("transcrib") || s.contains("process") {
        "transcribing"
    } else if s.contains("stop") || s.contains("off") || s.contains("error") {
        "stopped"
    } else {
        "idle"
    }
    .into()
}

fn probe() -> Voice {
    let out = amane::output("command -v voxtype >/dev/null && echo installed; systemctl --user is-active -q voxtype.service && echo running; systemctl --user is-enabled -q voxtype.service 2>/dev/null && echo enabled");
    let installed = out.lines().any(|l| l == "installed");
    let mut v = Voice { installed, running: out.lines().any(|l| l == "running"), autostart: out.lines().any(|l| l == "enabled"), state: "idle".into(), ..Default::default() };
    if installed {
        v.models = parse_models(&amane::output("voxtype info models 2>/dev/null"));
        let keys: Vec<String> = KEYS.iter().map(|k| sh_quote(k)).collect();
        let got = amane::output(&format!("for k in {}; do printf '%s=' \"$k\"; voxtype config get \"$k\" 2>/dev/null | head -1; done", keys.join(" ")));
        v.config = got.lines().filter_map(|l| l.split_once('=').map(|(a, b)| (a.to_string(), b.trim().to_string()))).collect();
    }
    v
}

pub fn refresh() {
    std::thread::spawn(|| {
        let mut n = probe();
        let cur = Voice::read();
        n.state = if n.running { cur.state.clone() } else { "stopped".into() };
        n.text = cur.text.clone();
        n.downloading = cur.downloading.clone();
        n.busy = cur.busy.clone();
        drop(cur);
        if *Voice::read() != n {
            *Voice::write() = n;
        }
    });
}

// служба лежит в дотфайлах ссылкой; `systemctl disable` у такой службы удаляет и ссылку — вернуть
const ENSURE_UNIT: &str = r#"u="$HOME/.config/systemd/user/voxtype.service"; d=$(readlink -f "$HOME/.config/amane"); src="${d%/home/.config/amane}/home/.config/systemd/user/voxtype.service"; [ -e "$u" ] || { [ -f "$src" ] && mkdir -p "${u%/*}" && ln -s "$src" "$u"; }; systemctl --user daemon-reload"#;

fn busy(what: &str) {
    Voice::write().busy = what.to_string();
}

// установить из AUR (voxtype-bin) — очередь «Программ», пароль спросит polkit
pub fn install() {
    crate::store::install("voxtype-bin", true);
    std::thread::spawn(|| {
        // дождаться конца установки и перечитать
        for _ in 0..600 {
            std::thread::sleep(Duration::from_secs(2));
            if crate::store::Store::read().busy_with("voxtype-bin").is_empty() {
                break;
            }
        }
        refresh();
    });
}

pub fn uninstall() {
    std::thread::spawn(|| {
        amane::output("systemctl --user disable --now voxtype.service 2>/dev/null");
        refresh();
    });
    crate::store::remove("voxtype-bin");
}

pub fn download(model: &str) {
    let m = model.to_string();
    Voice::write().downloading = m.clone();
    std::thread::spawn(move || {
        amane::output(&format!("voxtype setup --download --model {} --quiet --no-post-install 2>&1", sh_quote(&m)));
        Voice::write().downloading.clear();
        refresh();
    });
}

pub fn set(key: &str, value: &str) {
    let (k, v) = (key.to_string(), value.to_string());
    {
        let mut w = Voice::write();
        if let Some(e) = w.config.iter_mut().find(|(a, _)| *a == k) {
            e.1 = v.clone();
        } else {
            w.config.push((k.clone(), v.clone()));
        }
    }
    std::thread::spawn(move || {
        amane::output(&format!("voxtype config set {} {} 2>&1", sh_quote(&k), sh_quote(&v)));
        // настройки распознавания — после перезапуска службы
        if Voice::read().running {
            amane::output("systemctl --user restart voxtype.service");
        }
        refresh();
    });
}

// модель: выбрать (и скачать, если её нет)
pub fn use_model(m: &str) {
    let have = Voice::read().models.iter().any(|(n, i)| n == m && *i);
    if !have {
        let m2 = m.to_string();
        std::thread::spawn(move || {
            Voice::write().downloading = m2.clone();
            amane::output(&format!("voxtype setup --download --model {} --quiet --no-post-install 2>&1", sh_quote(&m2)));
            Voice::write().downloading.clear();
            set("whisper.model", &m2);
        });
    } else {
        set("whisper.model", m);
    }
}

pub fn set_running(on: bool) {
    busy(if on { "starting" } else { "stopping" });
    std::thread::spawn(move || {
        // без скачанной модели служба не стартует — скачать выбранную
        if on {
            let v = Voice::read().clone();
            let model = Some(v.get("whisper.model")).filter(|m| !m.is_empty()).unwrap_or_else(|| "small".into());
            if !v.models.iter().any(|(n, i)| *n == model && *i) {
                Voice::write().downloading = model.clone();
                amane::output(&format!("voxtype setup --download --model {} --quiet --no-post-install 2>&1", sh_quote(&model)));
                Voice::write().downloading.clear();
            }
        }
        amane::output(&format!("{ENSURE_UNIT}; systemctl --user {} voxtype.service", if on { "start" } else { "stop" }));
        busy("");
        refresh();
    });
}

pub fn set_autostart(on: bool) {
    Voice::write().autostart = on;
    std::thread::spawn(move || {
        amane::output(&format!("{ENSURE_UNIT}; systemctl --user {} voxtype.service; {ENSURE_UNIT}", if on { "enable" } else { "disable" }));
        refresh();
    });
}

// Super+H: служба выключена — включить и начать запись
pub fn toggle() {
    let v = Voice::read().clone();
    if !v.installed {
        let ru = crate::settings::Settings::read().c.ru();
        let (t, b) = if ru { ("Голосовой ввод не установлен", "Настройки → Голосовой ввод") } else { ("Voice typing is not installed", "Settings → Voice typing") };
        amane::spawn(&format!("notify-send -a Voxtype -i audio-input-microphone {} {}", sh_quote(t), sh_quote(b)));
        return;
    }
    if v.running {
        amane::spawn("voxtype record toggle");
    } else {
        std::thread::spawn(|| {
            set_running(true);
            for _ in 0..60 {
                std::thread::sleep(Duration::from_millis(500));
                if Voice::read().running && Voice::read().busy.is_empty() {
                    std::thread::sleep(Duration::from_millis(800));
                    amane::spawn("voxtype record toggle");
                    return;
                }
            }
        });
    }
}

pub fn ipc(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("status") => Voice::read().state.clone(),
        Some("start") => {
            set_running(true);
            "ok".into()
        }
        Some("stop") => {
            set_running(false);
            "ok".into()
        }
        _ => {
            toggle();
            "ok".into()
        }
    }
}

impl Service for Voice {
    fn new() -> Self {
        let mut v = probe();
        v.state = if v.running { "idle".into() } else { "stopped".into() };
        v
    }

    // поток состояния, пока служба работает; служба перезапустилась — подключаемся заново
    fn listen() {
        loop {
            if !Voice::read().running {
                std::thread::sleep(Duration::from_secs(3));
                let p = probe();
                if p.running != Voice::read().running || p.installed != Voice::read().installed {
                    refresh();
                }
                continue;
            }
            let Ok(mut child) = Command::new("voxtype").args(["status", "--follow", "--format", "json"]).stdout(Stdio::piped()).stderr(Stdio::null()).spawn() else {
                std::thread::sleep(Duration::from_secs(5));
                continue;
            };
            let out = child.stdout.take().unwrap();
            for line in BufReader::new(out).lines() {
                let Ok(line) = line else { break };
                let Some(j) = crate::json::Json::parse(&line) else { continue };
                let (s, t) = (parse_state(&j), [j.get("tooltip"), j.get("text")].iter().filter_map(|v| v.str()).next().unwrap_or("").to_string());
                let cur = Voice::read();
                let changed = cur.state != s || cur.text != t;
                drop(cur);
                if changed {
                    let mut w = Voice::write();
                    w.state = s;
                    w.text = t;
                }
                if !Voice::read().running {
                    break;
                }
            }
            let _ = child.kill();
            let _ = child.wait();
            Voice::write().state = "stopped".into();
            std::thread::sleep(Duration::from_secs(2));
            refresh();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn models_and_state() {
        let m = parse_models("Model catalog  (/x)\n\nwhisper\n             tiny\n             base.en (default)\n  installed  small\n\nparakeet\n             p1\n");
        assert_eq!(m, vec![("tiny".to_string(), false), ("base.en".to_string(), false), ("small".to_string(), true)]);
        let j = crate::json::Json::parse(r#"{"class":"recording","text":""}"#).unwrap();
        assert_eq!(parse_state(&j), "recording");
        let j = crate::json::Json::parse(r#"{"alt":"idle"}"#).unwrap();
        assert_eq!(parse_state(&j), "idle");
    }
}
