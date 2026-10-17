// настройки — общие с Quickshell: тот же settings.json, что меняют Настройки (Super+I)

use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use amane::Service;

use crate::json::Json;
use crate::md5;

#[derive(Debug, Clone, PartialEq)]
pub struct Config {
    pub scheme: String,
    pub font: String,
    pub ui_scale: f32,
    pub bar_height: f32,
    pub bar_style: String,
    pub transparency: bool,
    pub opacity: f32,
    pub clock_format: String,
    pub workspace_style: String,
    pub bar_modules: Vec<(String, bool)>,
    pub bar_screens: Vec<String>,
    pub primary_output: String,
    pub language: String,
    pub popup_timeout: u64,
    pub tray_mode: String,
}

impl Default for Config {
    fn default() -> Self {
        Config::from_json(&Json::Null)
    }
}

impl Config {
    pub fn from_json(j: &Json) -> Config {
        let strings = |v: &Json| v.arr().iter().filter_map(|s| s.str().map(String::from)).collect();
        Config {
            scheme: j.get("scheme").str_or("dark"),
            font: Some(j.get("font").str_or("")).filter(|f| !f.is_empty()).unwrap_or_else(|| "JetBrainsMono Nerd Font".into()),
            ui_scale: j.get("uiScale").num_or(1.0).clamp(0.5, 3.0) as f32,
            bar_height: j.get("barHeight").num_or(32.0).clamp(20.0, 80.0) as f32,
            bar_style: j.get("barStyle").str_or("flat"),
            transparency: j.get("transparency").bool_or(false),
            opacity: j.get("opacity").num_or(0.85).clamp(0.0, 1.0) as f32,
            clock_format: j.get("clockFormat").str_or("dddd HH:mm"),
            workspace_style: j.get("workspaceStyle").str_or("dots"),
            bar_modules: j
                .get("barModules")
                .obj()
                .iter()
                .filter_map(|(k, v)| v.bool().map(|b| (k.clone(), b)))
                .collect(),
            bar_screens: strings(j.get("barScreens")),
            primary_output: j.get("primaryOutput").str_or(""),
            language: j.get("language").str_or("en"),
            popup_timeout: j.get("popupTimeout").num_or(5.0).clamp(1.0, 600.0) as u64,
            tray_mode: j.get("trayMode").str_or("inline"),
        }
    }

    // Settings.module(): включён, если не выключен явно
    pub fn module(&self, name: &str) -> bool {
        self.module_on(name, true)
    }

    // Settings.moduleOn(): со своим значением по умолчанию
    pub fn module_on(&self, name: &str, def: bool) -> bool {
        self.bar_modules.iter().find(|(k, _)| k == name).map(|(_, v)| *v).unwrap_or(def)
    }

    pub fn ru(&self) -> bool {
        self.language == "ru"
    }

    pub fn tr<'a>(&self, en: &'a str, ru: &'a str) -> &'a str {
        if self.ru() { ru } else { en }
    }

    // главный монитор: заданный, иначе самый крупный (как Settings.primary)
    pub fn primary(&self, outputs: &[(String, u32, u32)]) -> String {
        if outputs.iter().any(|(n, _, _)| *n == self.primary_output) {
            return self.primary_output.clone();
        }
        outputs
            .iter()
            .max_by_key(|(_, w, h)| w * h)
            .map(|(n, _, _)| n.clone())
            .unwrap_or_default()
    }

    // мониторы с баром: выбранные, иначе только главный (Settings.barOn)
    pub fn bar_on(&self, outputs: &[(String, u32, u32)]) -> Vec<String> {
        let list: Vec<String> = self
            .bar_screens
            .iter()
            .filter(|n| outputs.iter().any(|(o, _, _)| o == *n))
            .cloned()
            .collect();
        if list.is_empty() { vec![self.primary(outputs)] } else { list }
    }
}

pub fn home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
}

fn state_home() -> PathBuf {
    std::env::var_os("XDG_STATE_HOME").map(PathBuf::from).unwrap_or_else(|| home().join(".local/state"))
}

// ~/.local/state/quickshell/by-shell/<md5 пути к shell.qml>/settings.json
pub fn path() -> PathBuf {
    if let Some(p) = std::env::var_os("REXILONE_SETTINGS") {
        return PathBuf::from(p);
    }
    let conf = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home().join(".config"));
    let shell = conf.join("quickshell/shell.qml");
    let id = md5::hex(shell.to_string_lossy().as_bytes());
    state_home().join("quickshell/by-shell").join(id).join("settings.json")
}

pub fn load() -> Json {
    fs::read_to_string(path()).ok().and_then(|t| Json::parse(&t)).unwrap_or(Json::Obj(Vec::new()))
}

// записать один ключ, не трогая остальные; через временный файл — Quickshell не прочтёт половину
pub fn save_key(key: &str, value: Json) {
    let p = path();
    let mut j = load();
    j.set(key, value);
    if let Some(dir) = p.parent() {
        let _ = fs::create_dir_all(dir);
    }
    let tmp = p.with_extension("json.amane");
    if fs::write(&tmp, j.pretty()).is_ok() {
        let _ = fs::rename(&tmp, &p);
    }
}

// записать вложенный ключ: set_path(&["barModules", "tray"], Json::Bool(false))
pub fn save_path(path: &[&str], value: Json) {
    let Some((first, rest)) = path.split_first() else { return };
    if rest.is_empty() {
        save_key(first, value);
        return;
    }
    let mut top = load().get(first).clone();
    let mut cur = &mut top;
    for (i, k) in rest.iter().enumerate() {
        if i + 1 == rest.len() {
            cur.set(k, value.clone());
            break;
        }
        if cur.get(k).is_null() || !matches!(cur.get(k), Json::Obj(_)) {
            cur.set(k, Json::Obj(Vec::new()));
        }
        cur = cur.get_mut(k).unwrap();
    }
    save_key(first, top);
}

pub struct Settings {
    pub c: Config,
    // весь файл — для страниц Настроек
    pub raw: Json,
}

impl Service for Settings {
    fn new() -> Self {
        let raw = load();
        Settings { c: Config::from_json(&raw), raw }
    }

    fn interval() -> Duration {
        Duration::from_secs(3600)
    }

    fn listen() {
        let p = path();
        if let Some(dir) = p.parent() {
            let _ = fs::create_dir_all(dir);
        }
        for _ in amane::watch_file(&p.to_string_lossy()) {
            let raw = load();
            if Settings::read().raw != raw {
                let c = Config::from_json(&raw);
                let mut w = Settings::write();
                w.c = c;
                w.raw = raw;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn outs() -> Vec<(String, u32, u32)> {
        vec![("HDMI-A-2".into(), 1440, 900), ("DP-1".into(), 1920, 1080)]
    }

    #[test]
    fn defaults_like_quickshell() {
        let c = Config::default();
        assert_eq!(c.scheme, "dark");
        assert_eq!(c.font, "JetBrainsMono Nerd Font");
        assert_eq!(c.bar_height, 32.0);
        assert_eq!(c.bar_style, "flat");
        assert_eq!(c.clock_format, "dddd HH:mm");
        assert_eq!(c.popup_timeout, 5);
        assert!(c.module("tray"));
        assert!(!c.module_on("media", false));
    }

    #[test]
    fn reads_values_and_clamps() {
        let j = Json::parse(r#"{"barStyle":"pills","barHeight":500,"uiScale":1.25,"font":"",
            "barModules":{"tray":false,"media":true},"language":"ru","barScreens":["DP-1","nope"]}"#)
        .unwrap();
        let c = Config::from_json(&j);
        assert_eq!(c.bar_style, "pills");
        assert_eq!(c.bar_height, 80.0);
        assert_eq!(c.ui_scale, 1.25);
        assert_eq!(c.font, "JetBrainsMono Nerd Font");
        assert!(!c.module("tray"));
        assert!(c.module_on("media", false));
        assert!(c.ru());
        assert_eq!(c.tr("Sleep", "Сон"), "Сон");
        assert_eq!(c.bar_on(&outs()), vec!["DP-1".to_string()]);
    }

    #[test]
    fn primary_falls_back_to_biggest() {
        let mut c = Config::default();
        assert_eq!(c.primary(&outs()), "DP-1");
        c.primary_output = "HDMI-A-2".into();
        assert_eq!(c.primary(&outs()), "HDMI-A-2");
        c.primary_output = "winit".into();
        assert_eq!(c.primary(&outs()), "DP-1");
        assert_eq!(c.bar_on(&outs()), vec!["DP-1".to_string()]);
        assert_eq!(c.primary(&[]), "");
    }

    #[test]
    fn save_key_keeps_other_keys() {
        let dir = std::env::temp_dir().join(format!("amane-settings-{}", std::process::id()));
        let file = dir.join("settings.json");
        fs::create_dir_all(&dir).unwrap();
        fs::write(&file, "{\n    \"scheme\": \"nord\",\n    \"barHeight\": 30\n}\n").unwrap();
        // SAFETY: тест один меняет эту переменную
        unsafe { std::env::set_var("REXILONE_SETTINGS", &file) };
        save_key("barHeight", Json::Num(36.0));
        let c = Config::from_json(&load());
        unsafe { std::env::remove_var("REXILONE_SETTINGS") };
        assert_eq!(c.scheme, "nord");
        assert_eq!(c.bar_height, 36.0);
        let _ = fs::remove_dir_all(&dir);
    }
}
