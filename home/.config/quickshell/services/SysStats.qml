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

    Process {
        running: root.active
        command: ["sh", "-c", `
            for h in /sys/class/hwmon/hwmon*; do
                case "$(cat "$h/name")" in
                    k10temp|coretemp|zenpower) [ -z "$ct" ] && ct="$h/temp1_input" ;;
                    amdgpu) [ -z "$gh" ] && gh="$h" ;;
                esac
            done
            gd=$(readlink -f "$gh/device" 2>/dev/null)
            while :; do
                printf '%s|%s|%s|%s|%s %s|%s\\n' \\
                    "$(head -n1 /proc/stat)" \\
                    "$(cat "$ct" 2>/dev/null || echo 0)" \\
                    "$(cat "$gd/gpu_busy_percent" 2>/dev/null || echo 0)" \\
                    "$(cat "$gh/temp1_input" 2>/dev/null || echo 0)" \\
                    "$(cat "$gd/mem_info_vram_used" 2>/dev/null || echo 0)" \\
                    "$(cat "$gd/mem_info_vram_total" 2>/dev/null || echo 0)" \\
                    "$(awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{print t, a}' /proc/meminfo)"
                sleep 1.5
            done`]
        stdout: SplitParser {
            onRead: line => root.parse(line)
        }
    }
}
