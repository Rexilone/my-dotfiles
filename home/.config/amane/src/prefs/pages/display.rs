// Дисплей: расположение мониторов, разрешение, частота, масштаб, поворот, VRR, ночной свет (DisplayPage.qml)

use amane::{Center, Color, Column, Padding, Rectangle, Row, Service, Stack, Start, Weight, children};

use super::super::Prefs;
use super::super::w::{self, Btn, Card, Slide, W, act, bx};
use super::Out;
use crate::json::Json;
use crate::look::Tk;
use crate::niriconf::{self, NiriConf};
use crate::nightlight::{self, NightLight};
use crate::settings::{self, Settings};
use crate::weather::Weather;

// изменённые, но ещё не применённые настройки мониторов — в Prefs как JSON
fn pending() -> Option<Json> {
    Json::parse(&Prefs::get("display:pending")).filter(|j| !j.obj().is_empty())
}

fn set_pending(j: &Json) {
    Prefs::set("display:pending", &j.pretty_with(0).replace('\n', ""));
}

fn current() -> Json {
    let live = NiriConf::read().live.clone();
    Json::Obj(niriconf::current(Settings::read().raw.get("outputs"), &live))
}

pub fn parse_mode(mode: &str) -> (f64, f64, f64) {
    let Some((wh, hz)) = mode.split_once('@') else { return (1920.0, 1080.0, 60.0) };
    let Some((w, h)) = wh.split_once('x') else { return (1920.0, 1080.0, 60.0) };
    match (w.parse(), h.parse(), hz.parse()) {
        (Ok(w), Ok(h), Ok(hz)) => (w, h, hz),
        _ => (1920.0, 1080.0, 60.0),
    }
}

fn rotated(t: &str) -> bool {
    t.contains("90") || t.contains("270")
}

// логический размер (с учётом масштаба и поворота)
pub fn logical(o: &Json) -> (f64, f64) {
    let (w, h, _) = parse_mode(&o.get("mode").str_or(""));
    let s = o.get("scale").num_or(1.0).max(0.1);
    if rotated(&o.get("transform").str_or("")) { (h / s, w / s) } else { (w / s, h / s) }
}

// примагничивание к ближайшему краю другого монитора, затем сдвиг к (0,0)
pub fn snap(p: &Json, name: &str, x: f64, y: f64) -> Json {
    let (aw, ah) = logical(p.get(name));
    let mut best = (x, y);
    let mut best_d = f64::INFINITY;
    for (other, o) in p.obj() {
        if other == name || o.get("off").bool_or(false) {
            continue;
        }
        let (bw, bh) = logical(o);
        let (ox, oy) = (o.get("x").num_or(0.0), o.get("y").num_or(0.0));
        let clamp_y = |v: f64| v.clamp(oy - ah + 50.0, oy + bh - 50.0);
        let clamp_x = |v: f64| v.clamp(ox - aw + 50.0, ox + bw - 50.0);
        let align_y = |v: f64| if (v - oy).abs() < 80.0 { oy } else if (v + ah - (oy + bh)).abs() < 80.0 { oy + bh - ah } else { v };
        let align_x = |v: f64| if (v - ox).abs() < 80.0 { ox } else if (v + aw - (ox + bw)).abs() < 80.0 { ox + bw - aw } else { v };
        for c in [(ox + bw, align_y(clamp_y(y))), (ox - aw, align_y(clamp_y(y))), (align_x(clamp_x(x)), oy + bh), (align_x(clamp_x(x)), oy - ah)] {
            let d = ((c.0 - x).powi(2) + (c.1 - y).powi(2)).sqrt();
            if d < best_d {
                best_d = d;
                best = c;
            }
        }
    }
    let mut out = p.clone();
    if let Some(o) = out.get_mut(name) {
        o.set("x", Json::Num(best.0.round()));
        o.set("y", Json::Num(best.1.round()));
    }
    let min_x = out.obj().iter().map(|(_, o)| o.get("x").num_or(0.0)).fold(f64::INFINITY, f64::min);
    let min_y = out.obj().iter().map(|(_, o)| o.get("y").num_or(0.0)).fold(f64::INFINITY, f64::min);
    if let Json::Obj(items) = &mut out {
        for (_, o) in items {
            let (x, y) = (o.get("x").num_or(0.0), o.get("y").num_or(0.0));
            o.set("x", Json::Num(x - min_x));
            o.set("y", Json::Num(y - min_y));
        }
    }
    out
}

// режимы монитора: уникальные «ШxВ@Гц», крупные и частые — первыми
pub fn modes(live: &Json, name: &str) -> Vec<(f64, f64, f64, bool, String)> {
    let mut v: Vec<(f64, f64, f64, bool, String)> = Vec::new();
    for m in live.get(name).get("modes").arr() {
        let k = niriconf::mode_key(m);
        if v.iter().any(|x| x.4 == k) {
            continue;
        }
        v.push((m.get("width").num_or(0.0), m.get("height").num_or(0.0), m.get("refresh_rate").num_or(0.0) / 1000.0, m.get("is_preferred").bool_or(false), k));
    }
    v.sort_by(|a, b| (b.0 * b.1).partial_cmp(&(a.0 * a.1)).unwrap().then(b.2.partial_cmp(&a.2).unwrap()));
    v
}

fn set_sel(key: &str, v: Json) {
    let mut p = pending().unwrap_or_else(current);
    let sel = Prefs::get("display:sel");
    if let Some(o) = p.get_mut(&sel) {
        o.set(key, v);
    }
    set_pending(&p);
}

pub fn page(t: &Tk, w: f32) -> Out {
    let live = NiriConf::read().live.clone();
    let cur = current();
    let p = pending().unwrap_or_else(|| cur.clone());
    let dirty = p != cur;
    let primary = t.c.primary(&crate::niri::Niri::read().s.outputs);
    let mut sel = Prefs::get("display:sel");
    if p.get(&sel).is_null() {
        sel = p.obj().iter().map(|(n, _)| n.clone()).find(|n| *n == primary).or_else(|| p.obj().first().map(|(n, _)| n.clone())).unwrap_or_default();
    }
    let selo = p.get(&sel).clone();
    let confirm_left = NiriConf::read().confirm_left;
    let mut items: Vec<W> = Vec::new();

    // ── подтверждение после применения
    if confirm_left > 0 {
        let msg = if t.c.ru() { format!("Оставить эти настройки дисплея? Откат через {confirm_left} с") } else { format!("Keep these display settings? Reverting in {confirm_left} s") };
        let tw = w - 18.0 - 14.0 - t.icon - 3.0 - 12.0 * 3.0 - 260.0;
        items.push(bx(Rectangle::new().width(w).height(64.0).radius(10.0).fill(t.p.surface_hi).border(1.0, t.p.warn).padding(Padding { top: 0.0, right: 14.0, bottom: 0.0, left: 18.0 }).child(
            Row::new(children![
                crate::ui::icon(t, 0xF0026, t.icon + 3.0, t.p.warn),
                w::line(t, &msg, t.fs, t.p.fg, tw, false),
                Btn::new("Revert").build(t, "disp-revert", || {
                    niriconf::revert();
                    Prefs::set("display:pending", "");
                }),
                Btn::new("Keep changes").primary().build(t, "disp-keep", || {
                    niriconf::confirm();
                    Prefs::set("display:pending", "");
                })
            ])
            .gap(12.0)
            .height(64.0)
            .align(Center),
        )));
    }

    // ── схема расположения
    let names: Vec<String> = p.obj().iter().filter(|(_, o)| !o.get("off").bool_or(false)).map(|(n, _)| n.clone()).collect();
    let (mut x0, mut y0, mut x1, mut y1) = (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
    for n in &names {
        let o = p.get(n);
        let (lw, lh) = logical(o);
        let (x, y) = (o.get("x").num_or(0.0), o.get("y").num_or(0.0));
        x0 = x0.min(x);
        y0 = y0.min(y);
        x1 = x1.max(x + lw);
        y1 = y1.max(y + lh);
    }
    if names.is_empty() {
        (x0, y0, x1, y1) = (0.0, 0.0, 1.0, 1.0);
    }
    let ah = 250.0f64;
    let k = ((w as f64 - 80.0) / (x1 - x0)).min((ah - 60.0) / (y1 - y0));
    let ox = (w as f64 - (x1 - x0) * k) / 2.0;
    let oy = (ah - (y1 - y0) * k) / 2.0;
    let mut layers: Vec<W> = vec![bx(Rectangle::new().width(w).height(30.0).padding(12.0).child(w::tx(t, "Drag monitors to arrange them", t.fs - 3.0, t.p.faint)))];
    for (i, n) in names.iter().enumerate() {
        let o = p.get(n);
        let (lw, lh) = logical(o);
        let mw = (lw * k - 4.0).max(10.0) as f32;
        let mh = (lh * k - 4.0).max(10.0) as f32;
        let mx = (ox + (o.get("x").num_or(0.0) - x0) * k) as f32;
        let my = (oy + (o.get("y").num_or(0.0) - y0) * k) as f32;
        let selected = *n == sel;
        let (mdw, mdh, hz) = parse_mode(&o.get("mode").str_or(""));
        let label = Column::new(children![
            w::raw(t, (i + 1).to_string(), t.fs + 10.0, if selected { t.p.fg } else { t.p.muted }).weight(Weight::Bold),
            w::raw(t, n.clone(), t.fs - 2.0, t.p.muted),
            w::raw(t, format!("{mdw}×{mdh} · {} Hz", hz.round()), t.fs - 3.0, t.p.dim)
        ])
        .gap(3.0)
        .align(Center);
        let (n1, n2) = (n.clone(), n.clone());
        let (kk, x0c, y0c, oxc, oyc) = (k, x0, y0, ox, oy);
        let r = Rectangle::new()
            .width(mw)
            .height(mh)
            .radius(8.0)
            .fill(if selected { t.p.surface_hi2 } else { t.p.surface_hi })
            .border(if selected { 2.0 } else { 1.0 }, if selected { t.p.accent } else { t.p.line })
            .translate(mx, my)
            .align_child(Center, Center)
            .clip()
            .cursor(amane::Grab)
            .on_drag(move |pt| {
                // первая точка — где схватили; дальше монитор едет за курсором
                let grab = Prefs::get("display:grab");
                let mut pend = pending().unwrap_or_else(current);
                if grab.is_empty() {
                    Prefs::set("display:grab", &format!("{} {}", pt.x, pt.y));
                    Prefs::set("display:sel", &n1);
                    return;
                }
                let (gx, gy) = grab.split_once(' ').map(|(a, b)| (a.parse::<f32>().unwrap_or(0.0), b.parse::<f32>().unwrap_or(0.0))).unwrap_or((0.0, 0.0));
                let o = pend.get(&n1).clone();
                let (cx, cy) = (o.get("x").num_or(0.0), o.get("y").num_or(0.0));
                let nx = cx + ((pt.x - gx) as f64) / kk;
                let ny = cy + ((pt.y - gy) as f64) / kk;
                if let Some(m) = pend.get_mut(&n1) {
                    m.set("x", Json::Num(nx));
                    m.set("y", Json::Num(ny));
                }
                let _ = (x0c, y0c, oxc, oyc);
                set_pending(&pend);
                Prefs::set("display:moved", "1");
            })
            // отпустили — примагнитить
            .on_click(move |_| {
                Prefs::set("display:grab", "");
                Prefs::set("display:sel", &n2);
                if Prefs::flag("display:moved") {
                    Prefs::set("display:moved", "");
                    let pend = pending().unwrap_or_else(current);
                    let o = pend.get(&n2).clone();
                    let snapped = snap(&pend, &n2, o.get("x").num_or(0.0), o.get("y").num_or(0.0));
                    set_pending(&snapped);
                }
            })
            .child(label);
        layers.push(bx(r));
    }
    items.push(bx(Rectangle::new().width(w).height(ah as f32).radius(10.0).fill(t.p.surface).clip().child(Stack::new(layers))));

    // ── главный монитор
    let mut names_live: Vec<(String, String)> = live.obj().iter().map(|(n, o)| (n.clone(), format!("{n}  ·  {}", o.get("model").str_or("")))).collect();
    names_live.sort();
    items.push(bx(Card::new(0xF0379, "Main display", "Gets focus at login, shows notifications and desktop widgets by default. Menus open where your cursor is.")
        .ctrl(w::dropdown(t, "primary", &names_live, &primary, 170.0, |v| settings::save_key("primaryOutput", Json::Str(v))))
        .build(t, w)));

    // ── настройки выбранного монитора
    if !sel.is_empty() {
        let lo = live.get(&sel);
        let title = format!("{sel}  ·  {} {}", lo.get("make").str_or(""), lo.get("model").str_or(""));
        items.push(bx(w::section(t, &title, w)));
        let mlist = modes(&live, &sel);
        let mut res: Vec<(String, String)> = Vec::new();
        for (mw, mh, _, pref, _) in &mlist {
            let k = format!("{mw}x{mh}");
            if !res.iter().any(|(v, _)| *v == k) {
                res.push((k, format!("{mw} × {mh}{}", if *pref { format!("  ({})", t.t("recommended")) } else { String::new() })));
            }
        }
        let mode = selo.get("mode").str_or("");
        let cur_res = mode.split('@').next().unwrap_or("").to_string();
        let ml = mlist.clone();
        items.push(bx(Card::new(0xF0379, "Display resolution", "Pick the resolution; the highest refresh rate is chosen automatically")
            .ctrl(w::dropdown(t, "res", &res, &cur_res, 180.0, move |v| {
                if let Some(best) = ml.iter().filter(|m| format!("{}x{}", m.0, m.1) == v).max_by(|a, b| a.2.partial_cmp(&b.2).unwrap()) {
                    set_sel("mode", Json::Str(best.4.clone()));
                }
            }))
            .build(t, w)));
        let rates: Vec<(String, String)> = mlist
            .iter()
            .filter(|m| format!("{}x{}", m.0, m.1) == cur_res)
            .map(|m| {
                let frac = m.2 % 1.0;
                let digits = if frac > 0.05 && frac < 0.95 { 2 } else { 0 };
                (m.4.clone(), format!("{:.*} Hz", digits, m.2))
            })
            .collect();
        items.push(bx(Card::new(0xF051B, "Refresh rate", "Higher is smoother").ctrl(w::dropdown(t, "rate", &rates, &mode, 140.0, |v| set_sel("mode", Json::Str(v)))).build(t, w)));
        let scales: Vec<(String, String)> = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
            .iter()
            .map(|v| (format!("{v}"), format!("{}%{}", (v * 100.0f64).round(), if *v == 1.0 { format!("  ({})", t.t("default")) } else { String::new() })))
            .collect();
        items.push(bx(Card::new(0xF1392, "Scale", "Size of text and apps")
            .ctrl(w::dropdown(t, "scale", &scales, &format!("{}", selo.get("scale").num_or(1.0)), 140.0, |v| set_sel("scale", Json::Num(v.parse().unwrap_or(1.0)))))
            .build(t, w)));
        items.push(bx(Card::new(0xF0467, "Rotation", "")
            .ctrl(w::choice(t, "rot", &[("normal", "0°"), ("90", "90°"), ("180", "180°"), ("270", "270°")], &selo.get("transform").str_or("normal"), |v| set_sel("transform", Json::Str(v))))
            .build(t, w)));
        if lo.get("vrr_supported").bool_or(false) {
            items.push(bx(Card::new(0xF1A0E, "Variable refresh rate", "FreeSync / VRR — smoother games, less tearing").ctrl(w::switch(t, "vrr", selo.get("vrr").bool_or(false), |v| set_sel("vrr", Json::Bool(v)))).build(t, w)));
        }
        let off = selo.get("off").bool_or(false);
        let can = off || names.len() > 1;
        items.push(bx(Card::new(0xF0425, "Use this display", "Turn the monitor off without unplugging it")
            .ctrl(w::switch(t, "use", !off, move |v| {
                if can {
                    set_sel("off", Json::Bool(!v))
                }
            })
            .opacity(if can { 1.0 } else { 0.4 }))
            .build(t, w)));
    }

    let pend2 = p.clone();
    let foot = Row::new(children![
        w::line(t, &if dirty { t.t("You have unapplied changes") } else { String::new() }, t.fs - 2.0, t.p.warn, w - 260.0, false),
        Btn::new("Reset").enabled(dirty).build(t, "disp-reset", || Prefs::set("display:pending", "")),
        Btn::new("Apply").primary().enabled(dirty && confirm_left == 0).build(t, "disp-apply", move || {
            niriconf::apply_outputs(pend2.clone());
            Prefs::set("display:pending", "");
        })
    ])
    .gap(8.0)
    .align(Center);
    items.push(bx(w::gap(12.0)));
    items.push(bx(foot));

    // ── ночной свет
    items.push(bx(w::section(t, "Night light", w)));
    let installed = NightLight::read().installed;
    let nl = Settings::read().raw.get("nightLight").clone();
    let ctrl: W = if installed {
        bx(w::switch(t, "nl", nightlight::on(), |v| settings::save_path(&["nightLight", "enabled"], Json::Bool(v))))
    } else {
        bx(Btn::new("Install").primary().build(t, "nl-install", nightlight::install))
    };
    items.push(bx(Card::new(0xF0335, "Night light", if installed { "Warmer colors that are easier on the eyes at night" } else { "Needs wlsunset — install it first" }).ctrl_box(ctrl).build(t, w)));
    if installed {
        let (configured, city) = {
            let wt = Weather::read();
            (wt.configured(), wt.city())
        };
        let desc = if configured {
            if t.c.ru() { format!("От заката до рассвета по городу из погоды ({city})") } else { format!("Sunset to sunrise uses your weather city ({city})") }
        } else {
            t.t("Set a weather city to use sunset to sunrise")
        };
        let auto = if nl.get("auto").bool_or(false) { "1" } else { "0" };
        items.push(bx(Card::new(0xF0590, "Schedule", &desc)
            .ctrl(w::choice(t, "nlauto", &[("0", "Always"), ("1", "Sunset → sunrise")], auto, move |v| {
                settings::save_path(&["nightLight", "auto"], Json::Bool(v == "1" && configured))
            }))
            .build(t, w)));
        items.push(bx(Card::new(0xF050F, "Warmth", "Lower is warmer")
            .ctrl(Slide::new(nl.get("temp").num_or(4500.0), 2500.0, 6000.0, 100.0).suffix(" K").build(t, "nltemp", |v| settings::save_path(&["nightLight", "temp"], Json::Num(v.round()))))
            .build(t, w)));
    }
    let _ = (Color::TRANSPARENT, Start, act(|| {}));
    Out { crumb: String::new(), subtitle: "Arrange monitors, resolution, refresh rate, scale and rotation".into(), items }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn outs() -> Json {
        Json::parse(r#"{"A":{"mode":"1920x1080@60.000","scale":1,"transform":"normal","x":0,"y":0},
                        "B":{"mode":"1440x900@75.000","scale":1,"transform":"270","x":0,"y":0}}"#).unwrap()
    }

    #[test]
    fn modes_and_logical_sizes() {
        assert_eq!(parse_mode("2560x1440@143.912"), (2560.0, 1440.0, 143.912));
        assert_eq!(parse_mode("junk"), (1920.0, 1080.0, 60.0));
        assert_eq!(logical(outs().get("B")), (900.0, 1440.0));
        let mut o = outs().get("A").clone();
        o.set("scale", Json::Num(2.0));
        assert_eq!(logical(&o), (960.0, 540.0));
    }

    #[test]
    fn snapping_to_edges_and_origin() {
        // B тянем вправо от A — прилипает к правому краю и выравнивается по верху
        let p = snap(&outs(), "B", 1950.0, 30.0);
        assert_eq!(p.get("B").get("x").num(), Some(1920.0));
        assert_eq!(p.get("B").get("y").num(), Some(0.0));
        // слева — A сдвигается, всё начинается с (0,0)
        let p = snap(&outs(), "B", -1000.0, 10.0);
        assert_eq!(p.get("B").get("x").num(), Some(0.0));
        assert_eq!(p.get("A").get("x").num(), Some(900.0));
    }

    #[test]
    fn unique_sorted_modes() {
        let live = Json::parse(r#"{"A":{"modes":[{"width":1920,"height":1080,"refresh_rate":60000},{"width":1920,"height":1080,"refresh_rate":180000,"is_preferred":true},{"width":2560,"height":1440,"refresh_rate":60000},{"width":1920,"height":1080,"refresh_rate":60000}]}}"#).unwrap();
        let m = modes(&live, "A");
        assert_eq!(m.len(), 3);
        assert_eq!(m[0].4, "2560x1440@60.000");
        assert_eq!(m[1].4, "1920x1080@180.000");
        assert!(m[1].3);
    }
}
