pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// состояние сети: тип подключения, скорость, адреса
Singleton {
    id: root

    property string type: "none"  // ethernet | wifi | none
    property string iface: ""
    property real rxSpeed: 0      // байт/с
    property real txSpeed: 0
    property real rxTotal: 0      // байт с момента загрузки
    property real txTotal: 0
    property var rxHistory: []
    property var txHistory: []
    readonly property int historySize: 60

    // подробности, обновляются через refreshInfo()
    property var info: ({})

    property real lastTime: 0

    function formatSpeed(b) {
        return formatBytes(b) + "/s";
    }

    function formatBytes(b) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (b >= 1024 && i < units.length - 1) {
            b /= 1024;
            i++;
        }
        return `${b.toFixed(i === 0 || b >= 100 ? 0 : 1)} ${units[i]}`;
    }

    function push(arr, v) {
        const a = arr.concat([v]);
        return a.length > historySize ? a.slice(a.length - historySize) : a;
    }

    function sample(line) {
        const [t, dev, rx, tx] = line.trim().split(" ");
        const now = Date.now();
        if (t === "none" || !dev) {
            type = "none";
            iface = "";
            rxSpeed = txSpeed = 0;
        } else {
            const r = Number(rx), w = Number(tx);
            if (dev === iface && lastTime > 0) {
                const dt = (now - lastTime) / 1000;
                rxSpeed = Math.max(0, (r - rxTotal) / dt);
                txSpeed = Math.max(0, (w - txTotal) / dt);
            }
            type = t;
            iface = dev;
            rxTotal = r;
            txTotal = w;
        }
        lastTime = now;
        rxHistory = push(rxHistory, rxSpeed);
        txHistory = push(txHistory, txSpeed);
    }

    function refreshInfo() {
        if (iface) infoProc.running = true;
    }

    // раз в секунду: первый физический интерфейс в состоянии up и его счётчики
    Process {
        running: true
        command: ["sh", "-c", `
            while :; do
                found=
                for d in /sys/class/net/*; do
                    [ -e "$d/device" ] || continue
                    [ "$(cat "$d/operstate")" = up ] || continue
                    t=ethernet; [ -d "$d/wireless" ] && t=wifi
                    echo "$t \${d##*/} $(cat "$d/statistics/rx_bytes") $(cat "$d/statistics/tx_bytes")"
                    found=1; break
                done
                [ -n "$found" ] || echo none
                sleep 1
            done`]
        stdout: SplitParser {
            onRead: line => root.sample(line)
        }
    }

    Process {
        id: infoProc
        command: ["sh", "-c", `
            d="$1"
            echo "@addr"; ip -j addr show
            echo "@route"; ip -j route show default
            echo "@dns"; grep '^nameserver' /etc/resolv.conf | awk '{print $2}'
            echo "@speed"; cat "/sys/class/net/$d/speed" 2>/dev/null
            echo "@wifi"; grep "$d" /proc/net/wireless 2>/dev/null | awk '{print int($3)}'
            echo "@ssid"; iw dev "$d" link 2>/dev/null | sed -n 's/.*SSID: //p'
        `, "sh", root.iface]
        stdout: StdioCollector {
            onStreamFinished: {
                const sections = {};
                let cur = null;
                for (const line of text.split("\n")) {
                    if (line.startsWith("@")) {
                        cur = line.slice(1);
                        sections[cur] = [];
                    } else if (cur && line.trim()) {
                        sections[cur].push(line.trim());
                    }
                }
                const parse = s => {
                    try { return JSON.parse((sections[s] ?? []).join("")); } catch (e) { return []; }
                };
                const addrs = parse("addr");
                const routes = parse("route");
                const main = addrs.find(a => a.ifname === root.iface) ?? {};
                const addr = fam => (main.addr_info ?? [])
                    .filter(a => a.family === fam && a.scope === "global")
                    .map(a => `${a.local}/${a.prefixlen}`);
                const route = routes.find(r => r.dev === root.iface) ?? {};
                const vpns = addrs.filter(a => a.link_type === "none" && a.ifname !== "lo"
                    && (a.flags ?? []).includes("UP"));
                const speed = Number((sections.speed ?? [])[0]);

                root.info = {
                    ipv4: addr("inet"),
                    ipv6: addr("inet6"),
                    gateway: route.gateway ?? "",
                    dns: sections.dns ?? [],
                    mac: main.address ?? "",
                    mtu: main.mtu ?? 0,
                    linkSpeed: speed > 0 ? (speed >= 1000 ? `${speed / 1000} Gb/s` : `${speed} Mb/s`) : "",
                    signal: (sections.wifi ?? [])[0] ?? "",
                    ssid: (sections.ssid ?? [])[0] ?? "",
                    vpn: vpns.map(v => v.ifname),
                };
            }
        }
    }
}
