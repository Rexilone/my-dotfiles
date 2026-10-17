// путь к значку по имени (иконки уведомлений, окон); найденное запоминается

use std::cell::RefCell;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

use amane::{Apps, Service};

thread_local! {
    static CACHE: RefCell<HashMap<String, Option<PathBuf>>> = RefCell::new(HashMap::new());
}

const THEMES: [&str; 4] = ["Adwaita", "hicolor", "Papirus", "breeze"];
const SIZES: [&str; 8] = ["scalable", "256x256", "128x128", "96x96", "64x64", "48x48", "32x32", "symbolic"];
const KINDS: [&str; 4] = ["apps", "devices", "status", "places"];

// кандидаты по порядку: так проверка не зависит от того, какие темы стоят
pub fn candidates(name: &str, roots: &[PathBuf]) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for root in roots {
        for theme in THEMES {
            for size in SIZES {
                for kind in KINDS {
                    let dir = root.join(theme).join(size).join(kind);
                    out.push(dir.join(format!("{name}.svg")));
                    out.push(dir.join(format!("{name}.png")));
                }
            }
        }
    }
    out.push(PathBuf::from(format!("/usr/share/pixmaps/{name}.png")));
    out.push(PathBuf::from(format!("/usr/share/pixmaps/{name}.svg")));
    out
}

fn roots() -> Vec<PathBuf> {
    let mut r = vec![crate::settings::home().join(".local/share/icons")];
    r.push(PathBuf::from("/usr/share/icons"));
    r
}

// «firefox», «/путь/к/файлу.png» или «file:///…» → файл картинки
pub fn resolve(name: &str) -> Option<PathBuf> {
    if name.is_empty() {
        return None;
    }
    if let Some(p) = name.strip_prefix("file://") {
        return Some(PathBuf::from(p)).filter(|p| p.exists());
    }
    if name.starts_with('/') {
        return Some(PathBuf::from(name)).filter(|p| p.exists());
    }
    if let Some(hit) = CACHE.with_borrow(|c| c.get(name).cloned()) {
        return hit;
    }
    // у программ из меню значок уже найден amane
    let from_apps = Apps::read()
        .list()
        .iter()
        .find(|a| a.icon() == Some(name) || a.name().eq_ignore_ascii_case(name))
        .and_then(|a| a.icon_path().map(Path::to_path_buf));
    let found = from_apps.or_else(|| candidates(name, &roots()).into_iter().find(|p| p.exists()));
    CACHE.with_borrow_mut(|c| c.insert(name.to_string(), found.clone()));
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn candidate_order_prefers_scalable_apps() {
        let c = candidates("foot", &[PathBuf::from("/r")]);
        assert_eq!(c[0], PathBuf::from("/r/Adwaita/scalable/apps/foot.svg"));
        assert!(c.contains(&PathBuf::from("/r/hicolor/48x48/apps/foot.png")));
        assert_eq!(c.last().unwrap(), &PathBuf::from("/usr/share/pixmaps/foot.svg"));
    }

    #[test]
    fn paths_and_urls() {
        assert_eq!(resolve(""), None);
        assert_eq!(resolve("/definitely/not/here.png"), None);
        assert_eq!(resolve("file:///definitely/not/here.png"), None);
        let tmp = std::env::temp_dir().join(format!("amane-icon-{}.png", std::process::id()));
        std::fs::write(&tmp, b"x").unwrap();
        assert_eq!(resolve(tmp.to_str().unwrap()), Some(tmp.clone()));
        assert_eq!(resolve(&format!("file://{}", tmp.display())), Some(tmp.clone()));
        let _ = std::fs::remove_file(tmp);
    }
}
