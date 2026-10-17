// сеть как в Net.qml: первый поднятый физический интерфейс из /sys/class/net (работает и без NetworkManager)

use std::fs;
use std::path::Path;
use std::time::Duration;

use amane::Service;

use crate::json::Json;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    None,
    Ethernet,
    Wifi,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Iface {
    pub name: String,
    pub physical: bool,
    pub up: bool,
    pub wireless: bool,
}

// как в шелле: физический (есть device), operstate = up; беспроводной — если есть wireless/
pub fn pick(list: &[Iface]) -> (Kind, String) {
    let mut sorted: Vec<&Iface> = list.iter().collect();
    sorted.sort_by(|a, b| a.name.cmp(&b.name));
    for i in sorted {
        if i.physical && i.up {
            return (if i.wireless { Kind::Wifi } else { Kind::Ethernet }, i.name.clone());
        }
    }
    (Kind::None, String::new())
}

fn scan(root: &Path) -> Vec<Iface> {
    let Ok(rd) = fs::read_dir(root) else { return Vec::new() };
    rd.flatten()
        .map(|e| {
            let p = e.path();
            Iface {
                name: e.file_name().to_string_lossy().to_string(),
                physical: p.join("device").exists(),
                up: fs::read_to_string(p.join("operstate")).map(|s| s.trim() == "up").unwrap_or(false),
                wireless: p.join("wireless").is_dir(),
            }
        })
        .collect()
}

// адрес IPv4 из `ip -o -4 addr show dev X`: «2: enp3s0    inet 192.168.1.5/24 brd …»
pub fn parse_ipv4(text: &str) -> String {
    text.split_whitespace()
        .skip_while(|w| *w != "inet")
        .nth(1)
        .map(|a| a.split('/').next().unwrap_or(a).to_string())
        .unwrap_or_default()
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Info {
    pub ipv4: Vec<String>,
    pub ipv6: Vec<String>,
    pub gateway: String,
    pub dns: Vec<String>,
    pub mac: String,
    pub mtu: i64,
    pub vpn: Vec<String>,
}

// разбор `ip -j addr` и `ip -j route show default` для интерфейса
pub fn parse_info(iface: &str, addrs: &Json, routes: &Json, resolv: &str) -> Info {
    let main = addrs.arr().iter().find(|a| a.get("ifname").str() == Some(iface));
    let addr = |fam: &str| -> Vec<String> {
        main.map(|m| {
            m.get("addr_info")
                .arr()
                .iter()
                .filter(|a| a.get("family").str() == Some(fam) && a.get("scope").str() == Some("global"))
                .map(|a| format!("{}/{}", a.get("local").str_or(""), a.get("prefixlen").num_or(0.0)))
                .collect()
        })
        .unwrap_or_default()
    };
    let gateway = routes.arr().iter().find(|r| r.get("dev").str() == Some(iface)).map(|r| r.get("gateway").str_or("")).unwrap_or_default();
    let vpn = addrs
        .arr()
        .iter()
        .filter(|a| a.get("link_type").str() == Some("none") && a.get("ifname").str() != Some("lo") && a.get("flags").arr().iter().any(|f| f.str() == Some("UP")))
        .map(|a| a.get("ifname").str_or(""))
        .collect();
    Info {
        ipv4: addr("inet"),
        ipv6: addr("inet6"),
        gateway,
        dns: resolv.lines().filter_map(|l| l.strip_prefix("nameserver")).map(|v| v.trim().to_string()).filter(|v| !v.is_empty()).collect(),
        mac: main.map(|m| m.get("address").str_or("")).unwrap_or_default(),
        mtu: main.map(|m| m.get("mtu").num_or(0.0) as i64).unwrap_or(0),
        vpn,
    }
}

pub fn format_bytes(b: f64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"];
    let (mut b, mut i) = (b, 0);
    while b >= 1024.0 && i < units.len() - 1 {
        b /= 1024.0;
        i += 1;
    }
    if i == 0 || b >= 100.0 { format!("{b:.0} {}", units[i]) } else { format!("{b:.1} {}", units[i]) }
}

pub fn format_speed(b: f64) -> String {
    format!("{}/s", format_bytes(b))
}

const HISTORY: usize = 60;

pub struct Net {
    pub kind: Kind,
    pub iface: String,
    pub ip: String,
    pub ssid: String,
    pub speed: String,
    pub signal: String,
    pub info: Info,
    tick: u32,
}

// скорость сети — отдельно: меняется каждую секунду, а бару она не нужна
#[derive(Default)]
pub struct NetRate {
    pub rx_speed: f64,
    pub tx_speed: f64,
    pub rx_total: f64,
    pub tx_total: f64,
    pub rx_history: Vec<f64>,
    pub tx_history: Vec<f64>,
    iface: String,
    last: Option<std::time::Instant>,
}

impl Service for NetRate {
    fn new() -> Self {
        NetRate::default()
    }

    fn interval() -> Duration {
        Duration::from_secs(1)
    }

    fn update(&mut self) -> bool {
        let iface = Net::read().iface.clone();
        if iface.is_empty() {
            self.rx_speed = 0.0;
            self.tx_speed = 0.0;
        } else {
            let rx = read_num(format!("/sys/class/net/{iface}/statistics/rx_bytes"));
            let tx = read_num(format!("/sys/class/net/{iface}/statistics/tx_bytes"));
            if let Some(t) = self.last.filter(|_| iface == self.iface) {
                let dt = t.elapsed().as_secs_f64().max(0.001);
                self.rx_speed = ((rx - self.rx_total) / dt).max(0.0);
                self.tx_speed = ((tx - self.tx_total) / dt).max(0.0);
            }
            self.rx_total = rx;
            self.tx_total = tx;
            self.last = Some(std::time::Instant::now());
        }
        self.iface = iface;
        self.rx_history.push(self.rx_speed);
        self.tx_history.push(self.tx_speed);
        if self.rx_history.len() > HISTORY {
            self.rx_history.remove(0);
            self.tx_history.remove(0);
        }
        true
    }
}

fn read_num(p: String) -> f64 {
    fs::read_to_string(p).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0.0)
}

impl Service for Net {
    fn new() -> Self {
        let (kind, iface) = pick(&scan(Path::new("/sys/class/net")));
        Net {
            kind,
            iface,
            ip: String::new(),
            ssid: String::new(),
            speed: String::new(),
            signal: String::new(),
            info: Info::default(),
            tick: 0,
        }
    }

    fn interval() -> Duration {
        Duration::from_secs(1)
    }

    fn update(&mut self) -> bool {
        let (kind, iface) = pick(&scan(Path::new("/sys/class/net")));
        let mut changed = kind != self.kind || iface != self.iface;
        self.tick += 1;
        // подробности — реже (и сразу при смене интерфейса)
        if changed || self.tick % 5 == 1 {
            let q = crate::niri::sh_quote(&iface);
            let addrs = Json::parse(&amane::output("ip -j addr show 2>/dev/null")).unwrap_or(Json::Null);
            let routes = Json::parse(&amane::output("ip -j route show default 2>/dev/null")).unwrap_or(Json::Null);
            let resolv = fs::read_to_string("/etc/resolv.conf").unwrap_or_default();
            let info = parse_info(&iface, &addrs, &routes, &resolv);
            let ip = info.ipv4.first().map(|a| a.split('/').next().unwrap_or("").to_string()).unwrap_or_default();
            let ssid = if kind == Kind::Wifi { amane::output(&format!("iw dev {q} link 2>/dev/null | sed -n 's/.*SSID: //p'")) } else { String::new() };
            let signal = if kind == Kind::Wifi { amane::output(&format!("grep {q} /proc/net/wireless 2>/dev/null | awk '{{print int($3)}}'")) } else { String::new() };
            let speed = fs::read_to_string(format!("/sys/class/net/{iface}/speed")).map(|s| s.trim().to_string()).unwrap_or_default();
            let speed = match speed.parse::<i64>() {
                Ok(v) if v >= 1000 => format!("{} Gb/s", v / 1000),
                Ok(v) if v > 0 => format!("{v} Mb/s"),
                _ => String::new(),
            };
            changed |= ip != self.ip || ssid != self.ssid || speed != self.speed || info != self.info;
            self.ip = ip;
            self.ssid = ssid;
            self.speed = speed;
            self.signal = signal;
            self.info = info;
        }
        self.kind = kind;
        self.iface = iface;
        changed
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn i(name: &str, physical: bool, up: bool, wireless: bool) -> Iface {
        Iface { name: name.into(), physical, up, wireless }
    }

    #[test]
    fn picks_first_up_physical() {
        assert_eq!(pick(&[]), (Kind::None, String::new()));
        // lo и docker0 — не физические
        let l = vec![i("lo", false, true, false), i("docker0", false, true, false), i("wlan0", true, true, true), i("enp3s0", true, true, false)];
        assert_eq!(pick(&l), (Kind::Ethernet, "enp3s0".into()));
        let l = vec![i("enp3s0", true, false, false), i("wlan0", true, true, true)];
        assert_eq!(pick(&l), (Kind::Wifi, "wlan0".into()));
        let l = vec![i("enp3s0", true, false, false)];
        assert_eq!(pick(&l).0, Kind::None);
    }

    #[test]
    fn info_from_ip_json() {
        let addrs = Json::parse(r#"[{"ifname":"lo","link_type":"loopback","flags":["UP"]},
            {"ifname":"enp4s0","address":"aa:bb:cc:dd:ee:ff","mtu":1500,"link_type":"ether","flags":["UP"],"addr_info":[{"family":"inet","local":"192.168.31.113","prefixlen":24,"scope":"global"},{"family":"inet6","local":"fe80::1","prefixlen":64,"scope":"link"}]},
            {"ifname":"wg0","link_type":"none","flags":["POINTOPOINT","UP"]}]"#).unwrap();
        let routes = Json::parse(r#"[{"dst":"default","gateway":"192.168.31.1","dev":"enp4s0"}]"#).unwrap();
        let i = parse_info("enp4s0", &addrs, &routes, "# x\nnameserver 127.0.0.53\n");
        assert_eq!(i.ipv4, vec!["192.168.31.113/24"]);
        assert!(i.ipv6.is_empty());
        assert_eq!(i.gateway, "192.168.31.1");
        assert_eq!(i.dns, vec!["127.0.0.53"]);
        assert_eq!(i.vpn, vec!["wg0"]);
        assert_eq!((i.mac.as_str(), i.mtu), ("aa:bb:cc:dd:ee:ff", 1500));
        assert_eq!(parse_ipv4(""), "");
    }

    #[test]
    fn byte_formats() {
        assert_eq!(format_bytes(512.0), "512 B");
        assert_eq!(format_bytes(1536.0), "1.5 KB");
        assert_eq!(format_speed(200.0 * 1024.0), "200 KB/s");
    }

    #[test]
    fn reads_real_sysfs_without_panicking() {
        let _ = pick(&scan(Path::new("/sys/class/net")));
        assert!(scan(Path::new("/nonexistent")).is_empty());
    }
}
