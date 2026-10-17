// Bluetooth через bluez (BluetoothPage.qml)

use amane::{Bluetooth, Center, Row, Service, children};

use super::super::w::{self, Btn, Card, W, bx};
use super::Out;
use crate::look::Tk;
use crate::ui;

pub fn page(t: &Tk, w: f32) -> Out {
    let bt = Bluetooth::read();
    let mut items: Vec<W> = Vec::new();
    if !bt.available() {
        items.push(bx(Card::new(0xF00B2, "No Bluetooth adapter", "This computer has no Bluetooth adapter, or the bluetooth service is not running.\nPlug in a USB adapter — it will show up here.").build(t, w)));
        return Out { crumb: String::new(), subtitle: "Pair and connect devices".into(), items };
    }
    let (on, scanning) = (bt.powered(), bt.scanning());
    items.push(bx(Card::new(0xF00AF, "Bluetooth", &t.t(if on { "on" } else { "off" })).ctrl(w::switch(t, "bt-on", on, Bluetooth::set_powered)).build(t, w)));
    items.push(bx(Card::new(0xF0349, "Search for devices", if scanning { "Searching…" } else { "Make sure the device is in pairing mode" })
        .ctrl(w::switch(t, "bt-scan", scanning, move |v| {
            if on {
                if v { Bluetooth::start_scan() } else { Bluetooth::stop_scan() }
            }
        })
        .opacity(if on { 1.0 } else { 0.4 }))
        .build(t, w)));
    let mut devs: Vec<_> = bt.devices().to_vec();
    drop(bt);
    devs.sort_by(|a, b| b.connected().cmp(&a.connected()).then(b.paired().cmp(&a.paired())).then(a.name().to_lowercase().cmp(&b.name().to_lowercase())));
    if !devs.is_empty() {
        items.push(bx(w::section(t, "Devices", w)));
    }
    for d in devs {
        let state = t.t(if d.connected() { "Connected" } else if d.paired() { "Paired" } else { "Available" });
        let desc = match d.battery() {
            Some(b) => format!("{state} · {} {b}%", t.t("battery")),
            None => state,
        };
        let path = d.path().to_string();
        let mut ctrl: Vec<W> = Vec::new();
        if !d.paired() {
            let p = path.clone();
            ctrl.push(bx(Btn::new("Pair").build(t, &format!("pair:{path}"), move || Bluetooth::pair(&p))));
        } else {
            let (p, connected) = (path.clone(), d.connected());
            ctrl.push(bx(Btn::new(if connected { "Disconnect" } else { "Connect" }).enabled(true).build(t, &format!("conn:{path}"), move || {
                if connected { Bluetooth::disconnect(&p) } else { Bluetooth::connect(&p) }
            })));
            let p = path.clone();
            ctrl.push(bx(Btn::new("").icon(ui::ic::TRASH).danger().build(t, &format!("forget:{path}"), move || Bluetooth::forget(&p))));
        }
        let title = if d.name().is_empty() { d.address().to_string() } else { d.name().to_string() };
        items.push(bx(Card::new(0xF00AF, &title, &desc).id(&path).ctrl(Row::new(ctrl).gap(8.0).align(Center)).build(t, w)));
    }
    let _ = children![w::gap(1.0)];
    Out { crumb: String::new(), subtitle: "Pair and connect devices".into(), items }
}
