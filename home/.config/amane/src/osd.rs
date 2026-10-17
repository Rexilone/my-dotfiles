// нижний индикатор (Osd.qml): выезжает снизу, когда меняются громкость, микрофон или яркость

use std::time::{Duration, Instant};

use amane::{
    Animation, Audio, Brightness, Center, Column, Full, Layer, LayerWindow, Parent, Rectangle, Row, Service, Shadow,
    SpaceBetween, Start, Vertical, Weight, Zone, children,
};

use crate::look;
use crate::popups::Popups;
use crate::settings::Settings;
use crate::ui;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Kind {
    Volume,
    Mic,
    Brightness,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Levels {
    pub vol: u8,
    pub mute: bool,
    pub mic: u8,
    pub mic_mute: bool,
    pub bright: Option<u8>,
}

pub struct Osd {
    pub kind: Kind,
    pub until: Option<Instant>,
    last: Option<Levels>,
    started: Instant,
    pub anim: Animation,
}

// что изменилось с прошлого раза (первые значения после запуска не показываем)
pub fn changed(prev: Option<Levels>, now: Levels) -> Option<Kind> {
    let p = prev?;
    if p.vol != now.vol || p.mute != now.mute {
        Some(Kind::Volume)
    } else if p.mic != now.mic || p.mic_mute != now.mic_mute {
        Some(Kind::Mic)
    } else if p.bright != now.bright && now.bright.is_some() {
        Some(Kind::Brightness)
    } else {
        None
    }
}

fn levels() -> Levels {
    let a = Audio::read();
    let b = Brightness::read();
    Levels {
        vol: a.volume(),
        mute: a.muted(),
        mic: a.microphone_volume(),
        mic_mute: a.microphone_muted(),
        bright: b.present().then(|| b.percent()),
    }
}

impl Service for Osd {
    fn new() -> Self {
        Osd { kind: Kind::Volume, until: None, last: None, started: Instant::now(), anim: crate::look::anim(0.0, 280) }
    }

    fn interval() -> Duration {
        Duration::from_millis(100)
    }

    fn update(&mut self) -> bool {
        let now = levels();
        let warm = self.started.elapsed() > Duration::from_millis(2500);
        let kind = changed(self.last, now);
        self.last = Some(now);
        let mut redraw = false;
        // пока открыто меню бара (там свой ползунок), громкость не показываем
        // открыто меню бара или «Звук» в Настройках — там свой ползунок
        let menu = !Popups::read().open.is_empty() || {
            let p = crate::prefs::Prefs::read();
            p.open && p.page == 2
        };
        let on = Settings::read().c.module_on("osd", true);
        if let Some(k) = kind.filter(|_| warm && on && !(menu && k_is_audio(kind))) {
            if self.until.is_none() {
                // появление — после первого кадра (look::appear)
            }
            self.kind = k;
            self.until = Some(Instant::now() + Duration::from_millis(1600));
            redraw = true;
        }
        if self.until.is_some_and(|t| Instant::now() >= t) {
            self.until = None;
            crate::look::go(&mut self.anim, 0.0);
            redraw = true;
        }
        redraw
    }
}

fn k_is_audio(k: Option<Kind>) -> bool {
    matches!(k, Some(Kind::Volume) | Some(Kind::Mic))
}

pub fn view(m: &amane::Monitor) -> LayerWindow {
    let t = look::tk();
    let here = crate::focus_output() == m.name;
    let o = Osd::read();
    let k = if here { o.anim.value() } else { 0.0 };
    let kind = o.kind;
    let open = here && o.until.is_some();
    drop(o);
    look::appear("osd", open, || {
        let mut x = Osd::write();
        if x.until.is_some() {
            look::go(&mut x.anim, 1.0);
        }
    });
    let l = levels();
    let (level, muted, label) = match kind {
        Kind::Volume => (l.vol, l.mute, t.tr("Volume", "Громкость")),
        Kind::Mic => (l.mic, l.mic_mute, t.tr("Microphone", "Микрофон")),
        Kind::Brightness => (l.bright.unwrap_or(0), false, t.tr("Brightness", "Яркость")),
    };
    let icon = match kind {
        Kind::Brightness => {
            if level < 34 {
                0xF00DE
            } else if level < 67 {
                0xF00DF
            } else {
                0xF00E0
            }
        }
        Kind::Mic => ui::volume_icon(true, muted, level),
        Kind::Volume => ui::volume_icon(false, muted, level),
    };
    let w = 380.0 - 40.0;
    let inner = w - 18.0 - 20.0 - 24.0 - 14.0;
    let title = if muted { format!("{label}   ·   {}", t.tr("muted", "без звука")) } else { label.to_string() };
    let ratio = (level as f32 / 100.0).clamp(0.0, 1.5);
    let over = ratio > 1.0;
    let fill = if muted { t.p.dim } else if over { t.p.warn } else { t.p.accent };
    let bar = Rectangle::new()
        .width(inner)
        .height(4.0)
        .radius(2.0)
        .fill(t.p.faint)
        .child(Rectangle::new().width(inner * ratio.min(1.0)).height(4.0).radius(2.0).fill(fill));
    let card = Rectangle::new()
        .width(w)
        .height(56.0)
        .radius(Full)
        .fill(t.panel)
        .border(1.0, t.p.surface_hi2)
        .shadow(Shadow::drop("#000000").opacity(0.44).blur(24.0).offset(0.0, 6.0))
        .padding(amane::Padding { top: 0.0, right: 20.0, bottom: 0.0, left: 18.0 })
        .opacity(k)
        .translate(0.0, (1.0 - k) * 90.0)
        .child(
            Row::new(children![
                Rectangle::new().width(24.0).height(24.0).align_child(Center, Center).child(ui::icon(&t, icon, t.icon + 4.0, if muted { t.p.dim } else { t.p.fg })),
                Column::new(children![
                    Row::new(children![
                        Rectangle::new().width(inner - 50.0).height(t.fs + 2.0).align_child(Start, Center).child(ui::bold(&t, title, t.p.fg).size(t.fs - 1.0).weight(Weight::Bold).elide()),
                        ui::text(&t, format!("{level}%"), t.p.dim).size(t.fs - 1.0)
                    ])
                    .width(inner)
                    .justify(SpaceBetween)
                    .align(Center),
                    bar
                ])
                .gap(6.0)
            ])
            .gap(14.0)
            .height(56.0)
            .align(Center),
        );
    LayerWindow::new()
        .width(380.0)
        .height(110.0)
        .anchor_vertical(Vertical::Bottom)
        .layer(Layer::Overlay)
        .space(Zone::Ignore)
        .namespace("rexilone-osd")
        .click_through()
        .visible(open || k > 0.01)
        .child(Rectangle::new().width(Parent).height(Parent).padding(amane::Padding { top: 30.0, right: 20.0, bottom: 24.0, left: 20.0 }).child(card))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lv(vol: u8, mute: bool, mic: u8, bright: Option<u8>) -> Levels {
        Levels { vol, mute, mic, mic_mute: false, bright }
    }

    #[test]
    fn first_reading_is_silent() {
        assert_eq!(changed(None, lv(50, false, 50, None)), None);
    }

    #[test]
    fn detects_what_changed() {
        let a = lv(50, false, 40, Some(70));
        assert_eq!(changed(Some(a), a), None);
        assert_eq!(changed(Some(a), lv(55, false, 40, Some(70))), Some(Kind::Volume));
        assert_eq!(changed(Some(a), lv(50, true, 40, Some(70))), Some(Kind::Volume));
        assert_eq!(changed(Some(a), lv(50, false, 45, Some(70))), Some(Kind::Mic));
        assert_eq!(changed(Some(a), lv(50, false, 40, Some(60))), Some(Kind::Brightness));
        // яркость пропала (монитор отключили) — не показываем
        assert_eq!(changed(Some(a), lv(50, false, 40, None)), None);
    }
}
