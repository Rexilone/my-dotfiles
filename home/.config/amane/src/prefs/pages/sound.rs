// Звук: устройства вывода/ввода, громкость до 150%, громкость приложений (SoundPage.qml)

use super::super::w::{self, Card, W, bx};
use super::Out;
use crate::json::Json;
use crate::look::Tk;
use crate::settings;
use crate::ui::PREFS;

pub fn page(t: &Tk, w: f32) -> Out {
    let mut items: Vec<W> = vec![bx(w::section(t, "Output", w)), bx(crate::mixer::mixer::<PREFS>(t, w, false, true))];
    items.push(bx(w::section(t, "Input", w)));
    items.push(bx(crate::mixer::mixer::<PREFS>(t, w, true, true)));
    items.push(bx(w::gap(10.0)));
    items.push(bx(Card::new(0xF1120, "More sound settings", "Open pavucontrol for profiles and advanced options").click(|| amane::spawn("setsid -f pavucontrol")).build(t, w)));
    items.push(bx(w::section(t, "Indicator", w)));
    items.push(bx(Card::new(0xF0A1D, "Pop-up at the bottom", "When volume, microphone or brightness change, and while voice typing listens (Super+H)")
        .ctrl(w::switch(t, "osd", t.c.module_on("osd", true), |v| settings::save_path(&["barModules", "osd"], Json::Bool(v))))
        .build(t, w)));
    Out { crumb: String::new(), subtitle: "Output and input devices, volume and per-app volume".into(), items }
}
