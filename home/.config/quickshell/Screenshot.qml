import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.screenshot

// скриншотилка: qs ipc call screenshot open (Print), delay 3 (Shift+Print), history (Ctrl+Print)
// Экран замирает (grim), поверх — снимок с инструментами (screenshot/ShotWindow.qml):
// текст и картинки выделяются мышью, рисование, размытие, QR, пипетка, линейка, перевод,
// закрепить снимок поверх окон, длинный скриншот с прокруткой, таймер, история с поиском по тексту.
Scope {
    id: root

    property bool open: false
    property bool capturing: false
    property int stamp: 0
    readonly property string dir: Quickshell.cachePath("screenshot")
    readonly property string shotsDir: `${Quickshell.env("HOME")}/Pictures/Screenshots`
    property var current: null      // окно монитора, где сейчас выделение
    property int countdown: 0       // таймер перед снимком, секунды
    property var pins: []           // закреплённые снимки: [{ id, path, screen, x, y, w, h }]
    property var longCap: null      // длинный скриншот: { screen, x, y, w, h (глобальные), out }
    property int longHeight: 0
    property bool longAuto: false     // листает сам
    property bool longLost: false     // прокрутили слишком далеко — вернуться чуть назад
    property bool historyOpen: false

    // ── снимок
    function start() {
        if (open || capturing || longCap) return;
        capturing = true;
        current = null;
        stamp++;
        // старые вырезки (out-*) живут сутки: на них могут ссылаться закреплённые снимки
        grab.command = ["sh", "-c", 'mkdir -p "$1" && cd "$1" && rm -f ./shot-*.png && find . -name "out-*.png" -mmin +1440 -delete; shift; for o in "$@"; do grim -o "$o" "shot-$o.png" & done; wait',
                        "sh", dir].concat(Quickshell.screens.map(s => s.name));
        grab.running = true;
    }

    function startIn(sec) {
        if (open) close();
        countdown = Math.max(1, sec);
    }

    function close() {
        open = false;
        current = null;
    }

    function shotPath(name) {
        return `${dir}/shot-${name}.png`;
    }

    function savePath() {
        const d = new Date();
        const p = n => String(n).padStart(2, "0");
        return `${shotsDir}/Screenshot from ${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}-${p(d.getMinutes())}-${p(d.getSeconds())}.png`;
    }

    function notify(title, body, icon) {
        Quickshell.execDetached(["notify-send", "-a", I18n.tr("Screenshot"), "-i", icon || "camera-photo", title, body || ""]);
    }

    // готовая картинка (уже обрезанная): в буфер, в файл, закрепить; в историю — если сохранена
    function deliver(file, copy, save, pin, pinGeom) {
        const out = savePath();
        Quickshell.execDetached(["sh", "-c", `
            [ "$2" = 1 ] && wl-copy -t image/png < "$1"
            if [ "$3" = 1 ]; then mkdir -p "$(dirname "$4")"; cp "$1" "$4"; fi`,
            "sh", file, copy ? "1" : "0", save ? "1" : "0", out]);
        if (save) hist.add(out);
        if (pin) addPin(file, pinGeom);
        if (copy || save)
            notify(I18n.tr(copy ? "Screenshot copied" : "Screenshot saved"), save ? out.split("/").pop() : I18n.tr("In the clipboard"), file);
    }

    // картинка всего экрана (с рисунками) → вырезать область → deliver
    function finish(full, x, y, w, h, copy, save, pin, geom) {
        const out = full.replace(/\.full\.png$/, "");
        cropProc.job = { out, copy, save, pin, geom };
        cropProc.command = ["sh", "-c", 'magick "$1" -crop "$4x$5+$2+$3" +repage "$6" && rm -f "$1"',
                            "sh", full, String(x), String(y), String(w), String(h), out];
        cropProc.running = true;
    }

    function copyText(text) {
        if (!text) return;
        Quickshell.execDetached(["wl-copy", "--", text]);
        notify(I18n.tr("Text copied"), text.length > 160 ? text.slice(0, 160) + "…" : text, "edit-copy");
    }

    // ── закреплённые снимки
    property int pinSeq: 0
    function addPin(file, g) {
        pinSeq++;
        pins = pins.concat([{ id: pinSeq, path: file, screen: g.screen, x: g.x, y: g.y, w: g.w, h: g.h }]);
    }
    // файл для очередной вырезки: у каждой свой, чтобы закреплённые не перезаписывались
    property int outSeq: 0
    function outPath() {
        outSeq++;
        return `${dir}/out-${Date.now()}-${outSeq}.png`;
    }
    function removePin(id) {
        pins = pins.filter(p => p.id !== id);
    }

    // ── длинный скриншот: область прокручивают, кадры склеиваются (scripts/shot-long.py)
    function startLong(screen, x, y, w, h) {
        const out = `${dir}/long-${Date.now()}.png`;
        close();
        longHeight = 0;
        longAuto = false;
        longLost = false;
        longCap = { screen, x, y, w, h, out };
        // оверлей успевает исчезнуть до первого кадра
        longStart.restart();
    }
    function stopLong(keep) {
        if (!longCap) return;
        longCap.cancelled = !keep;
        Quickshell.execDetached(["touch", longCap.out + ".stop"]);
    }
    // листать самому (стрелкой вниз в окне с фокусом), пока страница не кончится
    function autoLong() {
        if (!longCap) return;
        Quickshell.execDetached(["touch", longCap.out + ".auto"]);
    }

    IpcHandler {
        target: "screenshot"

        function open(): void { root.start(); }
        function delay(seconds: int): void { root.startIn(seconds); }
        function history(): void { root.historyOpen = !root.historyOpen; }
        function hide(): void { root.close(); }
    }

    Process {
        id: cropProc
        property var job: null
        // ImageMagick без OpenCL (на NVIDIA он будит видеокарту и компилирует ядра)
        environment: ({ MAGICK_OCL_DEVICE: "OFF" })
        onExited: code => {
            if (code === 0) root.deliver(job.out, job.copy, job.save, job.pin, job.geom);
            else root.notify(I18n.tr("Screenshot failed"), "", "dialog-error");
        }
    }

    Process {
        id: grab
        onExited: code => {
            root.capturing = false;
            if (code === 0) root.open = true;
            else root.notify(I18n.tr("Screenshot failed"), I18n.tr("Is grim installed?"), "dialog-error");
        }
    }

    Timer {
        id: longStart
        interval: 250
        onTriggered: {
            const c = root.longCap;
            longProc.command = ["python3", Quickshell.shellDir + "/scripts/shot-long.py",
                                String(Math.round(c.x)), String(Math.round(c.y)), String(Math.round(c.w)), String(Math.round(c.h)), c.out];
            longProc.running = true;
        }
    }

    Process {
        id: longProc
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("height ")) {
                    root.longHeight = parseInt(line.slice(7));
                    root.longLost = false;
                } else if (line === "lost") root.longLost = true;
                else if (line === "auto") root.longAuto = true;
            }
        }
        onExited: code => {
            const c = root.longCap;
            root.longCap = null;
            // «Готово», конец страницы при авто-прокрутке — сохранить; «Отмена» — нет
            if (c && !c.cancelled && code === 0) root.deliver(c.out, true, true, false);
        }
    }

    // таймер: тикает, на нуле — снимок (табло к этому времени уже скрыто)
    Timer {
        running: root.countdown > 0
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown === 0) shootAfterCountdown.restart();
        }
    }
    Timer {
        id: shootAfterCountdown
        interval: 180
        onTriggered: root.start()
    }

    ScreenshotHistory {
        id: hist
        ctl: root
    }

    Variants {
        model: root.open ? Quickshell.screens : []

        ShotWindow {
            ctl: root
        }
    }

    Variants {
        model: root.pins

        Pin {
            ctl: root
        }
    }

    Variants {
        model: root.longCap ? [root.longCap] : []

        LongFrame {
            ctl: root
        }
    }

    Countdown {
        ctl: root
    }
}
