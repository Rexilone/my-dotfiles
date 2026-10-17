// polkit-агент (PolkitDialog.qml): окно ввода пароля для pkexec и приложений, которым нужны права.
// Регистрация и проверка пароля — data/polkit.py (python-dbus + polkit-agent-helper-1)

use std::io::{BufRead, BufReader, Write};
use std::process::{ChildStdin, Command, Stdio};
use std::sync::Mutex;
use std::time::Duration;

use amane::{Center, Color, Column, Key, Keyboard, Layer, LayerWindow, Monitor, Padding, Parent, Rectangle, Row, Service, Start, TextInput, Widget, Zone, children};

use crate::json::Json;
use crate::look;
use crate::ui;

#[derive(Default, Clone)]
pub struct Polkit {
    pub active: bool,
    pub message: String,
    pub prompt: String,
    pub echo: bool,
    pub failed: bool,
    pub info: String,
    pub error: String,
    pub waiting: bool,
    pub output: String,
}

static STDIN: Mutex<Option<ChildStdin>> = Mutex::new(None);
static TEXT: Mutex<String> = Mutex::new(String::new());

fn send(o: Json) {
    let line = o.pretty_with(0).replace('\n', "") + "\n";
    if let Some(s) = STDIN.lock().unwrap().as_mut() {
        let _ = s.write_all(line.as_bytes());
        let _ = s.flush();
    }
}

fn submit() {
    let text = std::mem::take(&mut *TEXT.lock().unwrap());
    TextInput::set_text("polkit-pass", "");
    {
        let mut p = Polkit::write();
        if !p.active || p.waiting {
            return;
        }
        p.waiting = true;
        p.failed = false;
    }
    send(Json::Obj(vec![("cmd".into(), Json::Str("respond".into())), ("text".into(), Json::Str(text))]));
}

fn cancel() {
    send(Json::Obj(vec![("cmd".into(), Json::Str("cancel".into()))]));
    Polkit::write().active = false;
}

fn handle(j: &Json) {
    let mut p = Polkit::write();
    if let Json::Obj(_) = j.get("begin") {
        let b = j.get("begin");
        *p = Polkit { active: true, message: b.get("message").str_or(""), output: crate::niri::Niri::read().s.focused_output().to_string(), ..Default::default() };
        TEXT.lock().unwrap().clear();
    } else if let Some(pr) = j.get("prompt").str() {
        p.prompt = pr.to_string();
        p.echo = j.get("echo").bool_or(false);
        p.waiting = false;
    } else if let Some(i) = j.get("info").str() {
        p.info = i.to_string();
    } else if let Some(e) = j.get("error").str() {
        p.error = e.to_string();
    } else if j.get("failed").bool_or(false) {
        p.failed = true;
        p.waiting = false;
    } else if j.get("done").bool_or(false) {
        p.active = false;
    }
}

impl Service for Polkit {
    fn new() -> Self {
        Polkit::default()
    }

    fn listen() {
        let script = crate::settings::home().join(".config/amane/data/polkit.py");
        loop {
            let Ok(mut child) = Command::new("python3").arg("-u").arg(&script).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn() else {
                std::thread::sleep(Duration::from_secs(30));
                continue;
            };
            *STDIN.lock().unwrap() = child.stdin.take();
            let out = child.stdout.take().unwrap();
            for line in BufReader::new(out).lines() {
                let Ok(line) = line else { break };
                if let Some(j) = Json::parse(&line) {
                    handle(&j);
                }
            }
            let _ = child.wait();
            *STDIN.lock().unwrap() = None;
            Polkit::write().active = false;
            // уже есть другой агент (Quickshell) или polkitd перезапустился — попробовать позже
            std::thread::sleep(Duration::from_secs(20));
        }
    }
}

pub fn view(m: &Monitor) -> LayerWindow {
    let tk = look::tk();
    let t = &tk;
    let p = Polkit::read().clone();
    let here = p.active && (p.output == m.name || p.output.is_empty());
    if !here {
        return LayerWindow::new().width(1.0).height(1.0).layer(Layer::Overlay).namespace("rexilone-polkit").visible(false).child(Rectangle::new().width(1.0).height(1.0));
    }
    let w = 420.0;
    let iw = w - 40.0;
    let prompt = p.prompt.trim_end().trim_end_matches(':').to_string();
    let input = TextInput::new("polkit-pass").width(iw - 24.0).size(t.fs + 1.0).color(t.p.fg).placeholder(if prompt.is_empty() { t.t("Password") } else { t.t(&prompt) }).focused().on_change(|s| *TEXT.lock().unwrap() = s).on_submit(|_| submit());
    let input = if p.echo { input } else { input.password() };
    let mut col: Vec<Box<dyn Widget>> = vec![
        Box::new(Row::new(children![ui::icon(t, ui::ic::LOCK, 20.0, t.p.fg), ui::bold(t, t.t("Authentication required"), t.p.fg).size(t.fs + 1.0)]).gap(12.0).align(Center)),
        Box::new(crate::prefs::w::para(t, &p.message, t.fs, t.p.dim, iw)),
        Box::new(Rectangle::new().width(iw).height(4.0)),
        Box::new(Rectangle::new().width(iw).height(36.0).radius(8.0).fill(t.p.surface_hi).border(1.0, if p.failed { t.p.urgent } else { t.p.line }).padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 12.0 }).align_child(Start, Center).child(input)),
    ];
    let note = if p.failed { t.t("Wrong password, try again") } else if !p.error.is_empty() { p.error.clone() } else { p.info.clone() };
    if !note.is_empty() {
        col.push(Box::new(crate::prefs::w::para(t, &note, t.fs - 1.0, if p.failed || !p.error.is_empty() { t.p.urgent } else { t.p.dim }, iw)));
    }
    col.push(Box::new(Rectangle::new().width(iw).height(18.0).align_child(amane::End, Center).child(ui::text(t, t.t("Enter — confirm · Esc — cancel"), t.p.faint).size(t.fs - 2.0))));
    let c = Column::new(col).gap(12.0);
    let (_, ch) = ui::size_of(&c);
    let card = Rectangle::new().width(w).height(ch + 40.0).radius(t.radius + 2.0).fill(t.panel).border(1.0, t.p.faint).padding(20.0).on_click(|_| {}).child(c);
    LayerWindow::new()
        .width(amane::Full)
        .height(amane::Full)
        .layer(Layer::Overlay)
        .space(Zone::Ignore)
        .namespace("rexilone-polkit")
        .keyboard(Keyboard::Exclusive)
        .on_key(|k| {
            if k == Key::Escape {
                cancel()
            }
        })
        .child(Rectangle::new().width(Parent).height(Parent).fill(Color::rgba(0, 0, 0, 128)).align_child(Center, Center).child(card))
}
