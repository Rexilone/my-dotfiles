// команды для видов: вид просит результат по ключу, команда выполняется в фоне, окно перерисовывается,
// когда ответ готов. Вид не ждёт и не пишет в сервисы — запросы идут через свою очередь.

use std::collections::{HashMap, HashSet};
use std::sync::{Condvar, Mutex, OnceLock};
use std::time::Duration;

use amane::Service;

#[derive(Default)]
pub struct Cmd {
    results: HashMap<String, String>,
}

struct Queue {
    jobs: Mutex<(Vec<(String, String)>, HashSet<String>)>,
    wake: Condvar,
}

fn queue() -> &'static Queue {
    static Q: OnceLock<Queue> = OnceLock::new();
    Q.get_or_init(|| Queue { jobs: Mutex::new((Vec::new(), HashSet::new())), wake: Condvar::new() })
}

fn push(key: &str, script: &str) {
    let q = queue();
    let mut j = q.jobs.lock().unwrap();
    if j.1.insert(key.to_string()) {
        j.0.push((key.to_string(), script.to_string()));
        q.wake.notify_one();
    }
}

impl Service for Cmd {
    fn new() -> Self {
        Cmd::default()
    }

    fn interval() -> Duration {
        Duration::from_secs(3600)
    }

    // несколько потоков: медленная команда (pacman, lspci) не держит остальные
    fn listen() {
        for _ in 0..3 {
            std::thread::spawn(worker);
        }
        worker();
    }
}

fn worker() {
    let q = queue();
    loop {
        let (key, script) = {
            let mut j = q.jobs.lock().unwrap();
            while j.0.is_empty() {
                j = q.wake.wait(j).unwrap();
            }
            j.0.remove(0)
        };
        let out = amane::output(&script);
        q.jobs.lock().unwrap().1.remove(&key);
        let same = Cmd::read().results.get(&key) == Some(&out);
        if !same {
            Cmd::write().results.insert(key, out);
        }
    }
}

// результат (или None, пока выполняется); первый вызов запускает команду
pub fn get(key: &str, script: &str) -> Option<String> {
    let r = Cmd::read().results.get(key).cloned();
    if r.is_none() {
        push(key, script);
    }
    r
}

// выполнить заново (старый результат виден, пока не придёт новый)
pub fn refresh(key: &str, script: &str) {
    push(key, script);
}

// забыть результат — следующий get выполнит команду
pub fn forget(key: &str) {
    if Cmd::read().results.contains_key(key) {
        Cmd::write().results.remove(key);
    }
}

// строки «ключ=значение» → словарь
pub fn kv(text: &str) -> HashMap<String, String> {
    text.lines().filter_map(|l| l.split_once('=').map(|(k, v)| (k.trim().to_string(), v.to_string()))).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn key_values() {
        let m = kv("os=Arch Linux\nram=31.3 GB\nbad line\nx==y\n");
        assert_eq!(m.get("os").map(String::as_str), Some("Arch Linux"));
        assert_eq!(m.get("x").map(String::as_str), Some("=y"));
        assert_eq!(m.len(), 3);
    }
}
