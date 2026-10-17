// элементы Настроек — как settings/S*.qml: карточка, раздел, переключатель, сегменты, кнопка,
// ползунок, поле ввода, выпадающий список

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use amane::{
    Button, Center, Color, Column, End, Full, Padding, Parent, Pointer, Rectangle, Row, Size, Stack, Start, Text,
    TextInput, Weight, Widget, children,
};

use super::Prefs;
use crate::look::Tk;
use crate::ui::{self, PREFS};

pub type W = Box<dyn Widget>;
pub type Act = Rc<dyn Fn()>;

pub fn bx(w: impl Widget + 'static) -> W {
    Box::new(w)
}

pub fn act(f: impl Fn() + 'static) -> Act {
    Rc::new(f)
}

// ширина и высота виджета (для фиксированных)
pub fn wh(w: &dyn Widget) -> (f32, f32) {
    let f = |s: Size| match s {
        Size::Fixed(v) => v,
        Size::Parent => 0.0,
    };
    (f(w.width()), f(w.height()))
}

// имя для TextInput/ScrollArea должно жить всю программу — одно на строку
pub fn sid(s: &str) -> &'static str {
    thread_local! {
        static IDS: RefCell<HashMap<String, &'static str>> = RefCell::new(HashMap::new());
    }
    IDS.with_borrow_mut(|m| {
        if let Some(v) = m.get(s) {
            return *v;
        }
        let v: &'static str = Box::leak(s.to_string().into_boxed_str());
        m.insert(s.to_string(), v);
        v
    })
}

pub fn hov(id: &str) -> bool {
    ui::hovered::<PREFS>(id)
}

pub fn track(r: Rectangle, id: &str) -> Rectangle {
    ui::track::<PREFS>(r, id.to_string())
}

pub fn clickable(r: Rectangle, id: &str, f: Act) -> Rectangle {
    track(r, id).cursor(Pointer).on_click(move |b| {
        if b == Button::Left {
            f()
        }
    })
}

// текст по словарю
pub fn tx(t: &Tk, s: &str, size: f32, color: Color) -> Text {
    Text::new(t.t(s)).font(&t.font).size(size).color(color)
}

pub fn raw(t: &Tk, s: impl Into<String>, size: f32, color: Color) -> Text {
    Text::new(s.into()).font(&t.font).size(size).color(color)
}

pub fn line_h(size: f32) -> f32 {
    (size * 1.35).ceil()
}

// одна строка, обрезанная по ширине
pub fn line(t: &Tk, s: &str, size: f32, color: Color, width: f32, bold: bool) -> Rectangle {
    let x = raw(t, s, size, color);
    let x = if bold { x.weight(Weight::Bold) } else { x };
    Rectangle::new().width(width.max(1.0)).height(line_h(size)).align_child(Start, Center).clip().child(x.elide())
}

// перенос по словам; высота — по тексту
pub fn para(t: &Tk, s: &str, size: f32, color: Color, width: f32) -> Rectangle {
    let x = raw(t, s, size, color).wrap();
    let h = x.height_in(width.max(1.0)).max(line_h(size));
    Rectangle::new().width(width.max(1.0)).height(h).child(x)
}

pub fn gap(h: f32) -> Rectangle {
    Rectangle::new().width(1.0).height(h)
}

// ── раздел (SSection)
pub fn section(t: &Tk, s: &str, w: f32) -> Rectangle {
    Rectangle::new()
        .width(w)
        .height(16.0 + line_h(t.fs) + 4.0)
        .padding(Padding { top: 16.0, right: 0.0, bottom: 4.0, left: 0.0 })
        .child(tx(t, s, t.fs, t.p.fg).weight(Weight::Bold))
}

// ── карточка (SCard): значок, название, описание, справа — управление
pub struct Card<'a> {
    pub icon: u32,
    pub title: &'a str,
    pub desc: &'a str,
    pub ctrl: Option<W>,
    pub click: Option<Act>,
    pub id: &'a str,
}

impl<'a> Card<'a> {
    pub fn new(icon: u32, title: &'a str, desc: &'a str) -> Card<'a> {
        Card { icon, title, desc, ctrl: None, click: None, id: title }
    }
    pub fn ctrl(mut self, w: impl Widget + 'static) -> Self {
        self.ctrl = Some(bx(w));
        self
    }
    pub fn ctrl_box(mut self, w: W) -> Self {
        self.ctrl = Some(w);
        self
    }
    pub fn click(mut self, f: impl Fn() + 'static) -> Self {
        self.click = Some(act(f));
        self
    }
    pub fn id(mut self, id: &'a str) -> Self {
        self.id = id;
        self
    }

    pub fn build(self, t: &Tk, w: f32) -> Rectangle {
        let (cw, ch) = self.ctrl.as_ref().map(|c| wh(c.as_ref())).unwrap_or((0.0, 0.0));
        let chev = if self.click.is_some() { 16.0 + 12.0 } else { 0.0 };
        let icon_w = if self.icon != 0 { 22.0 + 16.0 } else { 0.0 };
        let text_w = (w - 18.0 - 16.0 - icon_w - if cw > 0.0 { cw + 16.0 } else { 0.0 } - chev).max(40.0);
        let title = line(t, &t.t(self.title), t.fs, t.p.fg, text_w, false);
        let mut col: Vec<W> = vec![bx(title)];
        let mut th = line_h(t.fs);
        if !self.desc.is_empty() {
            let d = para(t, &t.t(self.desc), t.fs - 2.0, t.p.dim, text_w);
            th += 2.0 + wh(&d).1;
            col.push(bx(d));
        }
        let h = (th.max(ch) + 26.0).max(64.0);
        let mut row: Vec<W> = Vec::new();
        if self.icon != 0 {
            row.push(bx(Rectangle::new().width(22.0).height(h).align_child(Center, Center).child(ui::icon(t, self.icon, t.icon + 3.0, t.p.fg))));
        }
        row.push(bx(Rectangle::new().width(text_w).height(h).align_child(Start, Center).child(Column::new(col).gap(2.0))));
        if let Some(c) = self.ctrl {
            row.push(bx(Rectangle::new().width(cw).height(h).align_child(End, Center).child(Column::new(vec![c]))));
        }
        if self.click.is_some() {
            row.push(bx(Rectangle::new().width(12.0).height(h).align_child(Center, Center).child(raw(t, "›", t.icon + 4.0, t.p.dim))));
        }
        let id = format!("card:{}", self.id);
        let hovering = self.click.is_some() && hov(&id);
        let r = Rectangle::new()
            .width(w)
            .height(h)
            .radius(10.0)
            .fill(if hovering { t.p.surface_hi } else { t.p.surface })
            .padding(Padding { top: 0.0, right: 16.0, bottom: 0.0, left: 18.0 })
            .child(Row::new(row).gap(16.0).height(h).align(Center));
        match self.click {
            Some(f) => clickable(r, &id, f),
            None => r,
        }
    }
}

// ── переключатель (SSwitch)
pub fn switch(t: &Tk, id: &str, on: bool, f: impl Fn(bool) + 'static) -> Rectangle {
    let h = hov(id);
    let knob = Rectangle::new()
        .width(12.0)
        .height(12.0)
        .radius(Full)
        .fill(if on { t.p.bg } else if h { t.p.fg } else { t.p.dim })
        .translate(if on { 44.0 - 12.0 - 5.0 } else { 5.0 }, 0.0);
    let mut r = Rectangle::new().width(44.0).height(24.0).radius(Full).align_child(Start, Center).child(knob);
    r = if on { r.fill(t.p.accent) } else { r.border(1.5, if h { t.p.fg } else { t.p.dim }) };
    clickable(r, id, act(move || f(!on)))
}

// ── сегменты (SChoice): [(значение, подпись)]
pub fn choice(t: &Tk, id: &str, opts: &[(&str, &str)], current: &str, f: impl Fn(String) + 'static) -> Rectangle {
    let f = Rc::new(f);
    let mut items: Vec<W> = Vec::new();
    for (v, label) in opts {
        let sel = *v == current;
        let oid = format!("{id}:{v}");
        let hv = hov(&oid);
        let txt = tx(t, label, t.fs - 1.0, if sel { t.p.bg } else if hv { t.p.fg } else { t.p.muted });
        let txt = if sel { txt.weight(Weight::Bold) } else { txt };
        let w = wh(&txt).0 + 24.0;
        let v = v.to_string();
        let f = f.clone();
        let r = Rectangle::new()
            .width(w)
            .height(28.0)
            .radius(7.0)
            .fill(if sel { t.p.accent } else { Color::TRANSPARENT })
            .align_child(Center, Center)
            .child(txt);
        items.push(bx(clickable(r, &oid, act(move || f(v.clone())))));
    }
    let row = Row::new(items);
    let (w, _) = wh(&row);
    Rectangle::new()
        .width(w + 6.0)
        .height(34.0)
        .radius(9.0)
        .fill(t.p.surface_hi)
        .border(1.0, t.p.surface_hi2)
        .padding(3.0)
        .child(row)
}

// ── кнопка (SButton)
pub struct Btn<'a> {
    pub text: &'a str,
    pub icon: u32,
    pub primary: bool,
    pub danger: bool,
    pub enabled: bool,
}

impl<'a> Btn<'a> {
    pub fn new(text: &'a str) -> Btn<'a> {
        Btn { text, icon: 0, primary: false, danger: false, enabled: true }
    }
    pub fn icon(mut self, i: u32) -> Self {
        self.icon = i;
        self
    }
    pub fn primary(mut self) -> Self {
        self.primary = true;
        self
    }
    pub fn primary_if(mut self, on: bool) -> Self {
        self.primary = on;
        self
    }
    pub fn danger(mut self) -> Self {
        self.danger = true;
        self
    }
    pub fn enabled(mut self, e: bool) -> Self {
        self.enabled = e;
        self
    }
    pub fn build(self, t: &Tk, id: &str, f: impl Fn() + 'static) -> Rectangle {
        let h = hov(id) && self.enabled;
        let fg = if self.primary { t.p.bg } else if self.danger { t.p.urgent } else { t.p.fg };
        let mut parts: Vec<W> = Vec::new();
        if self.icon != 0 {
            parts.push(bx(ui::icon(t, self.icon, t.icon - 1.0, fg)));
        }
        if !self.text.is_empty() {
            let x = tx(t, self.text, t.fs - 1.0, fg);
            parts.push(bx(if self.primary { x.weight(Weight::Bold) } else { x }));
        }
        let row = Row::new(parts).gap(8.0).align(Center);
        let (w, _) = wh(&row);
        let fill = if self.primary {
            if h { t.p.fg_hover } else { t.p.accent }
        } else if h {
            t.p.surface_hi2
        } else {
            t.p.surface_hi
        };
        let mut r = Rectangle::new().width(w + 28.0).height(34.0).radius(8.0).fill(fill).align_child(Center, Center).opacity(if self.enabled { 1.0 } else { 0.4 }).child(row);
        if !self.primary {
            r = r.border(1.0, t.p.surface_hi2);
        }
        if self.enabled { clickable(r, id, act(f)) } else { r }
    }
}

// ── ползунок со значением справа (SSlider)
pub struct Slide {
    pub value: f64,
    pub from: f64,
    pub to: f64,
    pub step: f64,
    pub suffix: &'static str,
    pub decimals: usize,
    pub display: Option<f64>,
}

impl Slide {
    pub fn new(value: f64, from: f64, to: f64, step: f64) -> Slide {
        Slide { value, from, to, step, suffix: "", decimals: 0, display: None }
    }
    pub fn suffix(mut self, s: &'static str) -> Self {
        self.suffix = s;
        self
    }
    pub fn decimals(mut self, d: usize) -> Self {
        self.decimals = d;
        self
    }
    pub fn display(mut self, v: f64) -> Self {
        self.display = Some(v);
        self
    }
    pub fn build(self, t: &Tk, id: &str, f: impl Fn(f64) + Clone + 'static) -> Row {
        let (from, to, step) = (self.from, self.to, self.step);
        let ratio = ((self.value - from) / (to - from)) as f32;
        let s = ui::slider::<PREFS>(t, id, 200.0, ratio, false, false, move |r| {
            let v = from + r as f64 * (to - from);
            let v = (v / step).round() * step;
            f(v.clamp(from.min(to), to.max(from)))
        });
        let shown = self.display.unwrap_or(self.value);
        let label = raw(t, format!("{:.*}{}", self.decimals, shown, self.suffix), t.fs - 1.0, t.p.fg);
        Row::new(children![s, Rectangle::new().width(56.0).height(20.0).align_child(End, Center).child(label)]).gap(12.0).align(Center)
    }
}

// ── поле ввода (SField): текст хранит сам TextInput под именем id; on_change — копия в Prefs
pub fn field(t: &Tk, id: &str, w: f32, placeholder: &str, icon: u32, submit: impl Fn(String) + 'static) -> Rectangle {
    let sid = sid(id);
    let key = format!("field:{id}");
    let mut parts: Vec<W> = Vec::new();
    if icon != 0 {
        parts.push(bx(ui::icon(t, icon, t.icon - 1.0, t.p.dim)));
    }
    let iw = w - 24.0 - if icon != 0 { t.icon + 10.0 } else { 0.0 };
    parts.push(bx(Rectangle::new().width(iw).height(38.0).align_child(Start, Center).child(
        TextInput::new(sid)
            .size(t.fs - 1.0)
            .color(t.p.fg)
            .width(iw)
            .placeholder(t.t(placeholder))
            .on_change(move |v| Prefs::set(&key, &v))
            .on_submit(submit),
    )));
    Rectangle::new()
        .width(w)
        .height(38.0)
        .radius(9.0)
        .fill(t.p.surface_hi)
        .border(1.0, t.p.surface_hi2)
        .padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 12.0 })
        .child(Row::new(parts).gap(10.0).height(38.0).align(Center))
}

// текст поля (последнее, что ввели)
pub fn field_text(id: &str) -> String {
    Prefs::get(&format!("field:{id}"))
}

pub fn set_field(id: &str, text: &str) {
    TextInput::set_text(sid(id), text);
    Prefs::set(&format!("field:{id}"), text);
}

// ── выпадающий список (SDropdown): открывается вниз прямо в карточке
pub fn dropdown(t: &Tk, id: &str, opts: &[(String, String)], current: &str, min_w: f32, f: impl Fn(String) + 'static) -> Column {
    let open = Prefs::get("dd") == id;
    let sel = opts.iter().find(|(v, _)| v == current).map(|(_, l)| t.t(l)).unwrap_or_else(|| "—".into());
    let label = raw(t, sel.clone(), t.fs - 1.0, t.p.fg);
    let w = (wh(&label).0 + 50.0).max(min_w).min(420.0);
    let bid = format!("dd:{id}");
    let h = hov(&bid);
    let id_s = id.to_string();
    let head = Rectangle::new()
        .width(w)
        .height(34.0)
        .radius(8.0)
        .fill(if h || open { t.p.surface_hi2 } else { t.p.surface_hi })
        .border(1.0, if open { t.p.line } else { t.p.surface_hi2 })
        .padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 12.0 })
        .child(
            Row::new(children![
                Rectangle::new().width(w - 24.0 - t.icon - 8.0).height(34.0).align_child(Start, Center).clip().child(label.elide()),
                ui::icon(t, if open { 0xF0143 } else { 0xF0140 }, t.icon, t.p.dim)
            ])
            .gap(8.0)
            .height(34.0)
            .align(Center),
        );
    let head = clickable(head, &bid, act(move || {
        let cur = Prefs::get("dd");
        Prefs::set("dd", if cur == id_s { "" } else { &id_s });
        Prefs::set(&format!("dd-filter:{id_s}"), "");
    }));
    let mut parts: Vec<W> = vec![bx(head)];
    if open {
        let lw = w.max(200.0);
        let searchable = opts.len() > 12;
        let filter = Prefs::get(&format!("dd-filter:{id}")).to_lowercase();
        let shown: Vec<&(String, String)> = opts
            .iter()
            .filter(|(_, l)| filter.is_empty() || format!("{} {}", l, t.t(l)).to_lowercase().contains(&filter))
            .collect();
        let f = Rc::new(f);
        let mut rows: Vec<W> = Vec::new();
        if searchable {
            let fid = format!("dd-filter-input:{id}");
            let key = format!("dd-filter:{id}");
            let first = shown.first().map(|(v, _)| v.clone());
            let f2 = f.clone();
            rows.push(bx(Rectangle::new().width(lw - 8.0).height(32.0).radius(7.0).fill(t.p.surface_hi).padding(Padding { top: 0.0, right: 10.0, bottom: 0.0, left: 10.0 }).align_child(Start, Center).child(
                TextInput::new(sid(&fid))
                    .focused()
                    .size(t.fs - 1.0)
                    .color(t.p.fg)
                    .placeholder(if t.c.ru() { format!("Поиск: {}…", opts.len()) } else { format!("Search {} items…", opts.len()) })
                    .on_change(move |v| Prefs::set(&key, &v))
                    .on_submit(move |_| {
                        if let Some(v) = &first {
                            f2(v.clone());
                            Prefs::set("dd", "");
                        }
                    }),
            )));
        }
        let mut items: Vec<W> = Vec::new();
        for (v, l) in &shown {
            let isel = v == current;
            let iid = format!("ddi:{id}:{v}");
            let hv = hov(&iid);
            let mut layers: Vec<W> = Vec::new();
            if isel {
                layers.push(bx(Rectangle::new().width(3.0).height(14.0).radius(2.0).fill(t.p.accent).translate(4.0, 9.0)));
            }
            let txt = raw(t, t.t(l), t.fs - 1.0, if isel { t.p.fg } else { t.p.muted });
            let txt = if isel { txt.weight(Weight::Bold) } else { txt };
            layers.push(bx(Rectangle::new().width(lw - 8.0).height(32.0).padding(Padding { top: 0.0, right: 6.0, bottom: 0.0, left: 14.0 }).align_child(Start, Center).clip().child(txt.elide())));
            let v = v.clone();
            let f = f.clone();
            let r = Rectangle::new().width(lw - 8.0).height(32.0).radius(7.0).fill(if hv { t.p.surface_hi2 } else { Color::TRANSPARENT }).child(Stack::new(layers));
            items.push(bx(clickable(r, &iid, act(move || {
                f(v.clone());
                Prefs::set("dd", "");
            }))));
        }
        let list_h = (shown.len() as f32 * 32.0).min(320.0);
        let total = shown.len() as f32 * 32.0;
        let off_key = format!("dd-off:{id}");
        let off = Prefs::get(&off_key).parse::<f32>().unwrap_or(0.0).clamp(0.0, (total - list_h).max(0.0));
        let list = Rectangle::new()
            .width(lw - 8.0)
            .height(list_h)
            .clip()
            .on_scroll(move |s| {
                let cur = Prefs::get(&off_key).parse::<f32>().unwrap_or(0.0);
                Prefs::set(&off_key, &((cur + s.y * 32.0).clamp(0.0, (total - list_h).max(0.0))).to_string());
            })
            .child(Rectangle::new().width(lw - 8.0).height(total.max(1.0)).translate(0.0, -off).child(Column::new(items)));
        rows.push(bx(list));
        let col = Column::new(rows).gap(4.0);
        let (_, chh) = wh(&col);
        parts.push(bx(Rectangle::new().width(lw).height(chh + 8.0).radius(10.0).fill(t.p.surface).border(1.0, t.p.line).padding(4.0).child(col)));
    }
    Column::new(parts).gap(4.0)
}

// ── плитка-переход (как быстрые переходы на странице «Система»)
pub fn tile(t: &Tk, id: &str, w: f32, icon: u32, title: &str, desc: &str, f: impl Fn() + 'static) -> Rectangle {
    let h = hov(id);
    let tw = w - 32.0 - t.icon - 6.0 - 14.0;
    let r = Rectangle::new()
        .width(w)
        .height(74.0)
        .radius(10.0)
        .fill(if h { t.p.surface_hi } else { t.p.surface })
        .padding(16.0)
        .child(
            Row::new(children![
                ui::icon(t, icon, t.icon + 6.0, t.p.accent),
                Column::new(children![line(t, &t.t(title), t.fs, t.p.fg, tw, false), line(t, &t.t(desc), t.fs - 2.0, t.p.dim, tw, false)]).gap(2.0)
            ])
            .gap(14.0)
            .height(42.0)
            .align(Center),
        );
    clickable(r, id, act(f))
}

// сетка из N колонок одинаковой ширины
pub fn grid(items: Vec<W>, cols: usize, gap_px: f32) -> Column {
    let mut rows: Vec<W> = Vec::new();
    let mut it = items.into_iter().peekable();
    while it.peek().is_some() {
        let line: Vec<W> = it.by_ref().take(cols).collect();
        rows.push(bx(Row::new(line).gap(gap_px)));
    }
    Column::new(rows).gap(gap_px)
}

// колонка с фиксированной шириной (для страниц)
pub fn col(items: Vec<W>, gap_px: f32) -> Column {
    Column::new(items).gap(gap_px)
}

pub fn width_for(cols: usize, total: f32, gap_px: f32) -> f32 {
    ((total - gap_px * (cols as f32 - 1.0)) / cols as f32).floor()
}

#[allow(dead_code)]
pub fn parent_box() -> Rectangle {
    Rectangle::new().width(Parent).height(Parent)
}
