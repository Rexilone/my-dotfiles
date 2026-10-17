// уровень звука узла для индикатора у ползунка (как LevelMeter.qml): процесс pw-record на каждый узел,
// который сейчас на экране; не нужен — останавливается

use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use amane::Service;

#[derive(Default)]
pub struct Meter {
    pub levels: HashMap<String, f32>,
}

// кто и когда последний раз спрашивал уровень
fn wanted() -> &'static Mutex<HashMap<String, (bool, Instant)>> {
    static W: OnceLock<Mutex<HashMap<String, (bool, Instant)>>> = OnceLock::new();
    W.get_or_init(|| Mutex::new(HashMap::new()))
}

fn script() -> String {
    crate::settings::home().join(".config/amane/data/level-meter.py").to_string_lossy().to_string()
}

// −60 дБ … 0 дБ → 0 … 1; мгновенная атака, плавный спад
pub fn smooth(prev: f32, peak: f32) -> f32 {
    let v = if peak > 0.001 { (1.0 + 20.0 * peak.log10() / 60.0).max(0.0) } else { 0.0 };
    if v > prev { v } else { prev * 0.75 + v * 0.25 }
}

// уровень 0..1 (вид спрашивает каждый кадр, пока показывает индикатор)
pub fn level(target: &str, sink: bool) -> f32 {
    if target.is_empty() {
        return 0.0;
    }
    wanted().lock().unwrap().insert(target.to_string(), (sink, Instant::now()));
    // кадры, пока идёт уровень
    amane::request_frame();
    let goal = Meter::read().levels.get(target).copied().unwrap_or(0.0);
    ease(target, goal)
}

// показ плавно догоняет уровень (как Behavior on width, 70 мс в Quickshell)
fn ease(target: &str, goal: f32) -> f32 {
    static SHOWN: OnceLock<Mutex<HashMap<String, (f32, Instant)>>> = OnceLock::new();
    let mut m = SHOWN.get_or_init(|| Mutex::new(HashMap::new())).lock().unwrap();
    let e = m.entry(target.to_string()).or_insert((goal, Instant::now()));
    let dt = e.1.elapsed().as_secs_f32();
    e.0 = approach(e.0, goal, dt);
    e.1 = Instant::now();
    e.0
}

pub fn approach(from: f32, to: f32, dt: f32) -> f32 {
    from + (to - from) * (1.0 - (-dt / 0.035).exp())
}

impl Service for Meter {
    fn new() -> Self {
        Meter::default()
    }

    fn listen() {
        let mut running: HashMap<String, Child> = HashMap::new();
        loop {
            let want: Vec<(String, bool)> = {
                let mut w = wanted().lock().unwrap();
                w.retain(|_, (_, at)| at.elapsed() < Duration::from_millis(1500));
                w.iter().map(|(k, (s, _))| (k.clone(), *s)).collect()
            };
            // лишние — остановить
            let stale: Vec<String> = running.keys().filter(|k| !want.iter().any(|(t, _)| t == *k)).cloned().collect();
            for k in stale {
                if let Some(mut c) = running.remove(&k) {
                    let _ = c.kill();
                    let _ = c.wait();
                }
                Meter::write().levels.remove(&k);
            }
            for (target, sink) in want {
                if running.contains_key(&target) {
                    continue;
                }
                let Ok(mut child) = Command::new("python3")
                    .arg("-u")
                    .arg(script())
                    .arg(&target)
                    .arg(if sink { "1" } else { "0" })
                    .stdout(Stdio::piped())
                    .stderr(Stdio::null())
                    .spawn()
                else {
                    continue;
                };
                let out = child.stdout.take();
                running.insert(target.clone(), child);
                if let Some(out) = out {
                    std::thread::spawn(move || {
                        for line in BufReader::new(out).lines() {
                            let Ok(line) = line else { break };
                            let peak: f32 = line.trim().parse().unwrap_or(0.0);
                            let prev = Meter::read().levels.get(&target).copied().unwrap_or(0.0);
                            let v = smooth(prev, peak);
                            if (v - prev).abs() > 0.005 {
                                Meter::write().levels.insert(target.clone(), v);
                            }
                        }
                    });
                }
            }
            std::thread::sleep(Duration::from_millis(300));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eases_toward_level() {
        assert!((approach(0.0, 1.0, 0.0)).abs() < 1e-6);
        let half = approach(0.0, 1.0, 0.035);
        assert!(half > 0.6 && half < 0.66);
        assert!((approach(0.0, 1.0, 1.0) - 1.0).abs() < 1e-3);
    }

    #[test]
    fn decibel_scale() {
        assert_eq!(smooth(0.0, 0.0), 0.0);
        assert!((smooth(0.0, 1.0) - 1.0).abs() < 1e-6);
        assert!((smooth(0.0, 0.1) - (1.0 - 20.0 / 60.0)).abs() < 1e-5);
        // спад плавный
        let v = smooth(1.0, 0.0);
        assert!((v - 0.75).abs() < 1e-6);
    }
}
