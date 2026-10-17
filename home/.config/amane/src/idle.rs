// простой компьютера: блокировка, выключение экранов, сон (как Power.qml) — через swayidle;
// «Не засыпать» (caffeine) отключает все таймеры. Видео и игры не дают уснуть сами (idle-inhibit).

use std::process::{Child, Command, Stdio};
use std::time::Duration;

use amane::Service;

use crate::json::Json;
use crate::settings::Settings;

#[derive(Default)]
pub struct Idle {
    pub caffeine: bool,
}

pub const LOCK: &str = "pgrep -x swaylock >/dev/null || swaylock -f -c 151515";

pub fn lock() {
    amane::spawn(LOCK);
}

pub fn suspend_cmd(lock_first: bool) -> String {
    if lock_first { format!("{LOCK}; sleep 0.5; systemctl suspend") } else { "systemctl suspend".into() }
}

pub fn suspend() {
    let l = Settings::read().raw.get("power").get("lockOnSuspend").bool_or(true);
    amane::spawn(&suspend_cmd(l));
}

// аргументы swayidle по настройкам (минуты); пусто — таймеров нет
pub fn args(power: &Json) -> Vec<String> {
    let m = |k: &str| power.get(k).num_or(0.0).max(0.0) as i64;
    let mut a: Vec<String> = Vec::new();
    if m("lock") > 0 {
        a.extend(["timeout".into(), (m("lock") * 60).to_string(), LOCK.into()]);
    }
    if m("screenOff") > 0 {
        // экраны включатся сами при движении мыши или нажатии клавиши
        a.extend(["timeout".into(), (m("screenOff") * 60).to_string(), "niri msg action power-off-monitors".into()]);
    }
    if m("suspend") > 0 {
        a.extend(["timeout".into(), (m("suspend") * 60).to_string(), suspend_cmd(power.get("lockOnSuspend").bool_or(true))]);
    }
    a
}

pub fn ipc(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("lock") => lock(),
        _ => {
            let mut w = Idle::write();
            w.caffeine = !w.caffeine;
        }
    }
    String::from("ok")
}

impl Service for Idle {
    fn new() -> Self {
        Idle::default()
    }

    fn listen() {
        let mut child: Option<(Child, Vec<String>)> = None;
        loop {
            let caffeine = Idle::read().caffeine;
            let want = if caffeine { Vec::new() } else { args(Settings::read().raw.get("power")) };
            let same = match &child {
                Some((_, a)) => *a == want,
                None => want.is_empty(),
            };
            if !same {
                if let Some((mut c, _)) = child.take() {
                    let _ = c.kill();
                    let _ = c.wait();
                }
                if !want.is_empty() {
                    if let Ok(c) = Command::new("swayidle").args(&want).stdout(Stdio::null()).stderr(Stdio::null()).spawn() {
                        child = Some((c, want));
                    }
                }
            }
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
    fn swayidle_args() {
        assert!(args(&Json::Null).is_empty());
        let p = Json::parse(r#"{"lock":5,"screenOff":10,"suspend":0,"lockOnSuspend":false}"#).unwrap();
        let a = args(&p);
        assert_eq!(a[0..2], ["timeout", "300"]);
        assert_eq!(a[3..6], ["timeout".to_string(), "600".into(), "niri msg action power-off-monitors".into()]);
        assert_eq!(a.len(), 6);
        let p = Json::parse(r#"{"suspend":30,"lockOnSuspend":true}"#).unwrap();
        assert!(args(&p)[2].ends_with("systemctl suspend") && args(&p)[2].contains("swaylock"));
    }
}
