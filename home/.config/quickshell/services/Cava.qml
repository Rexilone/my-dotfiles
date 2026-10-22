pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// спектр звука от cava: values — 32 полосы 0..1; cava работает, только пока кто-то смотрит (need)
Singleton {
    id: root

    readonly property int bands: 32
    property var values: new Array(bands).fill(0)
    readonly property bool installed: probe.found

    property var consumers: ({})
    readonly property bool active: installed && Object.keys(consumers).length > 0

    function need(id, on) {
        const c = Object.assign({}, consumers);
        if (on) c[id] = true;
        else delete c[id];
        consumers = c;
    }

    // n полос из 32: усреднение соседних
    function take(n) {
        if (n >= bands) return values;
        const out = [], step = bands / n;
        for (let i = 0; i < n; i++) {
            let s = 0, c = 0;
            for (let j = Math.floor(i * step); j < Math.floor((i + 1) * step); j++) { s += values[j]; c++; }
            out.push(c ? s / c : 0);
        }
        return out;
    }

    onActiveChanged: if (!active) values = new Array(bands).fill(0)

    Process {
        id: probe
        property bool found: false
        running: true
        command: ["sh", "-c", "command -v cava"]
        onExited: code => found = code === 0
    }

    Process {
        running: root.active
        command: ["sh", "-c", `printf '%s\\n' '[general]' 'framerate = 45' 'bars = ${root.bands}' 'sleep_timer = 3' \
            '[output]' 'method = raw' 'raw_target = /dev/stdout' 'data_format = ascii' 'ascii_max_range = 100' \
            'bar_delimiter = 59' 'frame_delimiter = 10' '[smoothing]' 'noise_reduction = 60' | exec cava -p /dev/stdin`]
        stdout: SplitParser {
            onRead: line => {
                const v = line.split(";").filter(x => x !== "").map(x => Number(x) / 100);
                if (v.length === root.bands) root.values = v;
            }
        }
    }
}
