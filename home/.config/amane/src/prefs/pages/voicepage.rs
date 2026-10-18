// Голосовой ввод (Voxtype): установка, модель распознавания, служба и автозапуск, язык, вывод текста

use amane::{Center, Column, Padding, Rectangle, Row, Service, children};

use super::super::w::{self, Btn, Card, Slide, W, bx};
use super::Out;
use crate::look::Tk;
use crate::theme::alpha;
use crate::ui;
use crate::voice::{self, Voice};

// размер моделей Whisper (для подписи)
fn model_size(m: &str) -> &'static str {
    match m.trim_end_matches(".en") {
        "tiny" => "75 MB",
        "base" => "142 MB",
        "small" => "466 MB",
        "medium" => "1.5 GB",
        "large-v3" => "2.9 GB",
        "large-v3-turbo" => "1.6 GB",
        _ => "",
    }
}

pub fn page(t: &Tk, w: f32) -> Out {
    let v = Voice::read().clone();
    let ru = t.c.ru();
    let mut items: Vec<W> = Vec::new();
    let installing = !crate::store::Store::read().busy_with("voxtype-bin").is_empty();
    let job_line = crate::store::Store::read().current().filter(|j| j.pkgs.iter().any(|p| p == "voxtype-bin")).map(|j| j.line.clone()).unwrap_or_default();

    // ── главная карточка: состояние
    let (icon, title, sub, tint) = if !v.installed {
        (0xF036D, t.t("Voice typing is not installed"), t.t("Voxtype turns speech into text and types it into the active window. Works offline — the model runs on your computer"), t.p.dim)
    } else if !v.running {
        (0xF036D, t.t("Voice typing is off"), t.t("Turn it on to dictate with Super+H. The model is loaded into memory only while it's on"), t.p.dim)
    } else {
        let st = match v.state.as_str() {
            "recording" => t.t("Listening…"),
            "transcribing" => t.t("Recognizing…"),
            _ => t.t("Ready — press Super+H and speak, press again to type the text"),
        };
        (0xF036C, t.t("Voice typing is on"), st, if v.state == "recording" { t.p.rec } else { t.p.accent })
    };
    let mut btns: Vec<W> = Vec::new();
    if !v.installed {
        btns.push(bx(Btn::new(if installing { "Installing…" } else { "Install" }).icon(0xF01DA).primary().enabled(!installing).build(t, "vx-install", voice::install)));
    } else {
        let busy = !v.busy.is_empty() || !v.downloading.is_empty();
        let label = if !v.busy.is_empty() {
            if v.busy == "starting" { "Starting…" } else { "Stopping…" }
        } else if v.running {
            "Turn off"
        } else {
            "Turn on"
        };
        let on = v.running;
        btns.push(bx(Btn::new(label).primary_if(!on).enabled(!busy).build(t, "vx-run", move || voice::set_running(!on))));
        if v.running {
            btns.push(bx(Btn::new(if v.state == "recording" { "Stop" } else { "Try" }).icon(0xF036C).build(t, "vx-try", || amane::spawn("voxtype record toggle"))));
        }
    }
    let br = Row::new(btns).gap(8.0).align(Center);
    let (bw, _) = w::wh(&br);
    let tw = w - 40.0 - 56.0 - 18.0 * 2.0 - bw;
    let mut lines: Vec<W> = vec![bx(w::line(t, &title, t.fs + 4.0, t.p.fg, tw, true)), bx(w::para(t, &sub, t.fs - 1.0, t.p.dim, tw))];
    if installing && !job_line.is_empty() {
        lines.push(bx(w::line(t, &job_line, t.fs - 2.0, t.p.faint, tw, false)));
    }
    if !v.downloading.is_empty() {
        lines.push(bx(w::line(t, &format!("{} {}…", t.tr("Downloading the model", "Скачиваю модель"), v.downloading), t.fs - 2.0, t.p.warn, tw, false)));
    }
    let col = Column::new(lines).gap(3.0);
    let (_, ch) = w::wh(&col);
    let h = ch.max(56.0);
    items.push(bx(Rectangle::new().width(w).height(h + 40.0).radius(14.0).fill(t.p.surface).padding(20.0).child(
        Row::new(children![
            Rectangle::new().width(56.0).height(56.0).radius(16.0).fill(alpha(tint, 0.16)).align_child(Center, Center).child(ui::icon(t, icon, 26.0, tint)),
            Rectangle::new().width(tw).height(h).align_child(amane::Start, Center).child(col),
            br
        ])
        .gap(18.0)
        .height(h)
        .align(Center),
    )));
    if !v.installed {
        items.push(bx(w::para(
            t,
            &t.t("Installs voxtype-bin from AUR (the password is asked once). Then pick a model below — it's downloaded once and works without the internet."),
            t.fs - 2.0,
            t.p.dim,
            w,
        )));
        return Out { crumb: String::new(), subtitle: "Dictate text with your voice — Super+H".into(), items };
    }

    // ── запуск
    items.push(bx(w::section(t, "Startup", w)));
    items.push(bx(Card::new(0xF0412, "Start with the system", "Turn voice typing on at login. Off — it starts only when you turn it on here or press Super+H")
        .ctrl(w::switch(t, "vx-auto", v.autostart, voice::set_autostart))
        .build(t, w)));
    let od = v.get("whisper.on_demand_loading") == "true";
    items.push(bx(Card::new(0xF035B, "Load the model only while recording", "Saves memory: the model is read from disk when you start speaking and freed after. The first words take a moment longer")
        .ctrl(w::switch(t, "vx-ondemand", od, |on| voice::set("whisper.on_demand_loading", if on { "true" } else { "false" })))
        .build(t, w)));

    // ── модель распознавания
    items.push(bx(w::section(t, "Recognition model", w)));
    let cur = v.get("whisper.model");
    let shown = ["tiny", "base", "small", "medium", "large-v3-turbo"];
    let mut rows: Vec<W> = Vec::new();
    for m in shown {
        let installed = v.models.iter().any(|(n, i)| n == m && *i);
        let selected = cur == m;
        let desc = match m {
            "tiny" => t.t("Fastest, rough — fine for short commands"),
            "base" => t.t("Fast, decent quality"),
            "small" => t.t("Good balance for Russian and English (recommended)"),
            "medium" => t.t("More accurate, slower, needs more memory"),
            _ => t.t("Most accurate; fast enough with a strong CPU or GPU"),
        };
        let size = model_size(m);
        let mut ctrl: Vec<W> = vec![bx(ui::text(t, size, t.p.dim).size(t.fs - 2.0))];
        if v.downloading == m {
            ctrl.push(bx(ui::text(t, t.t("Downloading…"), t.p.warn).size(t.fs - 1.0)));
        } else if selected {
            ctrl.push(bx(Rectangle::new().width(90.0).height(30.0).radius(9.0).fill(alpha(t.p.accent, 0.16)).align_child(Center, Center).child(ui::text(t, t.t("In use"), t.p.accent).size(t.fs - 1.0))));
        } else {
            let m2 = m.to_string();
            let b = Btn::new(if installed { "Use" } else { "Download" }).enabled(v.downloading.is_empty());
            let b = if installed { b } else { b.icon(0xF01DA) };
            ctrl.push(bx(b.build(t, &format!("vx-m:{m}"), move || voice::use_model(&m2))));
        }
        let title = format!("{m}{}", if installed { "  ✓" } else { "" });
        rows.push(bx(Card::new(if selected { 0xF0133 } else { 0xF0130 }, &title, &desc).id(&format!("vx-model:{m}")).ctrl(Row::new(ctrl).gap(12.0).align(Center)).build(t, w)));
    }
    items.push(bx(Column::new(rows).gap(3.0)));

    // ── язык и текст
    items.push(bx(w::section(t, "Language and text", w)));
    let lang = Some(v.get("whisper.language")).filter(|x| !x.is_empty()).unwrap_or_else(|| "auto".into());
    let opts: Vec<(String, String)> = [("auto", "Detect automatically"), ("ru", "Russian"), ("en", "English"), ("ru,en", "Russian or English"), ("uk", "Ukrainian"), ("de", "German")]
        .iter()
        .map(|(a, b)| (a.to_string(), t.t(b)))
        .collect();
    items.push(bx(Card::new(0xF05CA, "Spoken language", "Fixing the language makes recognition faster and more accurate")
        .ctrl(w::dropdown(t, "vx-lang", &opts, &lang, 220.0, |l| voice::set("whisper.language", &l)))
        .build(t, w)));
    let tr = v.get("whisper.translate") == "true";
    items.push(bx(Card::new(0xF05CA, "Translate to English", "Type English text whatever language you speak")
        .ctrl(w::switch(t, "vx-translate", tr, |on| voice::set("whisper.translate", if on { "true" } else { "false" })))
        .build(t, w)));
    let mode = Some(v.get("output.mode")).filter(|x| !x.is_empty()).unwrap_or_else(|| "type".into());
    items.push(bx(Card::new(0xF030C, "Where the text goes", "Type into the active window, or copy to the clipboard")
        .ctrl(w::choice(t, "vx-mode", &[("type", "Type"), ("clipboard", "Clipboard"), ("paste", "Paste")], &mode, |m| voice::set("output.mode", &m)))
        .build(t, w)));
    let max: f64 = v.get("audio.max_duration_secs").parse().unwrap_or(120.0);
    items.push(bx(Card::new(0xF051B, "Longest recording", "Recording stops by itself after this time")
        .ctrl(Slide::new(max, 15.0, 300.0, 15.0).suffix(if ru { " с" } else { " s" }).build(t, "vx-max", |s| voice::set("audio.max_duration_secs", &format!("{}", s.round() as i64))))
        .build(t, w)));
    let note = v.get("output.notification.on_transcription") == "true";
    items.push(bx(Card::new(0xF009A, "Notify with the recognized text", "")
        .ctrl(w::switch(t, "vx-notify", note, |on| voice::set("output.notification.on_transcription", if on { "true" } else { "false" })))
        .build(t, w)));
    let prompt = v.get("whisper.initial_prompt");
    let prompt = if prompt == "unset" { String::new() } else { prompt };
    if w::field_text("vx-prompt").is_empty() && !prompt.is_empty() && super::super::Prefs::get("vx-prompt-init").is_empty() {
        let p2 = prompt.clone();
        std::thread::spawn(move || {
            super::super::Prefs::set("vx-prompt-init", "1");
            w::set_field("vx-prompt", &p2);
        });
    }
    items.push(bx(Card::new(0xF0369, "Words to recognize better", "Names and terms, comma-separated — Enter to save")
        .ctrl(w::field(t, "vx-prompt", 300.0, "Rexilone, niri, amane…", 0, |s| voice::set("whisper.initial_prompt", s.trim())))
        .build(t, w)));

    // ── управление
    items.push(bx(w::section(t, "Control", w)));
    items.push(bx(Card::new(0xF0313, "Shortcut", "Super+H — start, Super+H again — stop and type. Change it in Keyboard shortcuts").click(|| super::super::show(11)).build(t, w)));
    items.push(bx(Card::new(0xF0493, "Advanced settings", "All Voxtype options in its own terminal interface")
        .ctrl(Btn::new("Open").build(t, "vx-tui", || amane::spawn("setsid -f foot -T Voxtype voxtype configure >/dev/null 2>&1")))
        .build(t, w)));
    items.push(bx(Card::new(ui::ic::TRASH, "Remove Voxtype", "Uninstalls the program; downloaded models stay in ~/.local/share/voxtype")
        .ctrl(Btn::new("Remove").danger().enabled(!v.running && !installing).build(t, "vx-remove", voice::uninstall))
        .build(t, w)));
    let _ = Padding::default();
    Out { crumb: String::new(), subtitle: "Dictate text with your voice — Super+H".into(), items }
}
