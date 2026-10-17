// ночной свет через wlsunset (как NightLight.qml): тёплые цвета экрана вечером

use std::process::{Child, Command, Stdio};
use std::time::Duration;

use amane::Service;

use crate::json::Json;
use crate::settings::{self, Settings};
use crate::weather::Weather;

#[derive(Default)]
pub struct NightLight {
    pub installed: bool,
}

pub fn on() -> bool {
    Settings::read().raw.get("nightLight").get("enabled").bool_or(false)
}

pub fn toggle() {
    let v = !on();
    settings::save_path(&["nightLight", "enabled"], Json::Bool(v));
}

pub fn install() {
    amane::spawn("pkexec pacman -S --needed --noconfirm wlsunset");
}

// аргументы wlsunset: по закату/рассвету города из погоды или «всегда» (ночь почти весь день)
pub fn args(cfg: &Json, weather: Option<(f64, f64)>) -> Vec<String> {
    let t = cfg.get("temp").num_or(4500.0).round() as i64;
    match weather {
        Some((lat, lon)) if cfg.get("auto").bool_or(false) => {
            vec!["-t".into(), t.to_string(), "-T".into(), "6500".into(), "-l".into(), format!("{lat}"), "-L".into(), format!("{lon}")]
        }
        _ => vec!["-t".into(), t.to_string(), "-T".into(), (t + 1).min(6500).to_string(), "-s".into(), "00:00".into(), "-S".into(), "23:59".into(), "-d".into(), "1".into()],
    }
}

impl Service for NightLight {
    fn new() -> Self {
        NightLight { installed: !amane::output("command -v wlsunset").is_empty() }
    }

    fn listen() {
        let mut child: Option<(Child, Vec<String>)> = None;
        let mut tick = 0u32;
        loop {
            tick += 1;
            if tick % 15 == 0 {
                let i = !amane::output("command -v wlsunset").is_empty();
                if NightLight::read().installed != i {
                    NightLight::write().installed = i;
                }
            }
            let cfg = Settings::read().raw.get("nightLight").clone();
            let w = {
                let w = Weather::read();
                w.configured().then(|| (w.lat(), w.lon()))
            };
            let want = (cfg.get("enabled").bool_or(false) && NightLight::read().installed).then(|| args(&cfg, w));
            let same = match (&child, &want) {
                (Some((_, a)), Some(b)) => a == b,
                (None, None) => true,
                _ => false,
            };
            if !same {
                if let Some((mut c, _)) = child.take() {
                    let _ = c.kill();
                    let _ = c.wait();
                }
                if let Some(a) = want {
                    if let Ok(c) = Command::new("wlsunset").args(&a).stdout(Stdio::null()).stderr(Stdio::null()).spawn() {
                        child = Some((c, a));
                    }
                }
            }
            // упал — перезапуск в следующем круге
            if let Some((c, _)) = &mut child {
                if c.try_wait().ok().flatten().is_some() {
                    child = None;
                }
            }
            std::thread::sleep(Duration::from_secs(1));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wlsunset_args() {
        let cfg = Json::parse(r#"{"enabled":true,"temp":4100,"auto":false}"#).unwrap();
        assert_eq!(args(&cfg, Some((55.0, 82.9))), vec!["-t", "4100", "-T", "4101", "-s", "00:00", "-S", "23:59", "-d", "1"]);
        let cfg = Json::parse(r#"{"temp":3000,"auto":true}"#).unwrap();
        assert_eq!(args(&cfg, Some((55.0, 82.9))), vec!["-t", "3000", "-T", "6500", "-l", "55", "-L", "82.9"]);
        // город не задан — как «всегда»
        assert_eq!(args(&cfg, None)[3], "3001");
    }
}
