// история буфера обмена (Super+V) — как Clipboard.qml, через cliphist.
// Enter — скопировать, ↑/↓ — выбор, Esc — закрыть; удалить запись — крестик, очистить всё — кнопка с подтверждением

use std::time::Duration;

use amane::{
    Animation, Center, Color, Column, End, Full, Image, Key, Keyboard, Layer, LayerWindow, Padding, Parent, Rectangle,
    Row, Service, Start, TextInput, Widget, Zone,
};

use crate::look;
use crate::niri::sh_quote;
use crate::ui::{self, CLIP, ic};

const WIDTH: f32 = 600.0;
const TEXT_H: f32 = 40.0;
const IMAGE_H: f32 = 96.0;
const MAX_H: f32 = 480.0;

#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub id: String,
    pub image: bool,
    pub file: String,
    pub text: String,
}

pub struct Clip {
    pub open: bool,
    pub output: String,
    pub entries: Vec<Entry>,
    pub query: String,
    pub sel: usize,
    pub scroll: f32,
    pub confirm_wipe: bool,
    pub want_refresh: bool,
    pub anim: Animation,
}

fn cache_dir() -> String {
    let base = std::env::var_os("XDG_CACHE_HOME").map(std::path::PathBuf::from).unwrap_or_else(|| crate::settings::home().join(".cache"));
    base.join("rexilone/clipboard").to_string_lossy().to_string()
}

// cliphist list → записи; картинки сохраняются в кэш, чтобы показать миниатюры
const LIST: &str = r#"
dir="$1"; mkdir -p "$dir"
cliphist list -preview-width 400 | head -n 300 | while IFS="$(printf '\t')" read -r id rest; do
    case "$rest" in
        "[[ binary data"*)
            ext=$(printf '%s' "$rest" | grep -oE 'png|jpe?g|webp|bmp|gif' | head -n1)
            f="$dir/$id.${ext:-png}"
            [ -s "$f" ] || printf '%s\t\n' "$id" | cliphist decode > "$f"
            printf '%s\timage\t%s\t%s\n' "$id" "$f" "$rest" ;;
        *)
            printf '%s\ttext\t\t%s\n' "$id" "$rest" ;;
    esac
done"#;

pub fn parse(text: &str) -> Vec<Entry> {
    text.lines()
        .filter_map(|l| {
            let mut it = l.splitn(4, '\t');
            let id = it.next()?.to_string();
            let kind = it.next()?;
            let file = it.next()?.to_string();
            let text = it.next().unwrap_or("").to_string();
            (!id.is_empty()).then_some(Entry { id, image: kind == "image", file, text })
        })
        .collect()
}

pub fn filter<'a>(entries: &'a [Entry], q: &str) -> Vec<&'a Entry> {
    let q = q.trim().to_lowercase();
    entries.iter().filter(|e| q.is_empty() || e.text.to_lowercase().contains(&q)).collect()
}

// «[[ binary data 12 KiB png 800x600 ]]» → «12 KiB png 800x600»
pub fn image_label(s: &str) -> &str {
    s.trim_start_matches("[[ binary data ").trim_end_matches(" ]]")
}

impl Service for Clip {
    fn new() -> Self {
        Clip {
            open: false,
            output: String::new(),
            entries: Vec::new(),
            query: String::new(),
            sel: 0,
            scroll: 0.0,
            confirm_wipe: false,
            want_refresh: false,
            anim: crate::look::anim(0.0, 220),
        }
    }

    // список читается в своём потоке и без блокировки: вид в это время рисуется дальше
    fn listen() {
        loop {
            std::thread::sleep(Duration::from_millis(50));
            if !Clip::read().want_refresh {
                continue;
            }
            Clip::write().want_refresh = false;
            let out = std::process::Command::new("sh").arg("-c").arg(LIST).arg("sh").arg(cache_dir()).output();
            let entries = out.map(|o| parse(&String::from_utf8_lossy(&o.stdout))).unwrap_or_default();
            let mut c = Clip::write();
            c.entries = entries;
            c.sel = 0;
        }
    }
}

pub fn toggle(_: &[String]) -> String {
    let open = !Clip::read().open;
    set_open(open);
    String::from(if open { "opened" } else { "closed" })
}

pub fn ipc(args: &[String]) -> String {
    match args.first().map(String::as_str) {
        Some("open") => set_open(true),
        Some("hide") | Some("close") => set_open(false),
        _ => return toggle(args),
    }
    String::from("ok")
}

pub fn set_open(open: bool) {
    let mut c = Clip::write();
    if c.open == open {
        return;
    }
    c.open = open;
    if open {
        c.output = crate::focus_output();
        c.query.clear();
        c.sel = 0;
        c.scroll = 0.0;
        c.confirm_wipe = false;
        c.want_refresh = true;
        c.anim = crate::look::anim(0.0, 220);
        // появление — после первого кадра (look::appear)
        TextInput::set_text("clipboard", "");
    } else {
        crate::look::go(&mut c.anim, 0.0);
    }
}

fn copy(id: &str) {
    amane::spawn(&format!("printf '%s\\t\\n' {} | cliphist decode | wl-copy", sh_quote(id)));
    set_open(false);
}

fn remove(id: &str) {
    let mut c = Clip::write();
    c.entries.retain(|e| e.id != id);
    let n = filter(&c.entries, &c.query).len();
    c.sel = c.sel.min(n.saturating_sub(1));
    drop(c);
    amane::spawn(&format!(
        "printf '%s\\t\\n' {id} | cliphist delete; rm -f {dir}/{id}.*",
        id = sh_quote(id),
        dir = sh_quote(&cache_dir())
    ));
}

fn wipe() {
    let mut c = Clip::write();
    if !c.confirm_wipe {
        c.confirm_wipe = true;
        return;
    }
    c.confirm_wipe = false;
    c.entries.clear();
    drop(c);
    amane::spawn(&format!("cliphist wipe; wl-copy --clear; rm -rf {}", sh_quote(&cache_dir())));
}

fn heights(list: &[&Entry]) -> Vec<f32> {
    list.iter().map(|e| if e.image { IMAGE_H } else { TEXT_H }).collect()
}

fn move_sel(d: i64) {
    let mut c = Clip::write();
    let list = filter(&c.entries, &c.query);
    if list.is_empty() {
        return;
    }
    let n = list.len() as i64;
    // как в Quickshell: по кругу
    let sel = (c.sel as i64 + d).rem_euclid(n) as usize;
    let hs = heights(&list);
    let view = hs.iter().sum::<f32>().min(MAX_H);
    c.sel = sel;
    c.scroll = keep(&hs, sel, c.scroll, view);
}

pub fn keep(hs: &[f32], sel: usize, scroll: f32, view: f32) -> f32 {
    let top: f32 = hs[..sel].iter().map(|h| h + 2.0).sum();
    let h = hs[sel];
    let total: f32 = hs.iter().map(|h| h + 2.0).sum();
    let mut s = scroll;
    if top < s {
        s = top;
    }
    if top + h > s + view {
        s = top + h - view;
    }
    s.clamp(0.0, (total - view).max(0.0))
}

fn on_key(k: Key) {
    match k {
        Key::Escape => set_open(false),
        Key::Down | Key::Tab => move_sel(1),
        Key::Up => move_sel(-1),
        _ => {}
    }
}

pub fn view(m: &amane::Monitor) -> LayerWindow {
    let t = look::tk();
    let c = Clip::read();
    let here = c.output == m.name;
    let k = if here { c.anim.value() } else { 0.0 };
    let open = c.open && here;
    look::appear("clipboard", open, || {
        let mut x = Clip::write();
        if x.open {
            look::go(&mut x.anim, 1.0);
        }
    });
    let list = filter(&c.entries, &c.query);

    let wipe_hov = ui::hovered::<CLIP>("wipe");
    let wipe_label = if c.confirm_wipe { t.tr("Confirm clear?", "Точно очистить?").to_string() } else { format!("{}  {}", ui::glyph(ic::TRASH), t.tr("Clear all", "Очистить")) };
    let wl = ui::text(&t, wipe_label, if c.confirm_wipe { t.p.urgent } else if wipe_hov { t.p.fg } else { t.p.dim }).size(t.fs - 1.0);
    let ww = crate::bar::width_of(&wl) + 20.0;
    let mut wipe_btn = Rectangle::new()
        .width(ww)
        .height(26.0)
        .radius(6.0)
        .fill(if c.confirm_wipe { crate::theme::alpha(t.p.urgent, 0.18) } else if wipe_hov { t.p.faint } else { Color::TRANSPARENT })
        .align_child(Center, Center)
        .child(wl);
    if c.confirm_wipe {
        wipe_btn = wipe_btn.border(1.0, t.p.urgent);
    }
    let wipe_btn = ui::on_left(
        wipe_btn.on_hover(|inside| {
            if inside {
                ui::Hover::<CLIP>::write().id = "wipe".into();
            } else {
                ui::clear_hover::<CLIP>();
                if Clip::read().confirm_wipe {
                    Clip::write().confirm_wipe = false;
                }
            }
        }),
        wipe,
    );
    let inner = WIDTH - 24.0;
    let has = !c.entries.is_empty();
    let input_w = inner - 8.0 - 4.0 - (t.icon + 2.0) - 12.0 * 2.0 - if has { ww } else { 0.0 };
    let mut head: Vec<Box<dyn Widget>> = vec![
        Box::new(ui::icon(&t, ic::CLIPBOARD, t.icon + 2.0, t.p.dim)),
        Box::new(Rectangle::new().width(input_w).height(36.0).align_child(Start, Center).child(
            TextInput::new("clipboard")
                .focused()
                .size(t.fs + 2.0)
                .color(t.p.fg)
                .placeholder(t.tr("Search clipboard…", "Поиск в буфере…"))
                .on_change(|text| {
                    let mut c = Clip::write();
                    c.query = text;
                    c.sel = 0;
                    c.scroll = 0.0;
                })
                .on_submit(|_| {
                    let c = Clip::read();
                    let id = filter(&c.entries, &c.query).get(c.sel).map(|e| e.id.clone());
                    drop(c);
                    if let Some(id) = id {
                        copy(&id);
                    }
                }),
        )),
    ];
    if has {
        head.push(Box::new(wipe_btn));
    }
    let head = Rectangle::new().width(inner).height(36.0).padding(Padding { top: 0.0, right: 4.0, bottom: 0.0, left: 8.0 }).child(Row::new(head).gap(12.0).height(36.0).align(Center));

    let mut col: Vec<Box<dyn Widget>> = vec![Box::new(head), Box::new(Rectangle::new().width(inner).height(1.0).fill(t.p.faint))];
    if list.is_empty() {
        let msg = if has { t.tr("Nothing found", "Ничего не найдено") } else { t.tr("Clipboard is empty", "Буфер обмена пуст") };
        col.push(Box::new(Rectangle::new().width(inner).height(60.0).align_child(Center, Center).child(ui::text(&t, msg, t.p.dim))));
    } else {
        let hs = heights(&list);
        let total: f32 = hs.iter().map(|h| h + 2.0).sum::<f32>() - 2.0;
        let view_h = total.min(MAX_H);
        let mut rows: Vec<Box<dyn Widget>> = Vec::new();
        for (i, e) in list.iter().enumerate() {
            let cur = i == c.sel;
            let rid = format!("row:{}", e.id);
            let hov = ui::hovered::<CLIP>(&rid) || ui::hovered::<CLIP>(&format!("del:{}", e.id));
            let h = hs[i];
            let did = format!("del:{}", e.id);
            let del_hov = ui::hovered::<CLIP>(&did);
            let id2 = e.id.clone();
            let del = ui::on_left(
                ui::track::<CLIP>(
                    Rectangle::new().width(24.0).height(24.0).align_child(Center, Center).opacity(if hov || cur { 1.0 } else { 0.0 }).child(ui::icon(&t, ic::CLOSE, t.icon, if del_hov { t.p.urgent } else { t.p.dim })),
                    did,
                ),
                move || remove(&id2),
            );
            let mut parts: Vec<Box<dyn Widget>> = Vec::new();
            let mut text_w = inner - 12.0 - 8.0 - 24.0 - 12.0;
            if e.image {
                parts.push(Box::new(Rectangle::new().width(140.0).height(80.0).radius(6.0).fill(Image::contain(&e.file).thumbnail(280, 160))));
                text_w -= 140.0 + 12.0;
            }
            let label = if e.image { image_label(&e.text).to_string() } else { e.text.trim().to_string() };
            let txt = ui::text(&t, label, if e.image { t.p.dim } else { t.p.fg }).size(if e.image { t.fs - 1.0 } else { t.fs });
            parts.push(Box::new(Rectangle::new().width(text_w).height(h).align_child(Start, Center).clip().child(txt.elide())));
            parts.push(Box::new(del));
            let id3 = e.id.clone();
            let row = Rectangle::new()
                .width(inner)
                .height(h)
                .radius(8.0)
                .fill(if cur { t.p.surface_hi2 } else { Color::TRANSPARENT })
                .padding(Padding { top: 0.0, right: 8.0, bottom: 0.0, left: 12.0 })
                .cursor(amane::Pointer)
                .on_click(move |_| copy(&id3))
                .child(Row::new(parts).gap(12.0).height(h).align(Center));
            let row = row.on_hover(move |inside| {
                if inside {
                    let mut c = Clip::write();
                    c.sel = i;
                    drop(c);
                    ui::Hover::<CLIP>::write().id = rid.clone();
                }
            });
            rows.push(Box::new(row));
        }
        let scroll = c.scroll;
        col.push(Box::new(
            Rectangle::new()
                .width(inner)
                .height(view_h)
                .clip()
                .on_scroll(move |s| {
                    let mut c = Clip::write();
                    c.scroll = (c.scroll + s.y * 40.0).clamp(0.0, (total - view_h).max(0.0));
                })
                .child(Rectangle::new().width(inner).height(total).translate(0.0, -scroll).child(Column::new(rows).gap(2.0))),
        ));
    }
    col.push(Box::new(Rectangle::new().width(inner).height(t.fs + 2.0).align_child(End, Center).padding(Padding { top: 0.0, right: 4.0, bottom: 0.0, left: 0.0 }).child(ui::text(
        &t,
        t.tr("Enter — copy · ✕ — delete", "Enter — скопировать · ✕ — удалить"),
        t.p.faint,
    )
    .size(t.fs - 2.0))));
    drop(c);
    let column = Column::new(col).gap(8.0);
    let (_, ch) = ui::size_of(&column);
    let card = Rectangle::new()
        .width(WIDTH)
        .height(ch + 24.0)
        .radius(t.radius + 2.0)
        .fill(t.panel)
        .border(1.0, t.p.faint)
        .padding(12.0)
        .opacity(k)
        .scale(0.96 + 0.04 * k)
        .on_click(|_| {})
        .child(column);
    let (_, sh) = amane::window_size();
    LayerWindow::new()
        .width(Full)
        .height(Full)
        .layer(Layer::Overlay)
        .space(Zone::Ignore)
        .namespace("rexilone-clipboard")
        .keyboard(if open { Keyboard::Exclusive } else { Keyboard::None })
        .on_key(on_key)
        .visible(open || k > 0.01)
        .child(
            Rectangle::new()
                .width(Parent)
                .height(Parent)
                .fill(Color::rgba(0, 0, 0, (0.35 * k * 255.0) as u8))
                .padding(Padding { top: (sh * 0.18).round(), right: 0.0, bottom: 0.0, left: 0.0 })
                .align_child(Center, Start)
                .on_click(|_| set_open(false))
                .child(card),
        )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_list_script_output() {
        let out = "12\ttext\t\thello\tworld\n11\timage\t/c/11.png\t[[ binary data 20 KiB png 100x50 ]]\n\nbroken\n";
        let e = parse(out);
        assert_eq!(e.len(), 2);
        assert_eq!(e[0], Entry { id: "12".into(), image: false, file: String::new(), text: "hello\tworld".into() });
        assert!(e[1].image);
        assert_eq!(e[1].file, "/c/11.png");
        assert_eq!(image_label(&e[1].text), "20 KiB png 100x50");
    }

    #[test]
    fn search_is_case_insensitive() {
        let e = parse("1\ttext\t\tHello\n2\ttext\t\tПривет мир\n");
        assert_eq!(filter(&e, "hel").len(), 1);
        assert_eq!(filter(&e, "МИР").len(), 1);
        assert_eq!(filter(&e, "  ").len(), 2);
        assert!(filter(&e, "zzz").is_empty());
    }

    #[test]
    fn scroll_keeps_selection() {
        let hs = vec![TEXT_H; 20];
        assert_eq!(keep(&hs, 0, 0.0, 400.0), 0.0);
        assert_eq!(keep(&hs, 12, 0.0, 400.0), 12.0 * 42.0 + 40.0 - 400.0);
        assert_eq!(keep(&hs, 2, 300.0, 400.0), 84.0);
    }
}
