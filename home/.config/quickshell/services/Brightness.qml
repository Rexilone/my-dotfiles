pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// яркость экрана ноутбука: /sys/class/backlight/<устройство>/brightness (меняет brightnessctl,
// клавиши яркости — в niri). На ПК без подсветки available = false.
Singleton {
    id: root

    property string device: ""
    property int max: 0
    property int raw: -1
    readonly property bool available: device !== "" && max > 0
    readonly property real value: available && raw >= 0 ? raw / max : 0

    signal changed

    function set(frac) {
        Quickshell.execDetached(["brightnessctl", "--class=backlight", "set", `${Math.round(Math.max(0.01, Math.min(1, frac)) * 100)}%`]);
    }

    Process {
        running: true
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/max_brightness\" ] && { echo \"$d\"; cat \"$d/max_brightness\"; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [dev, max] = text.trim().split("\n");
                if (dev && +max > 0) {
                    root.max = +max;
                    root.device = dev;
                }
            }
        }
    }

    FileView {
        path: root.device ? `${root.device}/brightness` : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const v = parseInt(text());
            if (isNaN(v) || v === root.raw) return;
            const first = root.raw < 0;
            root.raw = v;
            if (!first) root.changed();
        }
    }
}
