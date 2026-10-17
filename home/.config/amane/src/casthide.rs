// приложения, скрытые с демонстрации экрана (CastHide.qml + CastHideMenu.qml): Super+G → niri-cast-toggle.
// Список — ~/.config/niri/screencast-hidden.list, из него — правило niri в screencast-hidden.kdl

use std::time::Duration;

use amane::{Center, Column, Image, Padding, Rectangle, Row, Service, Widget, children};

use crate::look::Tk;
use crate::niri::Niri;
use crate::popups;
use crate::ui::{self, POPUP};

#[derive(Default)]
pub struct CastHide {
    pub apps: Vec<String>,
}

fn dir() -> std::path::PathBuf {
    crate::settings::home().join(".config/niri")
}

pub fn parse(text: &str) -> Vec<String> {
    text.lines().map(str::trim).filter(|s| !s.is_empty()).map(String::from).collect()
}

fn esc(a: &str) -> String {
    let mut s = String::new();
    for c in a.chars() {
        if ".*+?^${}()|[]\\-".contains(c) {
            s.push('\\');
        }
        s.push(c);
    }
    s
}

pub fn kdl(apps: &[String]) -> String {
    let mut s = String::from("// генерируется niri-cast-toggle (Super+G) и шеллом, вручную не редактировать\n");
    if !apps.is_empty() {
        s.push_str("window-rule {\n");
        for a in apps {
            s.push_str(&format!("    match app-id=r#\"^{}$\"#\n", esc(a)));
        }
        s.push_str("    block-out-from \"screencast\"\n}\n");
    }
    s
}

fn write_kdl(apps: &[String]) {
    if crate::look::no_services() {
        return;
    }
    let p = dir().join("screencast-hidden.kdl");
    let text = kdl(apps);
    if std::fs::read_to_string(&p).ok().as_deref() != Some(text.as_str()) {
        let _ = std::fs::write(p, text);
    }
}

fn save(next: Vec<String>) {
    let text = if next.is_empty() { String::new() } else { next.join("\n") + "\n" };
    let _ = std::fs::write(dir().join("screencast-hidden.list"), text);
    write_kdl(&next);
    CastHide::write().apps = next;
}

pub fn unhide(app: &str) {
    let next: Vec<String> = CastHide::read().apps.iter().filter(|a| *a != app).cloned().collect();
    save(next);
}

pub fn hide_app(app: &str) {
    let mut next = CastHide::read().apps.clone();
    if !app.is_empty() && !next.iter().any(|a| a == app) {
        next.push(app.to_string());
        save(next);
    }
}

fn focused_app() -> Option<(String, String)> {
    let n = Niri::read();
    n.s.focused().map(|w| (w.app_id.clone(), w.title.clone()))
}

pub fn ipc(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("unhide") => {
            if let Some(a) = args.get(1) {
                unhide(a);
            }
            "ok".into()
        }
        _ => CastHide::read().apps.join("\n"),
    }
}

// значок в баре; ярче — если скрыто активное окно
pub fn bar_icon(t: &Tk, output: &str) -> Option<amane::Rectangle> {
    let apps = CastHide::read().apps.clone();
    if apps.is_empty() {
        return None;
    }
    let focused_hidden = focused_app().is_some_and(|(a, _)| apps.contains(&a));
    let o = output.to_string();
    Some(crate::bar::bar_text_c(t, "cast", ui::glyph(0xF0209), t.icon, popups::Popups::read().open == "cast", true, if focused_hidden { t.p.warn } else { t.p.dim }).on_click(move |_| popups::toggle_at("cast", &o)))
}

pub fn menu(t: &Tk) -> Column {
    let w = 340.0;
    let apps = CastHide::read().apps.clone();
    let n = apps.len();
    let sub = if t.c.ru() {
        format!("{n} {} от зрителей", crate::i18n::plural(true, n as i64, "", "", "приложение скрыто", "приложения скрыты", "приложений скрыто"))
    } else if n == 1 {
        "1 app is blacked out for viewers".into()
    } else {
        format!("{n} apps are blacked out for viewers")
    };
    let mut col: Vec<Box<dyn Widget>> = vec![Box::new(ui::menu_header::<POPUP>(t, w, 0xF0209, "Hidden from screencast", &sub, ""))];
    let focus = focused_app();
    let mut rows: Vec<Box<dyn Widget>> = Vec::new();
    for a in &apps {
        let e = crate::apps::lookup(a);
        let name = e.as_ref().map(|e| e.name.clone()).filter(|x| !x.is_empty()).unwrap_or_else(|| a.clone());
        let is_focus = focus.as_ref().is_some_and(|(f, _)| f == a);
        let icon = Rectangle::new().width(26.0).height(26.0);
        let icon = match crate::apps::icon_for(a) {
            Some(p) => icon.fill(Image::contain(p)),
            None => icon,
        };
        let tw = w - 24.0 - 26.0 - 24.0 - 80.0;
        let a2 = a.clone();
        let btn = ui::button::<POPUP>(t, &format!("cast-show:{a}"), &format!("{}  {}", ui::glyph(0xF0208), t.t("Show")), false, move || unhide(&a2));
        rows.push(Box::new(Rectangle::new().width(w).height(52.0).radius(10.0).fill(t.p.surface).padding(Padding { top: 0.0, right: 10.0, bottom: 0.0, left: 12.0 }).child(
            Row::new(children![
                icon,
                Column::new(children![
                    crate::prefs::w::line(t, &name, t.fs, t.p.fg, tw, false),
                    crate::prefs::w::line(t, &t.t(if is_focus { "Active window" } else { a }), t.fs - 2.0, if is_focus { t.p.warn } else { t.p.dim }, tw, false)
                ])
                .gap(1.0)
                .width(tw),
                btn
            ])
            .gap(12.0)
            .height(52.0)
            .align(Center),
        )));
    }
    col.push(Box::new(Column::new(rows).gap(3.0)));
    // скрыть активное окно отсюда же (то же, что Super+G)
    if let Some((app, title)) = focus {
        if !apps.contains(&app) && !app.is_empty() && app != "amane" {
            let short: String = title.chars().take(28).collect();
            let label = format!("{} {}", t.t("Hide"), if short.is_empty() { t.t("active window") } else { format!("“{short}”") });
            col.push(Box::new(Rectangle::new().width(w).height(36.0).align_child(Center, Center).child(ui::button::<POPUP>(t, "cast-hide", &format!("{}  {label}", ui::glyph(0xF0209)), false, move || hide_app(&app)))));
        }
    }
    col.push(Box::new(crate::prefs::w::para(t, &t.t("Super+G hides or shows the active app. Viewers see a black box in its place."), t.fs - 2.0, t.p.dim, w)));
    Column::new(col).gap(10.0)
}

impl Service for CastHide {
    fn new() -> Self {
        CastHide { apps: parse(&std::fs::read_to_string(dir().join("screencast-hidden.list")).unwrap_or_default()) }
    }

    // список меняет и niri-cast-toggle (Super+G) — следим за файлом
    fn listen() {
        let p = dir().join("screencast-hidden.list");
        let mut first = true;
        loop {
            let next = parse(&std::fs::read_to_string(&p).unwrap_or_default());
            if first || CastHide::read().apps != next {
                write_kdl(&next);
                if CastHide::read().apps != next {
                    CastHide::write().apps = next;
                }
                first = false;
            }
            std::thread::sleep(Duration::from_secs(1));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rule() {
        assert_eq!(parse(" foot \n\norg.telegram.desktop\n"), vec!["foot", "org.telegram.desktop"]);
        let k = kdl(&["org.telegram.desktop".into()]);
        assert!(k.contains("match app-id=r#\"^org\\.telegram\\.desktop$\"#"));
        assert!(k.contains("block-out-from \"screencast\""));
        assert_eq!(kdl(&[]).lines().count(), 1);
    }
}
