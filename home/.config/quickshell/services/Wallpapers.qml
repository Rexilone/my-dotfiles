pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// обои через awww: список из папки, миниатюры в кэше, текущие обои
Singleton {
    id: root

    property string dir: `${Quickshell.env("HOME")}/Pictures/Wallpapers`
    readonly property string cacheDir: Quickshell.cachePath("wallthumbs")

    property var items: []          // [{ path, name, thumb, size }]
    property string current: ""
    property bool loading: false

    function refresh() {
        loading = true;
        scan.running = true;
        query.running = true;
    }

    function apply(path) {
        if (!path) return;
        current = path;
        Quickshell.execDetached(["awww", "img", path,
            "--transition-type", "grow", "--transition-pos", "top",
            "--transition-duration", "1.2", "--transition-fps", "180"]);
    }

    function random() {
        const others = items.filter(i => i.path !== current);
        if (others.length) apply(others[Math.floor(Math.random() * others.length)].path);
    }

    function openFolder() {
        Quickshell.execDetached(["xdg-open", dir]);
    }

    // список + миниатюры (создаются один раз) + размеры
    Process {
        id: scan
        command: ["sh", "-c", `
            dir="$1"; cache="$2"; mkdir -p "$cache"
            find -L "$dir" -maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\
                -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \\) | sort -f | while IFS= read -r f; do
                h=$(printf '%s' "$f" | md5sum | cut -c1-16)
                t="$cache/$h.jpg"; d="$cache/$h.txt"
                if [ ! -s "$t" ] || [ "$f" -nt "$t" ]; then
                    magick "$f[0]" -thumbnail 640x360^ -gravity center -extent 640x360 -quality 88 "$t" < /dev/null 2>/dev/null
                    magick identify -format '%wx%h' "$f[0]" < /dev/null > "$d" 2>/dev/null
                fi
                printf '%s\\t%s\\t%s\\n' "$f" "$t" "$(cat "$d" 2>/dev/null)"
            done`, "sh", root.dir, root.cacheDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.items = text.split("\n").filter(l => l).map(l => {
                    const [path, thumb, size] = l.split("\t");
                    return { path, thumb, size, name: path.split("/").pop().replace(/\.[^.]+$/, "") };
                });
                root.loading = false;
            }
        }
    }

    // текущие обои (с основного монитора, иначе с первого)
    Process {
        id: query
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const line = lines.find(l => l.includes(Settings.primary)) ?? lines[0] ?? "";
                const m = line.match(/image: (.+)$/);
                if (m) root.current = m[1].trim();
            }
        }
    }
}
