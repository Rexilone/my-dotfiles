pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// загрузка и температуры CPU/GPU, память; опрос идёт только пока active
Singleton {
    id: root

    // опрос идёт, пока его кто-то запросил (окно часов, виджет)
    property var consumers: ({})
    readonly property bool active: Object.keys(consumers).length > 0

    function need(id, on) {
        const c = Object.assign({}, consumers);
        if (on) c[id] = true;
        else delete c[id];
        consumers = c;
    }

    property real cpu: 0          // 0..1
    property real cpuTemp: 0      // °C
    property real gpu: 0
    property real gpuTemp: 0
    property real vramUsed: 0     // байты
    property real vramTotal: 0
    property real ramUsed: 0      // КиБ
    property real ramTotal: 0

    property var prevCpu: null

    function gb(kib) {
        return (kib / 1024 / 1024).toFixed(1);
    }

    function parse(line) {
        const [cpuLine, ct, gb, gt, vram, mem] = line.split("|");
        const n = cpuLine.trim().split(/\s+/).slice(1).map(Number);
        const idle = n[3] + n[4];
        const total = n.slice(0, 8).reduce((a, b) => a + b, 0);
        if (prevCpu) {
            const dt = total - prevCpu.total;
            if (dt > 0) cpu = 1 - (idle - prevCpu.idle) / dt;
        }
        prevCpu = { idle, total };
        cpuTemp = Number(ct) / 1000;
        gpu = Number(gb) / 100;
        gpuTemp = Number(gt) / 1000;
        const [vu, vt] = vram.trim().split(" ").map(Number);
        vramUsed = vu || 0;
        vramTotal = vt || 0;
        const [mt, ma] = mem.trim().split(" ").map(Number);
        ramTotal = mt;
        ramUsed = mt - ma;
    }

    onActiveChanged: if (!active) prevCpu = null

    // где лежат датчики — один раз; дальше файлы читаются напрямую (без запуска процессов)
    property var paths: ({})
    Process {
        running: true
        command: ["sh", "-c", `
            for h in /sys/class/hwmon/hwmon*; do
                case "$(cat "$h/name")" in
                    k10temp|coretemp|zenpower) [ -z "$ct" ] && ct="$h/temp1_input" ;;
                    amdgpu) [ -z "$gh" ] && gh="$h" ;;
                esac
            done
            gd=$(readlink -f "$gh/device" 2>/dev/null)
            printf '%s\n%s\n%s\n' "$ct" "$gh" "$gd"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const [ct, gh, gd] = text.split("\n");
                root.paths = { cpuTemp: ct, gpuTemp: gh ? gh + "/temp1_input" : "", gpuBusy: gd ? gd + "/gpu_busy_percent" : "",
                               vramUsed: gd ? gd + "/mem_info_vram_used" : "", vramTotal: gd ? gd + "/mem_info_vram_total" : "" };
            }
        }
    }
    FileView { id: fStat; path: "/proc/stat"; blockLoading: true; printErrors: false }
    FileView { id: fMem; path: "/proc/meminfo"; blockLoading: true; printErrors: false }
    FileView { id: fCt; path: root.paths.cpuTemp ?? ""; blockLoading: true; printErrors: false }
    FileView { id: fGb; path: root.paths.gpuBusy ?? ""; blockLoading: true; printErrors: false }
    FileView { id: fGt; path: root.paths.gpuTemp ?? ""; blockLoading: true; printErrors: false }
    FileView { id: fVu; path: root.paths.vramUsed ?? ""; blockLoading: true; printErrors: false }
    FileView { id: fVt; path: root.paths.vramTotal ?? ""; blockLoading: true; printErrors: false }

    function read(f) {
        if (!f.path) return "0";
        f.reload();
        return f.text().trim() || "0";
    }

    Timer {
        running: root.active
        interval: 1500
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const mem = (() => {
                fMem.reload();
                const m = fMem.text();
                const t = /MemTotal:\s+(\d+)/.exec(m), a = /MemAvailable:\s+(\d+)/.exec(m);
                return `${t ? t[1] : 0} ${a ? a[1] : 0}`;
            })();
            fStat.reload();
            root.parse([fStat.text().split("\n")[0], root.read(fCt), root.read(fGb), root.read(fGt),
                        `${root.read(fVu)} ${root.read(fVt)}`, mem].join("|"));
        }
    }
}
