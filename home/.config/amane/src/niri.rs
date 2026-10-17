// niri: воркспейсы, окна, раскладка, мониторы — из `niri msg -j event-stream` (как services/Niri.qml)

use std::thread;
use std::time::Duration;

use amane::Service;

use crate::json::Json;

#[derive(Debug, Clone, PartialEq)]
pub struct Ws {
    pub id: i64,
    pub idx: u32,
    pub name: Option<String>,
    pub output: String,
    pub urgent: bool,
    pub active: bool,
    pub focused: bool,
    pub active_window: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Win {
    pub id: i64,
    pub title: String,
    pub app_id: String,
    pub workspace: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct State {
    pub workspaces: Vec<Ws>,
    pub windows: Vec<Win>,
    pub focused_window: Option<i64>,
    pub layouts: Vec<String>,
    pub layout_idx: usize,
    // имя, ширина, высота (логические) — для выбора главного монитора
    pub outputs: Vec<(String, u32, u32)>,
}

fn id(j: &Json) -> Option<i64> {
    j.num().map(|n| n as i64)
}

fn ws(j: &Json) -> Ws {
    Ws {
        id: id(j.get("id")).unwrap_or(-1),
        idx: j.get("idx").num_or(0.0) as u32,
        name: j.get("name").str().map(String::from),
        output: j.get("output").str_or(""),
        urgent: j.get("is_urgent").bool_or(false),
        active: j.get("is_active").bool_or(false),
        focused: j.get("is_focused").bool_or(false),
        active_window: id(j.get("active_window_id")),
    }
}

fn win(j: &Json) -> Win {
    Win {
        id: id(j.get("id")).unwrap_or(-1),
        title: j.get("title").str_or(""),
        app_id: j.get("app_id").str_or(""),
        workspace: id(j.get("workspace_id")),
    }
}

impl State {
    // одно событие niri; true — если что-то поменялось
    pub fn handle(&mut self, ev: &Json) -> bool {
        let before = self.clone();
        let e = ev.get("WorkspacesChanged");
        if !e.is_null() {
            self.workspaces = e.get("workspaces").arr().iter().map(ws).collect();
            self.workspaces.sort_by(|a, b| a.output.cmp(&b.output).then(a.idx.cmp(&b.idx)));
        }
        let e = ev.get("WorkspaceActivated");
        if !e.is_null() {
            let target = id(e.get("id"));
            let focused = e.get("focused").bool_or(false);
            if let Some(out) = self.workspaces.iter().find(|w| Some(w.id) == target).map(|w| w.output.clone()) {
                for w in &mut self.workspaces {
                    if w.output == out {
                        w.active = Some(w.id) == target;
                    }
                    if focused {
                        w.focused = Some(w.id) == target;
                    }
                }
            }
        }
        let e = ev.get("WorkspaceUrgencyChanged");
        if !e.is_null() {
            for w in &mut self.workspaces {
                if Some(w.id) == id(e.get("id")) {
                    w.urgent = e.get("urgent").bool_or(false);
                }
            }
        }
        let e = ev.get("WorkspaceActiveWindowChanged");
        if !e.is_null() {
            for w in &mut self.workspaces {
                if Some(w.id) == id(e.get("workspace_id")) {
                    w.active_window = id(e.get("active_window_id"));
                }
            }
        }
        let e = ev.get("WindowsChanged");
        if !e.is_null() {
            let list = e.get("windows").arr();
            self.windows = list.iter().map(win).collect();
            self.focused_window = list.iter().find(|w| w.get("is_focused").bool_or(false)).and_then(|w| id(w.get("id")));
        }
        let e = ev.get("WindowOpenedOrChanged");
        if !e.is_null() {
            let w = e.get("window");
            let new = win(w);
            if w.get("is_focused").bool_or(false) {
                self.focused_window = Some(new.id);
            }
            match self.windows.iter_mut().find(|x| x.id == new.id) {
                Some(x) => *x = new,
                None => self.windows.push(new),
            }
        }
        let e = ev.get("WindowClosed");
        if !e.is_null() {
            let gone = id(e.get("id"));
            self.windows.retain(|w| Some(w.id) != gone);
            if self.focused_window == gone {
                self.focused_window = None;
            }
        }
        let e = ev.get("WindowFocusChanged");
        if !e.is_null() {
            self.focused_window = id(e.get("id"));
        }
        let e = ev.get("KeyboardLayoutsChanged");
        if !e.is_null() {
            let k = e.get("keyboard_layouts");
            self.layouts = k.get("names").arr().iter().filter_map(|n| n.str().map(String::from)).collect();
            self.layout_idx = k.get("current_idx").num_or(0.0) as usize;
        }
        let e = ev.get("KeyboardLayoutSwitched");
        if !e.is_null() {
            self.layout_idx = e.get("idx").num_or(0.0) as usize;
        }
        *self != before
    }

    pub fn on_output(&self, output: &str) -> Vec<&Ws> {
        self.workspaces.iter().filter(|w| w.output == output).collect()
    }

    pub fn focused_output(&self) -> &str {
        self.workspaces.iter().find(|w| w.focused).map(|w| w.output.as_str()).unwrap_or("")
    }

    pub fn focused(&self) -> Option<&Win> {
        self.windows.iter().find(|w| Some(w.id) == self.focused_window)
    }

    pub fn layout_name(&self) -> &str {
        self.layouts.get(self.layout_idx).map(String::as_str).unwrap_or("")
    }
}

// «English (US)» → «en», как KeyboardLayout.qml
pub fn layout_code(name: &str) -> String {
    let lower = name.to_lowercase();
    let first = lower.split([' ', '(']).next().unwrap_or("");
    let code = match first {
        "english" => "en",
        "russian" => "ru",
        "ukrainian" => "ua",
        "belarusian" => "by",
        "kazakh" => "kz",
        "german" => "de",
        "french" => "fr",
        "spanish" => "es",
        "italian" => "it",
        "polish" => "pl",
        "czech" => "cz",
        "turkish" => "tr",
        "japanese" => "jp",
        "korean" => "kr",
        "chinese" => "cn",
        "georgian" => "ge",
        "armenian" => "am",
        "arabic" => "ar",
        _ => return lower.chars().take(2).collect(),
    };
    code.to_string()
}

pub fn parse_outputs(text: &str) -> Vec<(String, u32, u32)> {
    let Some(j) = Json::parse(text) else { return Vec::new() };
    let mut list: Vec<(String, u32, u32)> = j
        .obj()
        .iter()
        .filter_map(|(name, o)| {
            let l = o.get("logical");
            if l.is_null() {
                return None; // выключенный монитор
            }
            Some((name.clone(), l.get("width").num_or(0.0) as u32, l.get("height").num_or(0.0) as u32))
        })
        .collect();
    list.sort();
    list
}

// кавычки для sh: имя монитора и аргументы niri идут через оболочку
pub fn sh_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', r"'\''"))
}

pub fn action(args: &str) {
    amane::spawn(&format!("niri msg action {args}"));
}

pub fn focus_workspace(output: &str, idx: u32) {
    amane::spawn(&format!(
        "niri msg action focus-monitor {} && niri msg action focus-workspace {idx}",
        sh_quote(output)
    ));
}

pub struct Niri {
    pub s: State,
}

impl Service for Niri {
    fn new() -> Self {
        Niri { s: State::default() }
    }

    fn listen() {
        loop {
            let outputs = parse_outputs(&amane::output("niri msg -j outputs 2>/dev/null"));
            if Niri::read().s.outputs != outputs {
                Niri::write().s.outputs = outputs;
            }
            for line in amane::lines("niri msg -j event-stream 2>/dev/null") {
                let Some(ev) = Json::parse(&line) else { continue };
                let mut next = Niri::read().s.clone();
                let mut changed = next.handle(&ev);
                // монитор подключили или отключили — воркспейсы меняются вместе с ним
                if !ev.get("WorkspacesChanged").is_null() {
                    let outputs = parse_outputs(&amane::output("niri msg -j outputs 2>/dev/null"));
                    changed |= outputs != next.outputs;
                    next.outputs = outputs;
                }
                if changed {
                    Niri::write().s = next;
                }
            }
            // niri перезапустился или ещё не готов
            thread::sleep(Duration::from_secs(1));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ev(s: &str) -> Json {
        Json::parse(s).unwrap()
    }

    fn sample() -> State {
        let mut s = State::default();
        s.handle(&ev(r#"{"WorkspacesChanged":{"workspaces":[
            {"id":4,"idx":2,"name":null,"output":"DP-1","is_urgent":false,"is_active":true,"is_focused":true,"active_window_id":13},
            {"id":2,"idx":1,"name":"web","output":"DP-1","is_urgent":false,"is_active":false,"is_focused":false,"active_window_id":null},
            {"id":1,"idx":1,"name":null,"output":"HDMI-A-2","is_urgent":false,"is_active":true,"is_focused":false,"active_window_id":null}]}}"#));
        s
    }

    #[test]
    fn workspaces_sorted_per_output() {
        let s = sample();
        let dp: Vec<u32> = s.on_output("DP-1").iter().map(|w| w.idx).collect();
        assert_eq!(dp, vec![1, 2]);
        assert_eq!(s.on_output("DP-1")[0].name.as_deref(), Some("web"));
        assert_eq!(s.focused_output(), "DP-1");
    }

    #[test]
    fn activation_moves_focus_only_on_that_output() {
        let mut s = sample();
        assert!(s.handle(&ev(r#"{"WorkspaceActivated":{"id":2,"focused":true}}"#)));
        let dp = s.on_output("DP-1");
        assert!(dp[0].active && dp[0].focused);
        assert!(!dp[1].active && !dp[1].focused);
        // на другом мониторе активный не сбрасывается
        assert!(s.on_output("HDMI-A-2")[0].active);
        // неизвестный id — ничего не меняется
        assert!(!s.handle(&ev(r#"{"WorkspaceActivated":{"id":99,"focused":true}}"#)));
    }

    #[test]
    fn urgency_and_active_window() {
        let mut s = sample();
        s.handle(&ev(r#"{"WorkspaceUrgencyChanged":{"id":2,"urgent":true}}"#));
        s.handle(&ev(r#"{"WorkspaceActiveWindowChanged":{"workspace_id":2,"active_window_id":7}}"#));
        let w = &s.on_output("DP-1")[0];
        assert!(w.urgent);
        assert_eq!(w.active_window, Some(7));
    }

    #[test]
    fn windows_focus_open_close() {
        let mut s = State::default();
        s.handle(&ev(r#"{"WindowsChanged":{"windows":[{"id":1,"title":"a","app_id":"foot","workspace_id":2,"is_focused":false},
            {"id":2,"title":"b","app_id":"chromium","workspace_id":2,"is_focused":true}]}}"#));
        assert_eq!(s.focused().map(|w| w.app_id.as_str()), Some("chromium"));
        s.handle(&ev(r#"{"WindowOpenedOrChanged":{"window":{"id":3,"title":"c","app_id":"nvim","workspace_id":2,"is_focused":true}}}"#));
        assert_eq!(s.focused().map(|w| w.id), Some(3));
        s.handle(&ev(r#"{"WindowOpenedOrChanged":{"window":{"id":1,"title":"renamed","app_id":"foot","workspace_id":2,"is_focused":false}}}"#));
        assert_eq!(s.windows.iter().find(|w| w.id == 1).unwrap().title, "renamed");
        s.handle(&ev(r#"{"WindowClosed":{"id":3}}"#));
        assert_eq!(s.focused(), None);
        assert_eq!(s.windows.len(), 2);
        s.handle(&ev(r#"{"WindowFocusChanged":{"id":1}}"#));
        assert_eq!(s.focused().map(|w| w.title.as_str()), Some("renamed"));
    }

    #[test]
    fn keyboard_layouts() {
        let mut s = State::default();
        s.handle(&ev(r#"{"KeyboardLayoutsChanged":{"keyboard_layouts":{"names":["English (US)","Russian"],"current_idx":0}}}"#));
        assert_eq!(layout_code(s.layout_name()), "en");
        s.handle(&ev(r#"{"KeyboardLayoutSwitched":{"idx":1}}"#));
        assert_eq!(layout_code(s.layout_name()), "ru");
        assert_eq!(layout_code("Esperanto"), "es");
        assert_eq!(layout_code(""), "");
    }

    #[test]
    fn unknown_event_changes_nothing() {
        let mut s = sample();
        assert!(!s.handle(&ev(r#"{"OverviewOpenedOrClosed":{"is_open":true}}"#)));
    }

    #[test]
    fn outputs_skip_disabled() {
        let o = parse_outputs(r#"{"DP-1":{"logical":{"x":0,"y":0,"width":1920,"height":1080,"scale":1.0}},
            "HDMI-A-1":{"logical":null},"HDMI-A-2":{"logical":{"width":900,"height":1440}}}"#);
        assert_eq!(o, vec![("DP-1".into(), 1920, 1080), ("HDMI-A-2".into(), 900, 1440)]);
        assert!(parse_outputs("не json").is_empty());
    }

    #[test]
    fn quoting() {
        assert_eq!(sh_quote("DP-1"), "'DP-1'");
        assert_eq!(sh_quote("a'b"), r"'a'\''b'");
    }
}
