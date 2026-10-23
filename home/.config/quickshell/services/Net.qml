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

    // скорость считается, только пока её показывают (меню сети, центр управления, Настройки → Сеть)
    property var consumers: ({})
    readonly property bool speedActive: Object.keys(consumers).length > 0
    function need(id, on) {
        const c = Object.assign({}, consumers);
        if (on) c[id] = true;
        else delete c[id];
        consumers = c;
    }
    onSpeedActiveChanged: if (!speedActive) { lastTime = 0; rxSpeed = txSpeed = 0; }

    // раз в секунду — счётчики интерфейса прямо из /sys (без запуска процессов);
    // какой интерфейс «up», ищется по событиям ip monitor (и раз в 30 с на всякий случай)
    property string cand: ""          // найденный интерфейс
    property string candType: "none"
    FileView { id: rxFile; path: root.cand ? `/sys/class/net/${root.cand}/statistics/rx_bytes` : ""; blockLoading: true; printErrors: false }
    FileView { id: txFile; path: root.cand ? `/sys/class/net/${root.cand}/statistics/tx_bytes` : ""; blockLoading: true; printErrors: false }
    Timer {
        running: root.speedActive
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!root.cand) { root.sample("none"); return; }
            rxFile.reload();
            txFile.reload();
            const rx = rxFile.text().trim(), tx = txFile.text().trim();
            if (!rx) { discover.running = true; return; }
            root.sample(`${root.candType} ${root.cand} ${rx} ${tx}`);
        }
    }
    Process {
        running: true
        // setpriv --pdeathsig: умирает вместе с шеллом (иначе после перезапуска/падения шелла остаётся висеть)
        command: ["setpriv", "--pdeathsig", "TERM", "ip", "-o", "monitor", "link", "address"]
        stdout: SplitParser { onRead: rediscover.restart() }
    }
    Timer {
        id: rediscover
        interval: 500
        onTriggered: discover.running = true
    }
    Timer {
        running: true
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: discover.running = true
    }
    Process {
        id: discover
        command: ["sh", "-c", `
            for d in /sys/class/net/*; do
                [ -e "$d/device" ] || continue
                [ "$(cat "$d/operstate")" = up ] || continue
                t=ethernet; [ -d "$d/wireless" ] && t=wifi
                echo "$t \${d##*/}"; exit 0
            done
            echo none`]
        stdout: StdioCollector {
            onStreamFinished: {
                const [t, dev] = text.trim().split(" ");
                root.candType = t || "none";
                root.cand = t && t !== "none" ? dev : "";
                if (root.cand !== root.iface || root.candType !== root.type) {
                    root.iface = root.cand;
                    root.type = root.candType;
                    root.lastTime = 0;   // счётчики другого интерфейса — скорость с нуля
                }
            }
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
