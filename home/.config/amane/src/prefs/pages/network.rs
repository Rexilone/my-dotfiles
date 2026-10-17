// Сеть: подключение, DNS (systemd-resolved), файрвол ufw (NetworkPage.qml)

use amane::{Center, Color, Column, End, Padding, Rectangle, Row, Service, Start, Weight, children};

use super::super::Prefs;
use super::super::w::{self, Btn, Card, W, bx};
use super::Out;
use crate::cmd;
use crate::look::Tk;
use crate::net::{self, Kind, Net, NetRate};
use crate::niri::sh_quote;
use crate::ui::{self, ic};

const PRESETS: [(&str, &str, &[&str]); 6] = [
    ("auto", "Automatic (from network / VPN)", &[]),
    ("cloudflare", "Cloudflare — 1.1.1.1", &["1.1.1.1#cloudflare-dns.com", "1.0.0.1#cloudflare-dns.com"]),
    ("google", "Google — 8.8.8.8", &["8.8.8.8#dns.google", "8.8.4.4#dns.google"]),
    ("quad9", "Quad9 — 9.9.9.9", &["9.9.9.9#dns.quad9.net", "149.112.112.112#dns.quad9.net"]),
    ("adguard", "AdGuard (blocks ads) — 94.140.14.14", &["94.140.14.14#dns.adguard-dns.com", "94.140.15.15#dns.adguard-dns.com"]),
    ("custom", "Custom…", &[]),
];

const DNS_READ: &str = "cat /etc/systemd/resolved.conf.d/90-quickshell.conf 2>/dev/null; echo '@@'; resolvectl dns 2>/dev/null";

pub struct Dns {
    pub preset: String,
    pub custom: Vec<String>,
    pub tls: bool,
    pub active: String,
}

pub fn parse_dns(text: &str) -> Dns {
    let (conf, active) = text.split_once("@@").unwrap_or((text, ""));
    let preset = conf.split("preset: ").nth(1).map(|r| r.chars().take_while(|c| c.is_alphanumeric()).collect::<String>()).filter(|p| !p.is_empty()).unwrap_or_else(|| "auto".into());
    let custom = conf.lines().find_map(|l| l.strip_prefix("DNS=")).map(|v| v.split_whitespace().map(String::from).collect()).unwrap_or_default();
    Dns {
        preset,
        custom,
        tls: conf.contains("DNSOverTLS=yes"),
        active: active.lines().map(str::trim).filter(|l| l.split_once(':').is_some_and(|(_, v)| !v.trim().is_empty())).collect::<Vec<_>>().join("\n"),
    }
}

// содержимое 90-quickshell.conf (None — убрать файл, автоматически)
pub fn dns_conf(preset: &str, custom: &[String], tls: bool) -> Option<String> {
    let servers: Vec<String> = if preset == "custom" {
        custom.to_vec()
    } else {
        PRESETS.iter().find(|p| p.0 == preset).map(|p| p.2.iter().map(|s| s.to_string()).collect()).unwrap_or_default()
    };
    if preset == "auto" || servers.is_empty() {
        return None;
    }
    Some(format!("# managed by Quickshell settings (preset: {preset})\n[Resolve]\nDNS={}\nDomains=~.\nDNSOverTLS={}\n", servers.join(" "), if tls { "yes" } else { "no" }))
}

fn apply_dns(preset: String, custom: Vec<String>, tls: bool) {
    Prefs::set("net:busy", "1");
    std::thread::spawn(move || {
        let cmd_line = match dns_conf(&preset, &custom, tls) {
            None => "pkexec sh -c 'rm -f /etc/systemd/resolved.conf.d/90-quickshell.conf && systemctl restart systemd-resolved'".to_string(),
            Some(conf) => format!(
                "pkexec sh -c 'mkdir -p /etc/systemd/resolved.conf.d && printf \"%s\" \"$1\" > /etc/systemd/resolved.conf.d/90-quickshell.conf && systemctl restart systemd-resolved' sh {}",
                sh_quote(&conf)
            ),
        };
        amane::output(&cmd_line);
        Prefs::set("net:busy", "");
        cmd::refresh("dns", DNS_READ);
    });
}

#[derive(Debug, Clone, PartialEq)]
pub struct Rule {
    pub num: String,
    pub to: String,
    pub action: String,
    pub from: String,
}

// строки `ufw status numbered`: «[ 1] 22/tcp   ALLOW IN    Anywhere»
pub fn parse_rules(text: &str) -> Option<Vec<Rule>> {
    if !text.contains("Status:") {
        return None;
    }
    let mut out = Vec::new();
    for line in text.lines() {
        let Some(rest) = line.trim_start().strip_prefix('[') else { continue };
        let Some((num, body)) = rest.split_once(']') else { continue };
        let body = body.trim();
        let Some(pos) = ["ALLOW", "DENY", "REJECT", "LIMIT"].iter().filter_map(|a| body.find(&format!("  {a}")).map(|p| (p, *a))).min() else { continue };
        let to = body[..pos.0].trim().to_string();
        let after = body[pos.0..].trim_start();
        let mut parts = after.splitn(2, char::is_whitespace);
        let act = parts.next().unwrap_or("").to_string();
        let rest = parts.next().unwrap_or("").trim_start();
        let (dir, from) = match rest.split_once(char::is_whitespace) {
            Some((d, f)) if ["IN", "OUT", "FWD"].contains(&d) => (format!(" {d}"), f.trim().to_string()),
            _ => (String::new(), rest.trim().to_string()),
        };
        out.push(Rule { num: num.trim().to_string(), to, action: format!("{act}{dir}"), from });
    }
    Some(out)
}

fn ufw(script: String) {
    Prefs::set("net:busy", "1");
    std::thread::spawn(move || {
        let out = amane::output(&format!("pkexec sh -c {} 2>/dev/null", sh_quote(&format!("{script}; ufw status numbered"))));
        if let Some(r) = parse_rules(&out) {
            let enc: Vec<String> = r.iter().map(|x| format!("{}\t{}\t{}\t{}", x.num, x.to, x.action, x.from)).collect();
            Prefs::set("net:rules", &enc.join("\n"));
            Prefs::set("net:rules-loaded", "1");
        }
        Prefs::set("net:busy", "");
        cmd::refresh("ufwconf", "cat /etc/ufw/ufw.conf 2>/dev/null");
    });
}

pub fn valid_dns(s: &str) -> bool {
    let (addr, name) = s.split_once('#').unwrap_or((s, ""));
    let v4 = addr.split('.').count() == 4 && addr.split('.').all(|p| !p.is_empty() && p.len() <= 3 && p.chars().all(|c| c.is_ascii_digit()));
    let v6 = addr.len() >= 2 && addr.contains(':') && addr.chars().all(|c| c.is_ascii_hexdigit() || c == ':');
    (v4 || v6) && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-') && (s.contains('#') <= !name.is_empty())
}

pub fn valid_port(s: &str) -> bool {
    let (ports, proto) = s.split_once('/').unwrap_or((s, ""));
    let ok_num = |p: &str| !p.is_empty() && p.len() <= 5 && p.chars().all(|c| c.is_ascii_digit());
    let ok_ports = match ports.split_once(':') {
        Some((a, b)) => ok_num(a) && ok_num(b),
        None => ok_num(ports),
    };
    ok_ports && (proto.is_empty() && !s.contains('/') || proto == "tcp" || proto == "udp")
}

pub fn page(t: &Tk, w: f32) -> Out {
    let n = Net::read();
    let (kind, iface, info, link) = (n.kind, n.iface.clone(), n.info.clone(), n.speed.clone());
    drop(n);
    let rate = NetRate::read();
    let (rx, tx) = (rate.rx_speed, rate.tx_speed);
    drop(rate);
    let busy = Prefs::flag("net:busy");
    let mut items: Vec<W> = vec![bx(w::section(t, "Connection", w))];
    let title = match kind {
        Kind::None => t.t("Disconnected"),
        Kind::Wifi => format!("Wi-Fi · {iface}"),
        Kind::Ethernet => format!("Ethernet · {iface}"),
    };
    let desc = if kind == Kind::None {
        t.t("No active connection")
    } else {
        format!("{}   ·   {}", if info.ipv4.is_empty() { t.t("no IPv4") } else { info.ipv4.join(", ") }, link)
    };
    let speeds = Column::new(children![
        Rectangle::new().width(130.0).height(t.fs + 2.0).align_child(End, Center).child(ui::text(t, format!("{} {}", ui::glyph(0xF0045), net::format_speed(rx)), t.p.fg).size(t.fs - 1.0)),
        Rectangle::new().width(130.0).height(t.fs + 2.0).align_child(End, Center).child(ui::text(t, format!("{} {}", ui::glyph(0xF005D), net::format_speed(tx)), t.p.dim).size(t.fs - 1.0))
    ])
    .gap(2.0);
    let icon = match kind {
        Kind::Wifi => ic::WIFI,
        Kind::Ethernet => ic::ETHERNET,
        Kind::None => ic::OFFLINE,
    };
    items.push(bx(Card::new(icon, &title, &desc).ctrl(speeds).build(t, w)));
    let gw = format!(
        "{} {}   ·   DNS {}",
        t.t("Gateway"),
        if info.gateway.is_empty() { "—".into() } else { info.gateway.clone() },
        if info.dns.is_empty() { "—".into() } else { info.dns.join(", ") }
    );
    items.push(bx(Card::new(0xF0A5F, "Gateway & DNS", &gw).build(t, w)));
    let vpn = if info.vpn.is_empty() { t.t("No VPN interfaces up") } else { format!("{}: {}", t.t("Active"), info.vpn.join(", ")) };
    items.push(bx(Card::new(0xF0582, "VPN", &vpn).build(t, w)));
    let has_wifi = !cmd::get("haswifi", "ls -d /sys/class/net/*/wireless 2>/dev/null | head -n1").unwrap_or_default().is_empty();
    items.push(bx(Card::new(ic::WIFI, "Wi-Fi", if has_wifi { "Wi-Fi adapter found — install iwd or NetworkManager to manage networks" } else { "No Wi-Fi adapter detected on this computer" }).build(t, w)));

    // ── DNS
    items.push(bx(w::section(t, "DNS", w)));
    let dns = parse_dns(&cmd::get("dns", DNS_READ).unwrap_or_default());
    let sel = { let s = Prefs::get("net:dns-preset"); if s.is_empty() { dns.preset.clone() } else { s } };
    let opts: Vec<(String, String)> = PRESETS.iter().map(|p| (p.0.to_string(), p.1.to_string())).collect();
    let tls = dns.tls;
    items.push(bx(Card::new(0xF0A5F, "DNS server", "Used for all connections. Changing it needs your password.")
        .ctrl(w::dropdown(t, "dns", &opts, &sel, 280.0, move |v| {
            Prefs::set("net:dns-preset", &v);
            if v != "custom" {
                apply_dns(v, Vec::new(), tls);
            }
        }))
        .build(t, w)));
    if sel == "custom" {
        let stored = Prefs::get("net:dns-custom");
        let custom: Vec<String> = if stored.is_empty() { dns.custom.clone() } else { stored.split(' ').filter(|s| !s.is_empty()).map(String::from).collect() };
        let mut chips: Vec<W> = Vec::new();
        for (i, c) in custom.iter().enumerate() {
            let id = format!("dnsrm:{i}");
            let hv = w::hov(&id);
            let lbl = ui::text(t, c.clone(), t.p.fg).size(t.fs - 2.0);
            let lw = crate::bar::width_of(&lbl);
            let cl = custom.clone();
            let x = w::clickable(Rectangle::new().width(14.0).height(14.0).align_child(Center, Center).child(ui::icon(t, ic::CLOSE, t.fs - 2.0, if hv { t.p.urgent } else { t.p.dim })), &id, w::act(move || {
                let mut v = cl.clone();
                v.remove(i);
                Prefs::set("net:dns-custom", &v.join(" "));
            }));
            chips.push(bx(Rectangle::new().width(lw + 20.0 + 22.0).height(30.0).radius(8.0).fill(t.p.surface_hi).align_child(Center, Center).child(Row::new(children![lbl, x]).gap(8.0).align(Center))));
        }
        let iw = w - 36.0;
        let mut col: Vec<W> = vec![bx(w::tx(t, "Custom servers", t.fs, t.p.fg))];
        if !chips.is_empty() {
            col.push(bx(Row::new(chips).gap(6.0)));
        }
        let c1 = custom.clone();
        let c2 = custom.clone();
        let input = w::field(t, "dns-input", iw - 200.0, "e.g. 1.1.1.1 or 2606:4700::1111", 0, move |v| {
            if valid_dns(&v) {
                let mut l = c1.clone();
                l.push(v);
                Prefs::set("net:dns-custom", &l.join(" "));
                w::set_field("dns-input", "");
            }
        });
        let typed = w::field_text("dns-input");
        let c3 = custom.clone();
        col.push(bx(Row::new(children![
            input,
            Btn::new("Add").enabled(valid_dns(&typed)).build(t, "dns-add", move || {
                let v = w::field_text("dns-input");
                if valid_dns(&v) {
                    let mut l = c3.clone();
                    l.push(v);
                    Prefs::set("net:dns-custom", &l.join(" "));
                    w::set_field("dns-input", "");
                }
            }),
            Btn::new("Apply").primary().enabled(!custom.is_empty() && !busy).build(t, "dns-apply", move || apply_dns("custom".into(), c2.clone(), tls))
        ])
        .gap(8.0)
        .align(Center)));
        let cc = Column::new(col).gap(8.0);
        let (_, chh) = w::wh(&cc);
        items.push(bx(Rectangle::new().width(w).height(chh + 28.0).radius(10.0).fill(t.p.surface).padding(Padding { top: 14.0, right: 18.0, bottom: 14.0, left: 18.0 }).child(cc)));
    }
    if sel != "auto" {
        let (p2, cu) = (sel.clone(), dns.custom.clone());
        items.push(bx(Card::new(ic::LOCK, "Encrypted DNS (DNS over TLS)", "Hides your DNS queries from the provider")
            .ctrl(w::switch(t, "dns-tls", tls, move |v| {
                if !Prefs::flag("net:busy") {
                    apply_dns(p2.clone(), cu.clone(), v)
                }
            }))
            .build(t, w)));
    }
    items.push(bx(Card::new(0xF02FC, "In use now", if dns.active.is_empty() { "—" } else { &dns.active }).build(t, w)));

    // ── файрвол
    items.push(bx(w::section(t, "Firewall (ufw)", w)));
    let ufw_on = cmd::get("ufwconf", "cat /etc/ufw/ufw.conf 2>/dev/null").unwrap_or_default().lines().any(|l| l.trim() == "ENABLED=yes");
    items.push(bx(Card::new(0xF0582, "Firewall", if ufw_on { "Active — incoming connections are filtered" } else { "Disabled" })
        .ctrl(w::switch(t, "ufw", ufw_on, |v| {
            if !Prefs::flag("net:busy") {
                ufw(if v { "ufw --force enable".into() } else { "ufw disable".into() })
            }
        }))
        .build(t, w)));
    if !Prefs::flag("net:rules-loaded") {
        items.push(bx(Card::new(0xF0CB6, "Rules", "Viewing rules needs your password").ctrl(Btn::new(if busy { "…" } else { "Show rules" }).build(t, "ufw-show", || ufw("true".into()))).build(t, w)));
    } else {
        let rules: Vec<Rule> = Prefs::get("net:rules")
            .lines()
            .filter_map(|l| {
                let p: Vec<&str> = l.split('\t').collect();
                (p.len() == 4).then(|| Rule { num: p[0].into(), to: p[1].into(), action: p[2].into(), from: p[3].into() })
            })
            .collect();
        let iw = w - 36.0;
        let mut rows: Vec<W> = Vec::new();
        if rules.is_empty() {
            rows.push(bx(w::tx(t, "No rules", t.fs - 1.0, t.p.dim)));
        }
        for r in rules {
            let deny = r.action.contains("DENY") || r.action.contains("REJECT");
            let num = r.num.clone();
            rows.push(bx(Row::new(children![
                Rectangle::new().width(40.0).height(28.0).align_child(Start, Center).child(ui::text(t, format!("#{}", r.num), t.p.faint).size(t.fs - 2.0)),
                w::line(t, &r.to, t.fs - 1.0, t.p.fg, 170.0, false),
                Rectangle::new().width(90.0).height(28.0).align_child(Start, Center).child(ui::text(t, r.action.clone(), if deny { t.p.urgent } else { t.p.accent }).size(t.fs - 2.0).weight(Weight::Bold)),
                w::line(t, &r.from, t.fs - 2.0, t.p.dim, (iw - 40.0 - 170.0 - 90.0 - 50.0 - 48.0).max(40.0), false),
                Btn::new("").icon(ic::TRASH).danger().build(t, &format!("ufwdel:{num}"), move || ufw(format!("ufw --force delete {}", sh_quote(&num))))
            ])
            .gap(12.0)
            .align(Center)));
        }
        let rc = Column::new(rows).gap(4.0);
        let (_, rh) = w::wh(&rc);
        items.push(bx(Rectangle::new().width(w).height(rh + 24.0).radius(10.0).fill(t.p.surface).padding(Padding { top: 12.0, right: 18.0, bottom: 12.0, left: 18.0 }).child(rc)));
    }
    let action = { let a = Prefs::get("net:rule-action"); if a.is_empty() { "allow".to_string() } else { a } };
    let port = w::field_text("ufw-port");
    let a2 = action.clone();
    let add = Row::new(children![
        w::field(t, "ufw-port", 150.0, "port", 0, |_| {}),
        w::choice(t, "rule-action", &[("allow", "Allow"), ("deny", "Deny")], &action, |v| Prefs::set("net:rule-action", &v)),
        Btn::new("Add").primary().enabled(valid_port(&port) && !busy).build(t, "ufw-add", move || {
            let p = w::field_text("ufw-port");
            if valid_port(&p) {
                ufw(format!("ufw {} {}", sh_quote(&a2), sh_quote(&p)));
                w::set_field("ufw-port", "");
            }
        })
    ])
    .gap(8.0)
    .align(Center);
    items.push(bx(Card::new(0, "Add rule", "Port or range with optional protocol: 22, 8080/tcp, 6000:6010/udp").ctrl(add).build(t, w)));
    let _ = Color::TRANSPARENT;
    Out { crumb: String::new(), subtitle: "Connection status and firewall".into(), items }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dns_state_and_conf() {
        let d = parse_dns("# managed by Quickshell settings (preset: quad9)\n[Resolve]\nDNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net\nDNSOverTLS=yes\n@@Global: 9.9.9.9\nLink 2 (enp4s0): \n");
        assert_eq!(d.preset, "quad9");
        assert!(d.tls);
        assert_eq!(d.custom.len(), 2);
        assert_eq!(d.active, "Global: 9.9.9.9");
        assert_eq!(parse_dns("@@").preset, "auto");
        assert!(dns_conf("auto", &[], true).is_none());
        let c = dns_conf("cloudflare", &[], false).unwrap();
        assert!(c.contains("DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com\n") && c.contains("DNSOverTLS=no"));
        assert!(dns_conf("custom", &[], false).is_none());
    }

    #[test]
    fn ufw_rules() {
        let out = "Status: active\n\n     To                         Action      From\n     --                         ------      ----\n[ 1] 22/tcp                     ALLOW IN    Anywhere\n[ 2] 47821/udp                  DENY IN     192.168.0.0/24          # Rexlink\n[ 3] 8080                       LIMIT       Anywhere (v6)\n";
        let r = parse_rules(out).unwrap();
        assert_eq!(r.len(), 3);
        assert_eq!(r[0], Rule { num: "1".into(), to: "22/tcp".into(), action: "ALLOW IN".into(), from: "Anywhere".into() });
        assert_eq!(r[1].action, "DENY IN");
        assert!(r[1].from.starts_with("192.168.0.0/24"));
        assert_eq!(r[2].action, "LIMIT");
        assert!(parse_rules("Ошибка").is_none());
    }

    #[test]
    fn validators() {
        assert!(valid_dns("1.1.1.1"));
        assert!(valid_dns("2606:4700::1111"));
        assert!(valid_dns("9.9.9.9#dns.quad9.net"));
        assert!(!valid_dns("1.1.1"));
        assert!(!valid_dns("example.com"));
        assert!(!valid_dns("1.1.1.1#"));
        assert!(valid_port("22"));
        assert!(valid_port("8080/tcp"));
        assert!(valid_port("6000:6010/udp"));
        assert!(!valid_port("22/"));
        assert!(!valid_port("abc"));
        assert!(!valid_port("123456"));
    }
}
