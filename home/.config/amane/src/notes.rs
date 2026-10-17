// заметки календаря + напоминания (Notes.qml): заметка со временем приходит уведомлением;
// пропущенные, пока ПК был выключен, — при следующем запуске. Файл общий с Quickshell (notes.json)

use std::path::PathBuf;
use std::time::Duration;

use amane::Service;

use crate::clock::{self, Civil, Clock};
use crate::json::Json;
use crate::niri::sh_quote;

#[derive(Default)]
pub struct Notes {
    // "yyyy-MM-dd" -> [{ id, text, time, notified }]
    pub notes: Json,
}

pub fn path() -> PathBuf {
    crate::settings::path().with_file_name("notes.json")
}

pub fn key(y: i64, m: u32, d: u32) -> String {
    format!("{y:04}-{m:02}-{d:02}")
}

impl Notes {
    pub fn list(&self, k: &str) -> Vec<Json> {
        let mut v = self.notes.get(k).arr().to_vec();
        let t = |n: &Json| Some(n.get("time").str_or("")).filter(|x| !x.is_empty()).unwrap_or_else(|| "99:99".into());
        v.sort_by_key(t);
        v
    }
    pub fn has(&self, k: &str) -> bool {
        !self.notes.get(k).arr().is_empty()
    }
}

// «9:5» не годится, «930» → 09:30, «9:30» → 09:30
pub fn norm_time(t: &str) -> String {
    let t = t.trim();
    let digits: String = t.chars().filter(|c| *c != ':').collect();
    if digits.len() < 3 || digits.len() > 4 || !digits.chars().all(|c| c.is_ascii_digit()) || t.matches(':').count() > 1 {
        return String::new();
    }
    if let Some((h, m)) = t.split_once(':') {
        if m.len() != 2 {
            return String::new();
        }
        let _ = h;
    }
    let (h, m) = digits.split_at(digits.len() - 2);
    let (h, m): (u32, u32) = (h.parse().unwrap_or(99), m.parse().unwrap_or(99));
    if h > 23 || m > 59 {
        return String::new();
    }
    format!("{h:02}:{m:02}")
}

fn save(next: Json) {
    let text = Json::Obj(vec![("notes".into(), next.clone())]).pretty_with(4);
    Notes::write().notes = next;
    let _ = std::fs::create_dir_all(path().parent().unwrap());
    let _ = std::fs::write(path(), text);
}

fn now_civil() -> (Civil, i64) {
    let c = Clock::read();
    (c.now(), c.offset)
}

// минуты с начала эпохи для ключа дня и времени (по местному времени)
fn due_min(k: &str, time: &str, offset: i64) -> Option<i64> {
    let p: Vec<i64> = k.split('-').filter_map(|x| x.parse().ok()).collect();
    let (h, m) = time.split_once(':')?;
    let days = crate::popups::days_from_civil(*p.first()?, *p.get(1)? as u32, *p.get(2)? as u32);
    Some((days * 86400 + h.parse::<i64>().ok()? * 3600 + m.parse::<i64>().ok()? * 60 - offset) / 60)
}

fn now_min() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64 / 60).unwrap_or(0)
}

pub fn add(k: &str, text: &str, time: &str) {
    let text = text.trim();
    if text.is_empty() {
        return;
    }
    let t = norm_time(time);
    let (_, offset) = now_civil();
    // напоминание в прошлом не присылаем — его только что создали
    let notified = !t.is_empty() && due_min(k, &t, offset).is_some_and(|d| d <= now_min());
    let id = format!("{}{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0), std::process::id() % 1000);
    let mut next = Notes::read().notes.clone();
    if !matches!(next, Json::Obj(_)) {
        next = Json::Obj(Vec::new());
    }
    let mut day = next.get(k).arr().to_vec();
    day.push(Json::Obj(vec![
        ("id".into(), Json::Str(id)),
        ("text".into(), Json::Str(text.into())),
        ("time".into(), Json::Str(t)),
        ("notified".into(), Json::Bool(notified)),
    ]));
    next.set(k, Json::Arr(day));
    save(next);
}

pub fn remove(k: &str, id: &str) {
    let mut next = Notes::read().notes.clone();
    let day: Vec<Json> = next.get(k).arr().iter().filter(|n| n.get("id").str() != Some(id)).cloned().collect();
    if let Json::Obj(items) = &mut next {
        if day.is_empty() {
            items.retain(|(x, _)| x != k);
        } else if let Some(v) = next.get_mut(k) {
            *v = Json::Arr(day);
        }
    }
    save(next);
}

fn check() {
    let (_, offset) = now_civil();
    let now = now_min();
    let mut next = Notes::read().notes.clone();
    let mut changed = false;
    let ru = crate::settings::Settings::read().c.ru();
    if let Json::Obj(days) = &mut next {
        for (k, list) in days.iter_mut() {
            if let Json::Arr(items) = list {
                for n in items.iter_mut() {
                    let time = n.get("time").str_or("");
                    if time.is_empty() || n.get("notified").bool_or(false) {
                        continue;
                    }
                    let Some(due) = due_min(k, &time, offset) else { continue };
                    if due > now {
                        continue;
                    }
                    let missed = now - due > 2;
                    let when = if missed {
                        let c = clock::civil(due * 60, offset);
                        format!("{}, {time}", clock::format("d MMM", &c, ru))
                    } else {
                        time.clone()
                    };
                    let title = match (missed, ru) {
                        (true, true) => format!("Пропущенное напоминание · {when}"),
                        (true, false) => format!("Missed reminder · {when}"),
                        (false, true) => format!("Напоминание · {when}"),
                        (false, false) => format!("Reminder · {when}"),
                    };
                    amane::spawn(&format!("notify-send -a Calendar -u critical -i x-office-calendar {} {}", sh_quote(&title), sh_quote(&n.get("text").str_or(""))));
                    n.set("notified", Json::Bool(true));
                    changed = true;
                }
            }
        }
    }
    if changed {
        save(next);
    }
}

fn load() -> Json {
    std::fs::read_to_string(path()).ok().and_then(|t| Json::parse(&t)).map(|j| j.get("notes").clone()).filter(|n| matches!(n, Json::Obj(_))).unwrap_or(Json::Obj(Vec::new()))
}

impl Service for Notes {
    fn new() -> Self {
        Notes { notes: load() }
    }

    // Quickshell мог поменять файл — перечитать; напоминания — раз в 20 с
    fn listen() {
        let mtime = || std::fs::metadata(path()).and_then(|m| m.modified()).ok();
        let mut seen = mtime();
        loop {
            if mtime() != seen {
                seen = mtime();
                let n = load();
                if Notes::read().notes != n {
                    Notes::write().notes = n;
                }
            }
            if !crate::look::no_services() {
                check();
                seen = mtime();
            }
            std::thread::sleep(Duration::from_secs(20));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn times() {
        assert_eq!(norm_time("9:30"), "09:30");
        assert_eq!(norm_time("930"), "09:30");
        assert_eq!(norm_time("2359"), "23:59");
        assert_eq!(norm_time("24:00"), "");
        assert_eq!(norm_time("9:5"), "");
        assert_eq!(norm_time(""), "");
        assert_eq!(key(2026, 3, 7), "2026-03-07");
        // 2026-03-07 09:30 по UTC+3 = 06:30 UTC
        let d = due_min("2026-03-07", "09:30", 3 * 3600).unwrap();
        assert_eq!(d, (crate::popups::days_from_civil(2026, 3, 7) * 86400 + 6 * 3600 + 30 * 60) / 60);
    }
}
