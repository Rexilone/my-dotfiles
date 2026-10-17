// микшер (Mixer.qml + VolumeRow.qml): общая громкость до 150%, устройства, громкость приложений,
// индикаторы уровня у ползунков

use amane::{Button, Center, Color, Column, End, Image, Padding, Pointer, Rectangle, Row, Service, Stack, Start, Weight, Widget, children};

use crate::look::Tk;
use crate::meter;
use crate::pw::{self, Node, Pw};
use crate::ui;

type W = Box<dyn Widget>;

fn bx(w: impl Widget + 'static) -> W {
    Box::new(w)
}

// ползунок 0–150% с отметкой 100% и уровнем звука поверх (Slider.qml)
pub fn slider<const H: u8>(t: &Tk, id: &str, width: f32, value: f64, muted: bool, level: Option<f32>, set: impl Fn(f64) + Clone + 'static) -> Rectangle {
    let ratio = (value / 1.5).clamp(0.0, 1.0) as f32;
    let hov = ui::hovered::<H>(id);
    let over = value > 1.0;
    let fill = if muted { t.p.dim } else if over { t.p.warn } else { t.p.accent };
    let mut track: Vec<W> = vec![bx(Rectangle::new().width(width).height(4.0).radius(2.0).fill(t.p.faint))];
    track.push(bx(Rectangle::new().width((width * ratio).max(0.0)).height(4.0).radius(2.0).fill(fill).opacity(if level.is_some() { 0.35 } else { 1.0 })));
    if let Some(l) = level.filter(|_| !muted) {
        track.push(bx(Rectangle::new().width((width * ratio * l.min(1.0)).max(0.0)).height(4.0).radius(2.0).fill(if over { t.p.warn } else { t.p.accent })));
    }
    // отметка 100%
    track.push(bx(Rectangle::new().width(2.0).height(8.0).radius(1.0).fill(t.p.dim).translate(width / 1.5 - 1.0, -2.0)));
    let knob = if hov { 12.0 } else { 10.0 };
    let s1 = set.clone();
    let s2 = set.clone();
    let r = Rectangle::new()
        .width(width)
        .height(16.0)
        .cursor(Pointer)
        .on_drag(move |p| {
            let mut v = (p.x / width).clamp(0.0, 1.0) as f64 * 1.5;
            if (v - 1.0).abs() < 0.02 {
                v = 1.0; // «прилипание» к 100%
            }
            s1(v)
        })
        .on_click(|_| {})
        .on_scroll(move |s| s2((value + if s.y < 0.0 { 0.05 } else { -0.05 }).clamp(0.0, 1.5)))
        .child(Stack::new(children![
            Rectangle::new().width(width).height(16.0).align_child(Start, Center).child(Stack::new(track)),
            Rectangle::new().width(width).height(16.0).align_child(Start, Center).child(
                Rectangle::new().width(knob).height(knob).radius(amane::Full).fill(if muted { t.p.dim } else { t.p.fg }).translate(width * ratio - knob / 2.0, 0.0)
            )
        ]));
    ui::track::<H>(r, id.to_string())
}

fn meter_target(n: &Node) -> (String, bool) {
    // приложения — по object.serial, устройства — по имени
    if n.is_out_stream() || n.is_in_stream() { (n.serial.clone(), false) } else { (n.name.clone(), n.is_sink()) }
}

// строка громкости: [мьют] [ползунок] [проценты]
pub fn volume_row<const H: u8>(t: &Tk, n: &Node, width: f32, input: bool, meters: bool) -> Row {
    let vol_pct = (n.volume * 100.0).round() as u8;
    let mid = format!("mute:{}", n.id);
    let id = n.id;
    let muted = n.muted;
    let mute = ui::track::<H>(
        Rectangle::new().width(18.0).height(20.0).align_child(Center, Center).cursor(Pointer).child(ui::icon(t, ui::volume_icon(input, muted, vol_pct.min(150)), t.icon, if muted { t.p.dim } else { t.p.fg })),
        mid,
    )
    .on_click(move |b| {
        if b == Button::Left {
            pw::set_mute(id, !muted)
        }
    });
    let level = meters.then(|| {
        let (target, sink) = meter_target(n);
        meter::level(&target, sink)
    });
    let sw = width - 18.0 - 38.0 - 20.0;
    let s = slider::<H>(t, &format!("vol:{}", n.id), sw, n.volume, muted, level, move |v| pw::set_volume(id, v));
    let pct = Rectangle::new().width(38.0).height(20.0).align_child(End, Center).child(ui::text(t, format!("{vol_pct}%"), if muted { t.p.dim } else { t.p.fg }));
    Row::new(children![mute, s, pct]).gap(10.0).align(Center)
}

fn caption(t: &Tk, s: &str) -> Rectangle {
    Rectangle::new().width(200.0).height(t.fs + 4.0).padding(Padding { top: 2.0, right: 0.0, bottom: 0.0, left: 0.0 }).child(ui::text(t, t.t(s), t.p.dim).size(t.fs - 2.0).weight(Weight::Bold))
}

pub fn mixer<const H: u8>(t: &Tk, width: f32, input: bool, meters: bool) -> Column {
    let p = Pw::read();
    let cur = p.current(input);
    let devices = p.devices(input);
    let streams = p.streams(input);
    drop(p);
    let mut col: Vec<W> = Vec::new();
    if let Some(c) = &cur {
        col.push(bx(Rectangle::new().width(width).height(52.0).radius(12.0).fill(t.p.surface).padding(Padding { top: 0.0, right: 14.0, bottom: 0.0, left: 14.0 }).align_child(Start, Center).child(volume_row::<H>(t, c, width - 28.0, input, meters))));
    }
    col.push(bx(caption(t, if input { "INPUT DEVICE" } else { "OUTPUT DEVICE" })));
    let mut devs: Vec<W> = Vec::new();
    for d in &devices {
        let sel = cur.as_ref().is_some_and(|c| c.id == d.id);
        let hid = format!("dev:{}", d.id);
        let hv = ui::hovered::<H>(&hid);
        let icon = if input {
            ui::ic::MIC
        } else if d.desc.to_lowercase().contains("hdmi") || d.desc.to_lowercase().contains("displayport") {
            0xF0379
        } else {
            0xF02CB
        };
        let name = ui::text(t, d.desc.clone(), if sel { t.p.fg } else { t.p.muted }).size(t.fs - 1.0);
        let name = if sel { name.weight(Weight::Bold) } else { name };
        let mut layers: Vec<W> = Vec::new();
        if sel {
            layers.push(bx(Rectangle::new().width(3.0).height(16.0).radius(2.0).fill(t.p.accent).translate(5.0, 10.0)));
        }
        layers.push(bx(Rectangle::new().width(width - 8.0).height(36.0).padding(Padding { top: 0.0, right: 12.0, bottom: 0.0, left: 16.0 }).child(
            Row::new(children![
                ui::icon(t, icon, t.icon - 1.0, if sel { t.p.accent } else { t.p.dim }),
                Rectangle::new().width(width - 8.0 - 28.0 - t.icon - 10.0).height(36.0).align_child(Start, Center).clip().child(name.elide())
            ])
            .gap(10.0)
            .height(36.0)
            .align(Center),
        )));
        let id = d.id;
        let r = Rectangle::new()
            .width(width - 8.0)
            .height(36.0)
            .radius(9.0)
            .fill(if sel { t.p.surface_hi2 } else if hv { t.p.surface_hi } else { Color::TRANSPARENT })
            .cursor(Pointer)
            .on_click(move |_| pw::set_default(id))
            .child(Stack::new(layers));
        devs.push(bx(ui::track::<H>(r, hid)));
    }
    let dcol = Column::new(devs).gap(2.0);
    let (_, dh) = ui::size_of(&dcol);
    col.push(bx(Rectangle::new().width(width).height(dh + 8.0).radius(12.0).fill(t.p.surface).padding(4.0).child(dcol)));
    col.push(bx(caption(t, "APPS")));
    if streams.is_empty() {
        col.push(bx(Rectangle::new().width(width).height(t.fs + 6.0).padding(Padding { top: 0.0, right: 0.0, bottom: 0.0, left: 2.0 }).child(ui::text(t, t.t(if input { "No app is using the microphone" } else { "Nothing is playing" }), t.p.faint).size(t.fs - 1.0))));
    }
    for s in &streams {
        let icon_path = crate::icons::resolve(&s.icon);
        let mut head: Vec<W> = Vec::new();
        if let Some(p) = icon_path {
            head.push(bx(Rectangle::new().width(16.0).height(16.0).fill(Image::contain(p))));
        }
        head.push(bx(Rectangle::new().width(width - 28.0 - 24.0).height(t.fs + 4.0).align_child(Start, Center).clip().child(ui::text(t, s.title(), t.p.fg).size(t.fs - 1.0).elide())));
        let c = Column::new(children![Row::new(head).gap(8.0).align(Center), volume_row::<H>(t, s, width - 28.0, input, meters)]).gap(4.0);
        let (_, ch) = ui::size_of(&c);
        col.push(bx(Rectangle::new().width(width).height(ch + 20.0).radius(12.0).fill(t.p.surface).padding(Padding { top: 10.0, right: 14.0, bottom: 10.0, left: 14.0 }).child(c)));
    }
    Column::new(col).gap(10.0)
}

#[allow(dead_code)]
fn unused(_: Node) {}
