// PipeWire: устройства и приложения со звуком, громкость каждого (микшер), из `pw-dump -m`;
// управление — wpctl. Громкость — как у wpctl/pavucontrol: кубический корень из channelVolumes.

use std::collections::BTreeMap;
use std::time::Duration;

use amane::Service;

use crate::json::Json;

#[derive(Debug, Clone, PartialEq)]
pub struct Node {
    pub id: i64,
    pub name: String,
    pub desc: String,
    pub class: String,
    pub volume: f64,
    pub muted: bool,
    pub app: String,
    pub icon: String,
    pub serial: String,
}

impl Node {
    pub fn is_sink(&self) -> bool {
        self.class == "Audio/Sink"
    }
    pub fn is_source(&self) -> bool {
        self.class == "Audio/Source"
    }
    pub fn is_out_stream(&self) -> bool {
        self.class == "Stream/Output/Audio"
    }
    pub fn is_in_stream(&self) -> bool {
        self.class == "Stream/Input/Audio"
    }
    // свои индикаторы уровня не показываем
    pub fn is_meter(&self) -> bool {
        self.app == "qs-meter" || self.name.starts_with("qs-meter")
    }
    pub fn title(&self) -> String {
        if !self.app.is_empty() {
            self.app.clone()
        } else if !self.desc.is_empty() {
            self.desc.clone()
        } else {
            self.name.clone()
        }
    }
}

#[derive(Default, Clone, PartialEq)]
pub struct Graph {
    pub objects: BTreeMap<i64, Json>,
    pub meta: BTreeMap<String, Json>,
}

impl Graph {
    // одна пачка из pw-dump: полные объекты, {"id", "info": null} — удалён
    pub fn apply(&mut self, batch: &Json) {
        for o in batch.arr() {
            let Some(id) = o.get("id").num().map(|n| n as i64) else { continue };
            if o.get("type").str() == Some("PipeWire:Interface:Metadata") {
                for m in o.get("metadata").arr() {
                    let key = m.get("key").str_or("");
                    if m.get("value").is_null() {
                        self.meta.remove(&key);
                    } else {
                        self.meta.insert(key, m.get("value").clone());
                    }
                }
                continue;
            }
            let info = o.get("info");
            if info.is_null() && o.get("type").is_null() {
                self.objects.remove(&id);
            } else if !info.is_null() {
                self.objects.insert(id, o.clone());
            }
        }
    }

    pub fn nodes(&self) -> Vec<Node> {
        self.objects
            .iter()
            .filter(|(_, o)| o.get("type").str() == Some("PipeWire:Interface:Node"))
            .filter_map(|(id, o)| {
                let p = o.get("info").get("props");
                let class = p.get("media.class").str_or("");
                if !class.contains("Audio") {
                    return None;
                }
                let props = o.get("info").get("params").get("Props");
                let vol_entry = props.arr().iter().find(|x| !x.get("channelVolumes").is_null());
                let (volume, muted) = match vol_entry {
                    Some(v) => {
                        let ch = v.get("channelVolumes").arr();
                        let avg = if ch.is_empty() { 0.0 } else { ch.iter().map(|c| c.num_or(0.0)).sum::<f64>() / ch.len() as f64 };
                        (avg.cbrt(), v.get("mute").bool_or(false))
                    }
                    None => (0.0, false),
                };
                let num_or_str = |j: &Json| match j {
                    Json::Num(n) => format!("{}", *n as i64),
                    Json::Str(s) => s.clone(),
                    _ => String::new(),
                };
                Some(Node {
                    id: *id,
                    name: p.get("node.name").str_or(""),
                    desc: p.get("node.description").str().or(p.get("node.nick").str()).unwrap_or("").to_string(),
                    class,
                    volume,
                    muted,
                    app: p.get("application.name").str_or(""),
                    icon: p.get("application.icon-name").str().or(p.get("application.process.binary").str()).unwrap_or("").to_string(),
                    serial: num_or_str(p.get("object.serial")),
                })
            })
            .collect()
    }

    pub fn default_name(&self, input: bool) -> String {
        self.meta.get(if input { "default.audio.source" } else { "default.audio.sink" }).map(|v| v.get("name").str_or("")).unwrap_or_default()
    }
}

#[derive(Default)]
pub struct Pw {
    pub g: Graph,
}

impl Pw {
    pub fn nodes(&self) -> Vec<Node> {
        self.g.nodes()
    }
    pub fn devices(&self, input: bool) -> Vec<Node> {
        self.nodes().into_iter().filter(|n| if input { n.is_source() } else { n.is_sink() }).collect()
    }
    pub fn streams(&self, input: bool) -> Vec<Node> {
        self.nodes().into_iter().filter(|n| if input { n.is_in_stream() } else { n.is_out_stream() }).filter(|n| !n.is_meter()).collect()
    }
    pub fn current(&self, input: bool) -> Option<Node> {
        let d = self.g.default_name(input);
        self.nodes().into_iter().find(|n| n.name == d)
    }
}

pub fn set_volume(id: i64, v: f64) {
    amane::spawn(&format!("wpctl set-volume {id} {:.3}", v.clamp(0.0, 1.5)));
}

pub fn set_mute(id: i64, muted: bool) {
    amane::spawn(&format!("wpctl set-mute {id} {}", if muted { 1 } else { 0 }));
}

pub fn set_default(id: i64) {
    amane::spawn(&format!("wpctl set-default {id}"));
}

impl Service for Pw {
    fn new() -> Self {
        let mut g = Graph::default();
        if let Some(j) = Json::parse(&amane::output("pw-dump 2>/dev/null")) {
            g.apply(&j);
        }
        Pw { g }
    }

    fn listen() {
        loop {
            let mut buf = String::new();
            for line in amane::lines("pw-dump -m 2>/dev/null") {
                buf.push_str(&line);
                buf.push('\n');
                // пачка — массив; заканчивается «]» в начале строки
                if line == "]" {
                    if let Some(j) = Json::parse(&buf) {
                        let mut g = Pw::read().g.clone();
                        g.apply(&j);
                        if g != Pw::read().g {
                            Pw::write().g = g;
                        }
                    }
                    buf.clear();
                }
            }
            std::thread::sleep(Duration::from_secs(2));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn node(id: i64, class: &str, name: &str, vol: f64, extra: &str) -> String {
        format!(r#"{{"id":{id},"type":"PipeWire:Interface:Node","info":{{"props":{{"media.class":"{class}","node.name":"{name}","node.description":"{name} desc","object.serial":{id}{extra}}},"params":{{"Props":[{{"channelVolumes":[{vol},{vol}],"mute":false}}]}}}}}}"#)
    }

    #[test]
    fn graph_nodes_defaults_and_removal() {
        let mut g = Graph::default();
        let batch = format!(
            "[{},{},{},{},{}]",
            node(54, "Audio/Sink", "hdmi", 0.064, ""),
            node(57, "Audio/Sink", "analog", 1.0, ""),
            node(56, "Audio/Source", "mic", 1.0, ""),
            node(83, "Stream/Output/Audio", "mpv", 1.0, r#","application.name":"mpv""#),
            r#"{"id":40,"type":"PipeWire:Interface:Metadata","metadata":[{"subject":0,"key":"default.audio.sink","value":{"name":"analog"}},{"subject":0,"key":"default.audio.source","value":{"name":"mic"}}]}"#
        );
        g.apply(&Json::parse(&batch).unwrap());
        let pw = Pw { g: g.clone() };
        assert_eq!(pw.devices(false).len(), 2);
        assert_eq!(pw.current(false).map(|n| n.id), Some(57));
        assert_eq!(pw.current(true).map(|n| n.id), Some(56));
        let hdmi = pw.devices(false).into_iter().find(|n| n.id == 54).unwrap();
        assert!((hdmi.volume - 0.4).abs() < 1e-6);
        assert_eq!(pw.streams(false)[0].title(), "mpv");
        // удалили mpv
        g.apply(&Json::parse(r#"[{"id":83,"info":null}]"#).unwrap());
        assert!(Pw { g }.streams(false).is_empty());
    }

    #[test]
    fn meters_are_hidden() {
        let mut g = Graph::default();
        g.apply(&Json::parse(&format!("[{}]", node(90, "Stream/Input/Audio", "qs-meter", 1.0, r#","application.name":"qs-meter""#))).unwrap());
        assert!(Pw { g }.streams(true).is_empty());
    }
}
