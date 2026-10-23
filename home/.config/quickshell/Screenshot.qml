import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// скриншотилка: qs ipc call screenshot open (Print)
// Экран замирает (grim), поверх — снимок:
//   тянуть мышью — выделить область; клик — выделить картинку/блок/окно по его границам;
//   тянуть по тексту — выделить текст (распознаётся tesseract), Alt — область даже поверх текста;
//   двойной клик по слову — вся строка, Ctrl+A — весь текст.
// Enter / Ctrl+C — скопировать (картинку — ещё и сохранить в ~/Pictures/Screenshots), Ctrl+S — только сохранить,
// T — текст из выделенной области, F — весь экран, Esc — закрыть.
Scope {
    id: root

    property bool open: false
    property bool capturing: false
    property int stamp: 0
    readonly property string dir: Quickshell.cachePath("screenshot")
    property var current: null     // окно монитора, где сейчас выделение

    function start() {
        if (open || capturing) return;
        capturing = true;
        current = null;
        stamp++;
        grab.command = ["sh", "-c", 'mkdir -p "$1" && cd "$1" && rm -f ./*.png && shift && for o in "$@"; do grim -o "$o" "$o.png" & done; wait',
                        "sh", dir].concat(Quickshell.screens.map(s => s.name));
        grab.running = true;
    }

    function close() {
        open = false;
        current = null;
    }

    function savePath() {
        const d = new Date();
        const p = n => String(n).padStart(2, "0");
        return `${Quickshell.env("HOME")}/Pictures/Screenshots/Screenshot from ${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}-${p(d.getMinutes())}-${p(d.getSeconds())}.png`;
    }

    // вырезать область снимка (пиксели) и скопировать/сохранить
    function exportImage(src, x, y, w, h, copy, save) {
        const out = savePath();
        Quickshell.execDetached(["sh", "-c", `
            tmp="$1.crop.png"
            magick "$1" -crop "$4x$5+$2+$3" +repage "$tmp" || exit 1
            [ "$6" = 1 ] && wl-copy -t image/png < "$tmp"
            if [ "$7" = 1 ]; then mkdir -p "$(dirname "$8")"; cp "$tmp" "$8"; fi
            notify-send -a Screenshot -i "$tmp" "$9" "${"$"}{10}"`,
            "sh", src, String(x), String(y), String(w), String(h), copy ? "1" : "0", save ? "1" : "0", out,
            I18n.tr(copy ? "Screenshot copied" : "Screenshot saved"),
            save ? out.split("/").pop() : I18n.tr("In the clipboard")]);
        close();
    }

    function copyText(text) {
        if (!text) return;
        Quickshell.execDetached(["wl-copy", "--", text]);
        Quickshell.execDetached(["notify-send", "-a", "Screenshot", I18n.tr("Text copied"), text.length > 160 ? text.slice(0, 160) + "…" : text]);
        close();
    }

    IpcHandler {
        target: "screenshot"

        function open(): void { root.start(); }
        function hide(): void { root.close(); }
    }

    Process {
        id: grab
        onExited: code => {
            root.capturing = false;
            if (code === 0) root.open = true;
            else Quickshell.execDetached(["notify-send", "-a", "Screenshot", I18n.tr("Screenshot failed"), I18n.tr("Is grim installed?")]);
        }
    }

    Variants {
        model: root.open ? Quickshell.screens : []

        PanelWindow {
            id: win

            required property ShellScreen modelData
            screen: modelData

            readonly property string src: `${root.dir}/${modelData.name}.png`
            // пиксели снимка на логический пиксель экрана
            readonly property real k: shot.implicitWidth > 0 ? shot.implicitWidth / width : 1
            readonly property bool focused: Settings.activeScreen() === modelData

            property var objects: []      // [[x, y, w, h], …] в пикселях снимка
            property var words: []        // [{ x, y, w, h, text, line }]
            property bool ocrDone: false

            // выделение в логических координатах окна
            property rect sel: Qt.rect(0, 0, 0, 0)
            readonly property bool hasSel: sel.width > 2 && sel.height > 2
            property rect hover: Qt.rect(0, 0, 0, 0)
            property int tA: -1           // выделение текста: от слова…
            property int tB: -1           // …до слова
            readonly property bool hasText: tA >= 0 && tB >= 0
            readonly property int tLo: Math.min(tA, tB)
            readonly property int tHi: Math.max(tA, tB)

            color: "black"
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-screenshot"
            WlrLayershell.keyboardFocus: focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            function wordRect(i) {
                const w = words[i];
                return Qt.rect(w.x / k, w.y / k, w.w / k, w.h / k);
            }
            function wordAt(x, y) {
                for (let i = 0; i < words.length; i++) {
                    const r = wordRect(i);
                    if (x >= r.x - 3 && x <= r.x + r.width + 3 && y >= r.y - 3 && y <= r.y + r.height + 3) return i;
                }
                return -1;
            }
            // ближайшее слово — чтобы выделение текста продолжалось и между строк
            function nearestWord(x, y) {
                let best = -1, bd = 1e9;
                for (let i = 0; i < words.length; i++) {
                    const r = wordRect(i);
                    const dx = Math.max(r.x - x, 0, x - r.x - r.width), dy = Math.max(r.y - y, 0, y - r.y - r.height);
                    const d = dx + dy * 3;
                    if (d < bd) { bd = d; best = i; }
                }
                return best;
            }
            // что выделит клик: самая маленькая найденная картинка/блок под курсором, иначе весь экран
            function candidateAt(x, y) {
                const px = x * k, py = y * k;
                let best = null;
                for (const o of objects) {
                    if (px >= o[0] && px <= o[0] + o[2] && py >= o[1] && py <= o[1] + o[3] && (!best || o[2] * o[3] < best[2] * best[3])) best = o;
                }
                return best ? Qt.rect(best[0] / k, best[1] / k, best[2] / k, best[3] / k) : Qt.rect(0, 0, width, height);
            }
            function textOf(list) {
                let out = "", line = null;
                for (const w of list) {
                    if (line !== null) out += w.line === line ? " " : "\n";
                    out += w.text;
                    line = w.line;
                }
                return out;
            }
            function selectedText() {
                return hasText ? textOf(words.slice(tLo, tHi + 1)) : "";
            }
            // слова, центр которых внутри области
            function textInSel() {
                return textOf(words.filter(w => {
                    const cx = (w.x + w.w / 2) / k, cy = (w.y + w.h / 2) / k;
                    return cx >= sel.x && cx <= sel.x + sel.width && cy >= sel.y && cy <= sel.y + sel.height;
                }));
            }
            function selectLine(i) {
                let a = i, b = i;
                while (a > 0 && words[a - 1].line === words[i].line) a--;
                while (b < words.length - 1 && words[b + 1].line === words[i].line) b++;
                tA = a; tB = b;
                sel = Qt.rect(0, 0, 0, 0);
                root.current = win;
            }
            function exportSel(copy, save) {
                const r = hasSel ? sel : Qt.rect(0, 0, width, height);
                root.exportImage(src, Math.round(r.x * k), Math.round(r.y * k), Math.round(r.width * k), Math.round(r.height * k), copy, save);
            }
            // Enter / Ctrl+C: выделенный текст — его, иначе картинку
            function primary() {
                if (hasText) root.copyText(selectedText());
                else exportSel(true, true);
            }

            Process {
                running: true
                command: ["python3", Quickshell.shellDir + "/scripts/shot-analyze.py", "objects", win.src]
                stdout: StdioCollector {
                    onStreamFinished: { try { win.objects = JSON.parse(text); } catch (e) {} }
                }
            }
            Process {
                running: true
                command: ["python3", Quickshell.shellDir + "/scripts/shot-analyze.py", "text", win.src]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { win.words = JSON.parse(text); } catch (e) {}
                        win.ocrDone = true;
                    }
                }
            }

            Image {
                id: shot
                anchors.fill: parent
                source: "file://" + win.src + "?" + root.stamp
                cache: false
                smooth: true
            }

            // затемнение вокруг выделения
            Item {
                anchors.fill: parent
                readonly property rect r: win.hasSel ? win.sel : Qt.rect(0, 0, 0, 0)
                readonly property real a: win.hasSel ? 0.45 : 0.18
                Rectangle { x: 0; y: 0; width: parent.width; height: parent.r.y; color: "black"; opacity: parent.a }
                Rectangle { x: 0; y: parent.r.y + parent.r.height; width: parent.width; height: parent.height - y; color: "black"; opacity: parent.a }
                Rectangle { x: 0; y: parent.r.y; width: parent.r.x; height: parent.r.height; color: "black"; opacity: parent.a }
                Rectangle { x: parent.r.x + parent.r.width; y: parent.r.y; width: parent.width - x; height: parent.r.height; color: "black"; opacity: parent.a }
            }

            // что выделит клик
            Rectangle {
                visible: !win.hasSel && !win.hasText && area.containsMouse && !area.pressed && win.hover.width < win.width
                x: win.hover.x; y: win.hover.y; width: win.hover.width; height: win.hover.height
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
                border.width: 1
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
                radius: 4
            }

            // выделенные слова
            Repeater {
                model: win.hasText ? win.tHi - win.tLo + 1 : 0

                Rectangle {
                    required property int index
                    readonly property rect r: win.wordRect(win.tLo + index)
                    x: r.x - 2; y: r.y - 2; width: r.width + 4; height: r.height + 4
                    radius: 3
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                }
            }

            // рамка выделения и размер
            Rectangle {
                visible: win.hasSel
                x: win.sel.x; y: win.sel.y; width: win.sel.width; height: win.sel.height
                color: "transparent"
                border.width: 2
                border.color: Theme.accent

                Rectangle {
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 6
                    visible: parent.y > 30
                    width: sizeText.implicitWidth + 12
                    height: 22
                    radius: 6
                    color: Theme.surface

                    Text {
                        id: sizeText
                        anchors.centerIn: parent
                        text: `${Math.round(win.sel.width * win.k)} × ${Math.round(win.sel.height * win.k)}`
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: pressed ? (mode === "text" ? Qt.IBeamCursor : Qt.CrossCursor)
                    : win.wordAt(mouseX, mouseY) >= 0 ? Qt.IBeamCursor : Qt.CrossCursor

                property point p0
                property string mode: ""     // "" | "region" | "text"
                property bool moved: false
                property bool alt: false

                onPositionChanged: mouse => {
                    if (!pressed) {
                        win.hover = win.candidateAt(mouse.x, mouse.y);
                        return;
                    }
                    if (!moved && Math.abs(mouse.x - p0.x) + Math.abs(mouse.y - p0.y) < 5) return;
                    moved = true;
                    root.current = win;
                    if (mode === "text") {
                        win.tB = win.nearestWord(mouse.x, mouse.y);
                    } else {
                        win.sel = Qt.rect(Math.min(p0.x, mouse.x), Math.min(p0.y, mouse.y), Math.abs(mouse.x - p0.x), Math.abs(mouse.y - p0.y));
                    }
                }
                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) return;
                    p0 = Qt.point(mouse.x, mouse.y);
                    moved = false;
                    alt = mouse.modifiers & Qt.AltModifier;
                    const w = alt ? -1 : win.wordAt(mouse.x, mouse.y);
                    mode = w >= 0 ? "text" : "region";
                    if (mode === "text") {
                        win.sel = Qt.rect(0, 0, 0, 0);
                        win.tA = w;
                        win.tB = w;
                    } else {
                        win.tA = win.tB = -1;
                    }
                }
                onReleased: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        // ПКМ: снять выделение, без выделения — закрыть
                        if (win.hasSel || win.hasText) { win.sel = Qt.rect(0, 0, 0, 0); win.tA = win.tB = -1; }
                        else root.close();
                        return;
                    }
                    if (moved) return;
                    // клик — выделить по границам того, что под курсором
                    win.tA = win.tB = -1;
                    win.sel = win.candidateAt(mouse.x, mouse.y);
                    root.current = win;
                }
                onDoubleClicked: mouse => {
                    const w = win.wordAt(mouse.x, mouse.y);
                    if (w >= 0) win.selectLine(w);
                }
            }

            // ── панель действий у выделения
            Rectangle {
                id: bar
                visible: win.hasSel || win.hasText
                readonly property rect anchorRect: win.hasSel ? win.sel : (win.hasText ? (() => {
                    const a = win.wordRect(win.tLo), b = win.wordRect(win.tHi);
                    const x0 = Math.min(a.x, b.x), y0 = Math.min(a.y, b.y);
                    return Qt.rect(x0, y0, Math.max(a.x + a.width, b.x + b.width) - x0, Math.max(a.y + a.height, b.y + b.height) - y0);
                })() : Qt.rect(0, 0, 0, 0))
                x: Math.max(8, Math.min(win.width - width - 8, anchorRect.x + anchorRect.width - width))
                y: anchorRect.y + anchorRect.height + 10 + height < win.height ? anchorRect.y + anchorRect.height + 10
                    : Math.max(8, anchorRect.y - height - 10)
                width: actions.implicitWidth + 12
                height: 40
                radius: 12
                color: Theme.surface
                border.width: 1
                border.color: Theme.line

                RowLayout {
                    id: actions
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: win.hasText ? [
                            { icon: 0xF018F, text: "Copy text", key: "Enter", act: () => root.copyText(win.selectedText()) },
                        ] : [
                            { icon: 0xF018F, text: "Copy", key: "Enter", act: () => win.exportSel(true, true) },
                            { icon: 0xF0193, text: "Save", key: "Ctrl+S", act: () => win.exportSel(false, true) },
                            { icon: 0xF05CA, text: win.ocrDone ? "Text" : "Text…", key: "T", act: () => root.copyText(win.textInSel()), off: !win.ocrDone },
                        ]

                        Rectangle {
                            required property var modelData
                            implicitWidth: row.implicitWidth + 20
                            implicitHeight: 30
                            radius: 8
                            opacity: modelData.off ? 0.5 : 1
                            color: btnArea.containsMouse ? Theme.surfaceHi2 : "transparent"

                            Row {
                                id: row
                                anchors.centerIn: parent
                                spacing: 7
                                Text {
                                    text: String.fromCodePoint(parent.parent.modelData.icon)
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.iconSize
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: I18n.tr(parent.parent.modelData.text)
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: parent.parent.modelData.key
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 3
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            MouseArea {
                                id: btnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (!parent.modelData.off) parent.modelData.act()
                            }
                        }
                    }
                }
            }

            // ── подсказка сверху
            Rectangle {
                visible: win.focused
                anchors.horizontalCenter: parent.horizontalCenter
                y: 14
                width: hint.implicitWidth + 28
                height: 34
                radius: 10
                color: Theme.surface
                opacity: 0.94
                border.width: 1
                border.color: Theme.line

                Text {
                    id: hint
                    anchors.centerIn: parent
                    text: (win.ocrDone ? (win.words.length ? "" : I18n.tr("No text found") + "   ·   ") : I18n.tr("Recognizing text…") + "   ·   ")
                        + I18n.tr("Drag — area   ·   click — by edges   ·   drag over text — select it   ·   F — whole screen   ·   Esc")
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            Item {
                anchors.fill: parent
                focus: win.focused
                Component.onCompleted: if (win.focused) forceActiveFocus()
                Keys.onPressed: event => {
                    const w = root.current ?? win;
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    if (event.key === Qt.Key_Escape) root.close();
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (ctrl && event.key === Qt.Key_C)) w.primary();
                    else if (ctrl && event.key === Qt.Key_S) w.exportSel(false, true);
                    else if (ctrl && event.key === Qt.Key_A && w.words.length) { w.sel = Qt.rect(0, 0, 0, 0); w.tA = 0; w.tB = w.words.length - 1; root.current = w; }
                    else if (event.key === Qt.Key_F) { w.tA = w.tB = -1; w.sel = Qt.rect(0, 0, w.width, w.height); root.current = w; }
                    else if (event.key === Qt.Key_T && w.hasSel && w.ocrDone) root.copyText(w.textInSel());
                    else return;
                    event.accepted = true;
                }
            }
        }
    }
}
