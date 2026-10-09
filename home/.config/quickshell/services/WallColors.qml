pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// схема «под обои»: берём самый заметный насыщенный цвет обоев
// и строим из его оттенка тёмную палитру с акцентом
Singleton {
    id: root

    property var palette: null
    property string source: ""

    function hsl(h, s, l) {
        return Qt.hsla(h, s, l, 1).toString();
    }

    function build(hex) {
        const c = Qt.color(hex);
        const h = c.hslHue < 0 ? 0 : c.hslHue;
        const s = Math.max(0.35, Math.min(0.75, c.hslSaturation));
        palette = {
            name: "Wallpaper",
            bg: hsl(h, 0.16, 0.075), surface: hsl(h, 0.15, 0.105), surfaceHi: hsl(h, 0.14, 0.135),
            surfaceHi2: hsl(h, 0.13, 0.17), line: hsl(h, 0.12, 0.25),
            fg: hsl(h, 0.18, 0.87), fgHover: hsl(h, 0.2, 0.93), fgPressed: hsl(h, 0.15, 0.76),
            muted: hsl(h, 0.1, 0.66), dim: hsl(h, 0.08, 0.46), faint: hsl(h, 0.1, 0.22),
            urgent: "#d9706f", warn: "#e0b060", accent: hsl(h, s, 0.68), rec: "#e05d5d",
        };
    }

    function update(path) {
        if (!path || path === source && palette) return;
        source = path;
        extract.command = ["sh", "-c",
            'magick "$1[0]" -resize 96x96 -colors 8 -format "%c" histogram:info:- < /dev/null 2>/dev/null', "sh", path];
        extract.running = true;
    }

    Process {
        id: extract
        stdout: StdioCollector {
            onStreamFinished: {
                // строки вида: "  120: (r,g,b) #RRGGBB srgb(...)"
                let best = null, bestScore = -1;
                for (const line of text.split("\n")) {
                    const m = line.match(/^\s*(\d+):.*?(#[0-9A-Fa-f]{6})/);
                    if (!m) continue;
                    const c = Qt.color(m[2]);
                    const score = Number(m[1]) * (0.15 + c.hslSaturation) * (c.hslLightness > 0.12 && c.hslLightness < 0.9 ? 1 : 0.2);
                    if (score > bestScore) {
                        bestScore = score;
                        best = m[2];
                    }
                }
                if (best) root.build(best);
            }
        }
    }

    // следим за текущими обоями
    Connections {
        target: Wallpapers
        function onCurrentChanged() {
            if (Settings.scheme === "wallpaper") root.update(Wallpapers.current);
        }
    }

    Connections {
        target: Settings
        function onSchemeChanged() {
            if (Settings.scheme === "wallpaper") {
                if (!Wallpapers.current) Wallpapers.refresh();
                else root.update(Wallpapers.current);
            }
        }
    }

    Component.onCompleted: {
        if (Settings.scheme === "wallpaper") Wallpapers.refresh();
    }
}
