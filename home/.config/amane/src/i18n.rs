// перевод интерфейса (как I18n.qml): английская строка → русская по словарю data/i18n-ru.json;
// нет перевода — исходный текст. «A   ·   B» переводится по частям.

use std::collections::HashMap;
use std::sync::OnceLock;

use crate::json::Json;

fn dict() -> &'static HashMap<String, String> {
    static D: OnceLock<HashMap<String, String>> = OnceLock::new();
    D.get_or_init(|| {
        let j = Json::parse(include_str!("../data/i18n-ru.json")).unwrap_or(Json::Null);
        j.obj().iter().filter_map(|(k, v)| v.str().map(|v| (k.clone(), v.to_string()))).collect()
    })
}

pub fn tr(ru: bool, s: &str) -> String {
    if !ru || s.is_empty() {
        return s.to_string();
    }
    let d = dict();
    if let Some(v) = d.get(s) {
        return v.clone();
    }
    let t = s.trim();
    if let Some(v) = d.get(t) {
        return s.replacen(t, v, 1);
    }
    if s.contains(" · ") {
        // части и разделители (с пробелами вокруг ·) — по отдельности
        let mut out = String::new();
        let mut rest = s;
        while let Some(i) = rest.find('·') {
            let (part, tail) = rest.split_at(i);
            let lead = part.trim_end();
            let gap = &part[lead.len()..];
            out += &tr_part(d, lead);
            out += gap;
            out.push('·');
            let tail = &tail['·'.len_utf8()..];
            let next = tail.trim_start();
            out += &tail[..tail.len() - next.len()];
            rest = next;
        }
        out += &tr_part(d, rest);
        return out;
    }
    s.to_string()
}

fn tr_part(d: &HashMap<String, String>, p: &str) -> String {
    let t = p.trim();
    match d.get(t) {
        Some(v) if !t.is_empty() => p.replacen(t, v, 1),
        _ => p.to_string(),
    }
}

// число + форма слова: plural(ru, 5, "app", "apps", "приложение", "приложения", "приложений")
pub fn plural<'a>(ru: bool, n: i64, one: &'a str, many: &'a str, ru1: &'a str, ru2: &'a str, ru5: &'a str) -> &'a str {
    if !ru {
        return if n == 1 { one } else { many };
    }
    let a = n.abs() % 100;
    let b = a % 10;
    if a > 10 && a < 20 {
        ru5
    } else if b == 1 {
        ru1
    } else if (2..=4).contains(&b) {
        ru2
    } else {
        ru5
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn translates_known_and_keeps_unknown() {
        assert_eq!(tr(true, "Restart shell"), "Перезапустить оболочку");
        assert_eq!(tr(false, "Restart shell"), "Restart shell");
        assert_eq!(tr(true, "Нет такого ключа xyz"), "Нет такого ключа xyz");
        assert_eq!(tr(true, ""), "");
        // пробелы по краям сохраняются
        assert_eq!(tr(true, "  Restart shell "), "  Перезапустить оболочку ");
    }

    #[test]
    fn composite_parts() {
        assert_eq!(tr(true, "Restart shell   ·   xyz"), "Перезапустить оболочку   ·   xyz");
        assert_eq!(tr(true, "a · Restart shell"), "a · Перезапустить оболочку");
    }

    #[test]
    fn dictionary_is_big() {
        assert!(dict().len() > 1000);
    }

    #[test]
    fn plurals() {
        assert_eq!(plural(true, 1, "app", "apps", "приложение", "приложения", "приложений"), "приложение");
        assert_eq!(plural(true, 3, "", "", "a", "b", "c"), "b");
        assert_eq!(plural(true, 11, "", "", "a", "b", "c"), "c");
        assert_eq!(plural(true, 21, "", "", "a", "b", "c"), "a");
        assert_eq!(plural(false, 2, "app", "apps", "", "", ""), "apps");
    }
}
