// поиск меню приложений — как Launcher.qml: очки совпадения, «ашкуащч» → firefox, калькулятор

use std::collections::HashMap;

use crate::apps::Entry;

const RU: &str = "йцукенгшщзхъфывапролджэячсмитьбю";
const EN: &str = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";

// набрано в русской раскладке — те же клавиши в английской
pub fn translit(q: &str) -> String {
    let ru: Vec<char> = RU.chars().collect();
    let en: Vec<char> = EN.chars().collect();
    q.chars().map(|c| ru.iter().position(|r| *r == c).map(|i| en[i]).unwrap_or(c)).collect()
}

pub fn score(e: &Entry, q: &str) -> i32 {
    let name = e.name.to_lowercase();
    if name == q {
        return 1000;
    }
    if name.starts_with(q) {
        return 800;
    }
    if name.split([' ', '-', '_', '.']).any(|w| !w.is_empty() && w.starts_with(q)) {
        return 600;
    }
    if name.contains(q) {
        return 400;
    }
    let extra = [e.generic.as_str(), &e.comment, &e.id, &e.keywords.join(" ")].join(" ").to_lowercase();
    if extra.contains(q) {
        return 200;
    }
    // буквы по порядку («ffx» → firefox)
    let qc: Vec<char> = q.chars().collect();
    let mut i = 0;
    for c in name.chars() {
        if i < qc.len() && c == qc[i] {
            i += 1;
        }
    }
    if i == qc.len() { 100 } else { -1 }
}

// ── калькулятор: цифры, скобки, + - * / % ^

pub fn calc(q: &str) -> Option<String> {
    let s: String = q
        .replace(',', ".")
        .replace('×', "*")
        .replace('÷', "/")
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect();
    if s.is_empty() || !s.chars().all(|c| c.is_ascii_digit() || "+-*/%().^".contains(c)) {
        return None;
    }
    // нужна хотя бы одна операция: «12» — не пример
    let b: Vec<char> = s.chars().collect();
    let has_op = b.windows(2).any(|w| (w[0].is_ascii_digit() || w[0] == ')') && "+-*/%^".contains(w[1]))
        || s.starts_with("-(")
        || s.starts_with('(');
    if !has_op {
        return None;
    }
    let mut p = Calc { s: b, i: 0 };
    let v = p.expr()?;
    if p.i != p.s.len() || !v.is_finite() {
        return None;
    }
    Some(fmt_num(v))
}

// как Number(v.toPrecision(12)) в JS
pub fn fmt_num(v: f64) -> String {
    if v == 0.0 {
        return "0".into();
    }
    let digits = 12 - 1 - v.abs().log10().floor() as i32;
    let r = if digits >= 0 {
        let k = 10f64.powi(digits.min(300));
        (v * k).round() / k
    } else {
        let k = 10f64.powi(-digits);
        (v / k).round() * k
    };
    let mut s = format!("{r}");
    if s.contains('.') && !s.contains('e') {
        while s.ends_with('0') {
            s.pop();
        }
        if s.ends_with('.') {
            s.pop();
        }
    }
    s
}

struct Calc {
    s: Vec<char>,
    i: usize,
}

impl Calc {
    fn peek(&self) -> Option<char> {
        self.s.get(self.i).copied()
    }

    fn expr(&mut self) -> Option<f64> {
        let mut v = self.term()?;
        while let Some(c) = self.peek() {
            match c {
                '+' => {
                    self.i += 1;
                    v += self.term()?
                }
                '-' => {
                    self.i += 1;
                    v -= self.term()?
                }
                _ => break,
            }
        }
        Some(v)
    }

    fn term(&mut self) -> Option<f64> {
        let mut v = self.power()?;
        while let Some(c) = self.peek() {
            match c {
                '*' => {
                    self.i += 1;
                    v *= self.power()?
                }
                '/' => {
                    self.i += 1;
                    v /= self.power()?
                }
                '%' => {
                    self.i += 1;
                    v %= self.power()?
                }
                _ => break,
            }
        }
        Some(v)
    }

    // ^ — справа налево, сильнее унарного минуса слева: -2^2 = -4
    fn power(&mut self) -> Option<f64> {
        let base = self.unary()?;
        if self.peek() == Some('^') {
            self.i += 1;
            let exp = self.power()?;
            return Some(base.powf(exp));
        }
        Some(base)
    }

    fn unary(&mut self) -> Option<f64> {
        match self.peek()? {
            '-' => {
                self.i += 1;
                Some(-self.unary()?)
            }
            '+' => {
                self.i += 1;
                self.unary()
            }
            _ => self.atom(),
        }
    }

    fn atom(&mut self) -> Option<f64> {
        if self.peek()? == '(' {
            self.i += 1;
            let v = self.expr()?;
            if self.peek()? != ')' {
                return None;
            }
            self.i += 1;
            return Some(v);
        }
        let start = self.i;
        while self.peek().is_some_and(|c| c.is_ascii_digit() || c == '.') {
            self.i += 1;
        }
        self.s[start..self.i].iter().collect::<String>().parse().ok()
    }
}

// ── строки меню

#[derive(Debug, Clone, PartialEq)]
pub enum Kind {
    App(usize),
    // приложение, номер действия
    Action(usize, usize),
    Calc(String),
    Run(String),
    Web(String),
    System(usize),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Item {
    pub kind: Kind,
    pub group: &'static str,
    pub label: String,
    pub sub: String,
    pub glyph: u32,
}

pub struct SystemAction {
    pub label: &'static str,
    pub label_ru: &'static str,
    pub keys: &'static str,
    pub icon: u32,
    pub cmd: &'static str,
}

pub const SYSTEM: [SystemAction; 8] = [
    SystemAction { label: "Lock screen", label_ru: "Заблокировать экран", keys: "lock screen блок", icon: 0xF033E, cmd: "pgrep -x swaylock >/dev/null || swaylock -f -c 151515" },
    SystemAction { label: "Sleep", label_ru: "Сон", keys: "sleep suspend сон", icon: 0xF0904, cmd: "systemctl suspend" },
    SystemAction { label: "Power menu", label_ru: "Меню питания", keys: "power shutdown reboot restart logout turn off выключ перезагр питан", icon: 0xF0425, cmd: "amane ipc call power toggle" },
    SystemAction { label: "Wallpapers", label_ru: "Обои", keys: "wallpaper background обои", icon: 0xF0E09, cmd: "amane ipc call wallpaper toggle" },
    SystemAction { label: "Clipboard history", label_ru: "Буфер обмена", keys: "clipboard paste copy history буфер", icon: 0xF014C, cmd: "amane ipc call clipboard toggle" },
    SystemAction { label: "Switch to Quickshell", label_ru: "Перейти на Quickshell", keys: "quickshell shell amane switch шелл", icon: 0xF0A1E, cmd: "rexilone-shell use quickshell" },
    SystemAction { label: "Do not disturb", label_ru: "Не беспокоить", keys: "dnd do not disturb notifications quiet беспок", icon: 0xF009B, cmd: "amane ipc call notifications dnd" },
    SystemAction { label: "Dark / light theme", label_ru: "Тёмная / светлая тема", keys: "dark light theme mode тем", icon: 0xF0594, cmd: "amane ipc call theme toggle" },
];

pub struct Query<'a> {
    pub text: &'a str,
    pub apps: &'a [Entry],
    pub counts: &'a HashMap<String, i64>,
    pub actions_for: Option<usize>,
    pub ru: bool,
}

pub fn items(q: &Query) -> Vec<Item> {
    let raw = q.text.trim();
    let low = raw.to_lowercase();
    let tr = |en: &'static str, ru: &'static str| if q.ru { ru } else { en };
    let app_item = |i: usize, group: &'static str| {
        let e = &q.apps[i];
        Item { kind: Kind::App(i), group, label: e.name.clone(), sub: e.generic.clone(), glyph: 0 }
    };

    if let Some(a) = q.actions_for {
        let e = &q.apps[a];
        return e
            .actions
            .iter()
            .enumerate()
            .map(|(j, act)| Item { kind: Kind::Action(a, j), group: "Actions", label: act.name.clone(), sub: String::new(), glyph: 0 })
            .collect();
    }
    if let Some(cmd) = raw.strip_prefix('>') {
        let cmd = cmd.trim().to_string();
        let label = if cmd.is_empty() { tr("Type a command…", "Введите команду…").to_string() } else { cmd.clone() };
        return vec![Item { kind: Kind::Run(cmd), group: "Run", label, sub: tr("Runs in a terminal, stays open", "Выполнится в терминале").into(), glyph: 0xF018D }];
    }
    if let Some(w) = raw.strip_prefix('?') {
        let w = w.trim().to_string();
        let label = if w.is_empty() { tr("Type what to search…", "Что искать…").to_string() } else { format!("{} “{w}”", tr("Search", "Найти")) };
        return vec![Item { kind: Kind::Web(w), group: "Web", label, sub: "Google".into(), glyph: 0xF059F }];
    }
    let count = |i: usize| q.counts.get(&q.apps[i].id).copied().unwrap_or(0);

    if low.is_empty() {
        let mut freq: Vec<usize> = (0..q.apps.len()).filter(|i| count(*i) > 0).collect();
        freq.sort_by(|a, b| count(*b).cmp(&count(*a)));
        freq.truncate(6);
        let mut out: Vec<Item> = freq.iter().map(|i| app_item(*i, "Frequent")).collect();
        let mut rest: Vec<usize> = (0..q.apps.len()).filter(|i| !freq.contains(i)).collect();
        rest.sort_by_key(|i| q.apps[*i].name.to_lowercase());
        out.extend(rest.into_iter().map(|i| app_item(i, "All apps")));
        return out;
    }

    let mut out = Vec::new();
    if let Some(v) = calc(raw.strip_prefix('=').unwrap_or(raw)) {
        let sub = format!("{}   ·   {}", raw.trim_start_matches('='), tr("Enter copies the result", "Enter — скопировать"));
        out.push(Item { kind: Kind::Calc(v.clone()), group: "Calculator", label: v, sub, glyph: 0xF00EC });
    }
    let alt = translit(&low);
    let mut found: Vec<(usize, i32)> = (0..q.apps.len())
        .filter_map(|i| {
            let e = &q.apps[i];
            let s = score(e, &low).max(if alt != low { score(e, &alt) - 1 } else { -1 });
            (s >= 0).then(|| (i, s + count(i).min(50) as i32 * 4))
        })
        .collect();
    found.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| q.apps[a.0].name.to_lowercase().cmp(&q.apps[b.0].name.to_lowercase())));
    out.extend(found.into_iter().map(|(i, _)| app_item(i, "Apps")));

    let hit = |text: &str| {
        let t = text.to_lowercase();
        t.contains(&low) || t.contains(&alt)
    };
    for (i, a) in SYSTEM.iter().enumerate() {
        if hit(&format!("{} {} {}", a.label, a.label_ru, a.keys)) {
            out.push(Item { kind: Kind::System(i), group: "System", label: tr(a.label, a.label_ru).into(), sub: String::new(), glyph: a.icon });
        }
    }
    out.push(Item { kind: Kind::Web(raw.to_string()), group: "Web", label: format!("{} “{raw}”", tr("Search", "Найти")), sub: "Google".into(), glyph: 0xF059F });
    out
}

pub fn group_name(g: &str, ru: bool) -> &str {
    if !ru {
        return g;
    }
    match g {
        "Frequent" => "Часто",
        "All apps" => "Все приложения",
        "Apps" => "Приложения",
        "Calculator" => "Калькулятор",
        "System" => "Система",
        "Web" => "Интернет",
        "Run" => "Команда",
        "Actions" => "Действия",
        _ => g,
    }
}

// %XX для адреса поиска
pub fn url_encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(id: &str, name: &str, generic: &str) -> Entry {
        Entry { id: id.into(), name: name.into(), generic: generic.into(), ..Default::default() }
    }

    fn apps() -> Vec<Entry> {
        vec![
            app("firefox", "Firefox", "Web Browser"),
            app("foot", "Foot", "Terminal"),
            app("org.gnome.Nautilus", "Files", "File Manager"),
            app("org.telegram.desktop", "Telegram Desktop", "Messenger"),
        ]
    }

    #[test]
    fn scores_like_launcher_qml() {
        let a = apps();
        assert_eq!(score(&a[1], "foot"), 1000);
        assert_eq!(score(&a[0], "fire"), 800);
        assert_eq!(score(&a[3], "desk"), 600);
        assert_eq!(score(&a[0], "efo"), 400);
        assert_eq!(score(&a[2], "nautilus"), 200);
        assert_eq!(score(&a[0], "ffx"), 100);
        assert_eq!(score(&a[0], "zzz"), -1);
    }

    #[test]
    fn russian_layout_finds_english_names() {
        assert_eq!(translit("ашкуащч"), "firefox");
        assert_eq!(translit("abc"), "abc");
        let a = apps();
        let counts = HashMap::new();
        let list = items(&Query { text: "ашку", apps: &a, counts: &counts, actions_for: None, ru: false });
        assert_eq!(list[0].kind, Kind::App(0));
    }

    #[test]
    fn frequent_first_then_all() {
        let a = apps();
        let counts: HashMap<String, i64> = [("org.telegram.desktop".to_string(), 33), ("foot".to_string(), 5)].into();
        let list = items(&Query { text: "", apps: &a, counts: &counts, actions_for: None, ru: false });
        assert_eq!(list[0].kind, Kind::App(3));
        assert_eq!(list[0].group, "Frequent");
        assert_eq!(list[1].kind, Kind::App(1));
        assert_eq!(list[2].group, "All apps");
        assert_eq!(list[2].label, "Files");
        assert_eq!(list.len(), 4);
    }

    #[test]
    fn usage_boosts_search() {
        let a = vec![app("a", "Term One", ""), app("b", "Term Two", "")];
        let counts: HashMap<String, i64> = [("b".to_string(), 10)].into();
        let list = items(&Query { text: "term", apps: &a, counts: &counts, actions_for: None, ru: false });
        assert_eq!(list[0].kind, Kind::App(1));
        assert_eq!(list.last().unwrap().group, "Web");
    }

    #[test]
    fn prefixes_and_system() {
        let a = apps();
        let c = HashMap::new();
        let q = |t| items(&Query { text: t, apps: &a, counts: &c, actions_for: None, ru: false });
        assert_eq!(q("> htop")[0].kind, Kind::Run("htop".into()));
        assert_eq!(q("?rust")[0].kind, Kind::Web("rust".into()));
        assert!(q("sleep").iter().any(|i| i.kind == Kind::System(1)));
        assert!(q("выключ").iter().any(|i| i.kind == Kind::System(2)));
    }

    #[test]
    fn calculator() {
        assert_eq!(calc("2+2"), Some("4".into()));
        assert_eq!(calc("2 × 3 + 1"), Some("7".into()));
        assert_eq!(calc("(1+2)*3"), Some("9".into()));
        assert_eq!(calc("-(2+3)"), Some("-5".into()));
        assert_eq!(calc("2^10"), Some("1024".into()));
        assert_eq!(calc("2^3^2"), Some("512".into()));
        assert_eq!(calc("10/4"), Some("2.5".into()));
        assert_eq!(calc("0,1+0,2"), Some("0.3".into()));
        assert_eq!(calc("1/3"), Some("0.333333333333".into()));
        assert_eq!(calc("7%3"), Some("1".into()));
        assert_eq!(calc("12"), None);
        assert_eq!(calc("1/0"), None);
        assert_eq!(calc("2+"), None);
        assert_eq!(calc("firefox"), None);
        assert_eq!(calc("(1+2"), None);
        let a = apps();
        let c = HashMap::new();
        let list = items(&Query { text: "=6*7", apps: &a, counts: &c, actions_for: None, ru: true });
        assert_eq!(list[0].kind, Kind::Calc("42".into()));
        assert_eq!(group_name(list[0].group, true), "Калькулятор");
    }

    #[test]
    fn actions_list() {
        let mut a = apps();
        a[0].actions.push(crate::apps::Action { name: "New Window".into(), exec: "firefox --new-window".into(), icon: String::new() });
        let c = HashMap::new();
        let list = items(&Query { text: "", apps: &a, counts: &c, actions_for: Some(0), ru: false });
        assert_eq!(list, vec![Item { kind: Kind::Action(0, 0), group: "Actions", label: "New Window".into(), sub: String::new(), glyph: 0 }]);
    }

    #[test]
    fn number_format() {
        assert_eq!(fmt_num(0.1 + 0.2), "0.3");
        assert_eq!(fmt_num(1e20), "100000000000000000000");
        assert_eq!(fmt_num(-2.5), "-2.5");
        assert_eq!(fmt_num(0.0), "0");
    }

    #[test]
    fn encoding() {
        assert_eq!(url_encode("rust lang"), "rust%20lang");
        assert_eq!(url_encode("ё"), "%D1%91");
    }
}
