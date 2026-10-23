import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// окно скриншотилки на одном мониторе: замороженный снимок, выделение, рисование, действия.
// Внутри scene — то, что попадает в картинку (снимок, размытие, рисунки); всё остальное — интерфейс.
PanelWindow {
    id: win

    required property ShellScreen modelData
    required property var ctl
    screen: modelData

    readonly property string src: ctl.shotPath(modelData.name)
    // пиксели снимка на логический пиксель экрана
    readonly property real k: shot.implicitWidth > 0 ? shot.implicitWidth / width : 1
    readonly property bool focused: Settings.activeScreen() === modelData

    // ── разбор снимка
    property var objects: []      // [[x, y, w, h], …] в пикселях снимка
    property var codes: []        // [{ x, y, w, h, text, kind }] QR и штрихкоды
    property var words: []        // [{ x, y, w, h, text, line }]
    property bool ocrDone: false

    // ── выделение (логические координаты окна)
    property rect sel: Qt.rect(0, 0, 0, 0)
    readonly property bool hasSel: sel.width > 2 && sel.height > 2
    property rect hover: Qt.rect(0, 0, 0, 0)
    property int tA: -1           // выделение текста: от слова…
    property int tB: -1           // …до слова
    readonly property bool hasText: tA >= 0 && tB >= 0
    readonly property int tLo: Math.min(tA, tB)
    readonly property int tHi: Math.max(tA, tB)

    // ── инструменты и рисунки
    property string tool: "select"   // select arrow rect pen marker text num blur ruler picker
    readonly property var inks: [Theme.accent, "#f25c54", "#f4b740", "#4cc38a", "#ffffff"]
    property int colorIdx: 1
    readonly property color ink: inks[colorIdx]
    property var shapes: []
    property var draft: null
    property int numNext: 1
    property var ruler: null         // { x1, y1, x2, y2 }
    property point mouse: Qt.point(-100, -100)
    property string toast: ""
    property var translation: null   // { busy, text }

    readonly property var tools: [
        { id: "select", icon: 0xF01BF, tip: "Select", key: "V" },
        { id: "arrow", icon: 0xF005C, tip: "Arrow", key: "A" },
        { id: "rect", icon: 0xF0E5F, tip: "Rectangle", key: "R" },
        { id: "pen", icon: 0xF03EB, tip: "Pen", key: "P" },
        { id: "marker", icon: 0xF0652, tip: "Marker", key: "H" },
        { id: "text", icon: 0xF0284, tip: "Text", key: "X" },
        { id: "num", icon: 0xF0CA0, tip: "Numbers", key: "N" },
        { id: "blur", icon: 0xF00B5, tip: "Blur", key: "B" },
        { id: "ruler", icon: 0xF046D, tip: "Ruler", key: "U" },
        { id: "picker", icon: 0xF020A, tip: "Color picker", key: "C" },
    ]

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

    // ═════════════════════════ логика
    function say(t) {
        toast = t;
        toastTimer.restart();
    }
    function setTool(t) {
        commitText();
        tool = t;
        if (t !== "ruler") ruler = null;
    }
    function wordRect(i) {
        const w = words[i];
        if (!w) return Qt.rect(0, 0, 0, 0);
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
            const d = Math.max(r.x - x, 0, x - r.x - r.width) + 3 * Math.max(r.y - y, 0, y - r.y - r.height);
            if (d < bd) { bd = d; best = i; }
        }
        return best;
    }
    // что выделит клик: самая маленькая найденная картинка/блок/код под курсором, иначе весь экран
    function candidateAt(x, y) {
        const px = x * k, py = y * k;
        let best = null;
        const all = objects.concat(codes.map(c => [c.x, c.y, c.w, c.h]));
        for (const o of all) {
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
    function inRect(w, r) {
        const cx = (w.x + w.w / 2) / k, cy = (w.y + w.h / 2) / k;
        return cx >= r.x && cx <= r.x + r.width && cy >= r.y && cy <= r.y + r.height;
    }
    function textInSel() {
        const r = hasSel ? sel : Qt.rect(0, 0, width, height);
        return textOf(words.filter(w => inRect(w, r)));
    }
    function selectLine(i) {
        let a = i, b = i;
        while (a > 0 && words[a - 1].line === words[i].line) a--;
        while (b < words.length - 1 && words[b + 1].line === words[i].line) b++;
        tA = a; tB = b;
        sel = Qt.rect(0, 0, 0, 0);
        ctl.current = win;
    }
    function selectAllText() {
        if (!words.length) return;
        sel = Qt.rect(0, 0, 0, 0);
        tA = 0; tB = words.length - 1;
        ctl.current = win;
    }
    function fullScreen() {
        tA = tB = -1;
        sel = Qt.rect(0, 0, width, height);
        ctl.current = win;
    }
    function undo() {
        if (editor.visible) { editor.visible = false; return; }
        if (!shapes.length) return;
        const last = shapes[shapes.length - 1];
        if (last.t === "num") numNext = Math.max(1, numNext - 1);
        shapes = shapes.slice(0, -1);
    }
    function addShape(s) {
        shapes = shapes.concat([s]);
        ctl.current = win;
    }

    // ── текст на картинке
    function startText(x, y) {
        commitText();
        editor.x = x;
        editor.y = y - 14;
        editor.text = "";
        editor.visible = true;
        editor.forceActiveFocus();
    }
    function commitText() {
        if (!editor.visible) return;
        editor.visible = false;
        if (editor.text.trim()) addShape({ t: "text", x: editor.x, y: editor.y + 14, text: editor.text, c: String(ink) });
        keys.forceActiveFocus();
    }

    // ── спрятать личное: почта, карты, телефоны, IP, ключи и токены — размытием поверх слов
    function hideSensitive() {
        const re = [
            /\S+@\S+\.\S{2,}/,                                     // почта
            /^\+?\d[\d\-()]{9,}$/,                                 // телефон, номер карты одним словом
            /^\d{1,3}(\.\d{1,3}){3}(:\d+)?$/,                      // IP
            /^(sk|pk|ghp|gho|xox[abp]|glpat|AKIA)[-_A-Za-z0-9]{8,}/, // ключи сервисов
            /^(?=.*\d)(?=.*[A-Za-z])[A-Za-z0-9_\-+/=]{24,}$/,      // длинные токены
        ];
        const r = hasSel ? sel : Qt.rect(0, 0, width, height);
        const add = [];
        for (let i = 0; i < words.length; i++) {
            const w = words[i];
            if (!inRect(w, r)) continue;
            let hit = re.some(x => x.test(w.text));
            // номер карты из групп по 4 цифры
            if (!hit && /^\d{4}$/.test(w.text)) {
                let n = 0;
                for (let j = i; j < words.length && /^\d{4}$/.test(words[j].text) && words[j].line === w.line; j++) n++;
                for (let j = i; j > 0 && /^\d{4}$/.test(words[j - 1].text) && words[j - 1].line === w.line; j--) n++;
                hit = n >= 3;
            }
            if (hit) {
                const q = wordRect(i);
                add.push({ t: "blur", x1: q.x - 4, y1: q.y - 4, x2: q.x + q.width + 4, y2: q.y + q.height + 4 });
            }
        }
        if (add.length) shapes = shapes.concat(add);
        say(add.length ? `${I18n.tr("Hidden")}: ${add.length}` : I18n.tr("Nothing private found"));
        ctl.current = win;
    }

    // ── перевод выделенного текста
    function translate(text) {
        if (!text) return;
        const to = /[а-яё]/i.test(text) ? "en" : (I18n.ru ? "ru" : "en");
        translation = { busy: true, text: "" };
        tr.command = ["curl", "-s", "--max-time", "10", "-X", "POST",
                      `https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=auto&tl=${to}`,
                      "--data-urlencode", `q=${text}`];
        tr.running = true;
    }
    Process {
        id: tr
        stdout: StdioCollector {
            onStreamFinished: {
                let out = "";
                try {
                    const r = JSON.parse(text);
                    out = Array.isArray(r[0]) ? r[0][0] : r[0];
                } catch (e) {}
                win.translation = { busy: false, text: out || I18n.tr("Translation failed") };
            }
        }
    }

    // ── пипетка: цвет пикселя (холст под снимком хранит копию картинки)
    function hexAt(x, y) {
        if (!pix.available) return "";
        const d = pix.getContext("2d").getImageData(Math.round(x), Math.round(y), 1, 1).data;
        const h = n => n.toString(16).padStart(2, "0");
        return `#${h(d[0])}${h(d[1])}${h(d[2])}`;
    }

    // ── выгрузка: scene → файл в полном разрешении → обрезка (в Screenshot.qml)
    function exportSel(copy, save, pin) {
        commitText();
        const r = hasSel ? sel : Qt.rect(0, 0, width, height);
        const full = ctl.outPath() + ".full.png";
        scene.grabToImage(res => {
            res.saveToFile(full);
            ctl.finish(full, Math.round(r.x * k), Math.round(r.y * k), Math.round(r.width * k), Math.round(r.height * k), copy, save, pin,
                       { screen: modelData.name, x: r.x, y: r.y, w: r.width, h: r.height });
            ctl.close();
        }, Qt.size(Math.round(width * k), Math.round(height * k)));
    }
    function startLong() {
        if (!hasSel) { say(I18n.tr("Select the area to scroll first")); return; }
        ctl.startLong(modelData.name, modelData.x + sel.x, modelData.y + sel.y, sel.width, sel.height);
    }
    // Enter / Ctrl+C: выделенный текст — его, иначе картинку
    function primary() {
        if (hasText) { ctl.copyText(selectedText()); ctl.close(); }
        else exportSel(true, true, false);
    }

    Timer {
        id: toastTimer
        interval: 2200
        onTriggered: win.toast = ""
    }

    // ── разбор снимка в фоне
    Process {
        running: true
        command: ["python3", Quickshell.shellDir + "/scripts/shot-analyze.py", "objects", win.src]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.objects = d.objects ?? [];
                    win.codes = d.codes ?? [];
                } catch (e) {}
            }
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

    // ═════════════════════════ то, что попадает в картинку
    Item {
        id: scene
        anchors.fill: parent

        // копия снимка для пипетки — под снимком, не видна
        Canvas {
            id: pix
            anchors.fill: parent
            readonly property string url: "file://" + win.src + "?" + win.ctl.stamp
            Component.onCompleted: loadImage(url)
            onImageLoaded: requestPaint()
            onPaint: if (isImageLoaded(url)) getContext("2d").drawImage(url, 0, 0, width, height)
        }

        Image {
            id: shot
            anchors.fill: parent
            source: "file://" + win.src + "?" + win.ctl.stamp
            cache: false
            smooth: true
        }

        // размытие: крупные пиксели
        Repeater {
            model: win.shapes.concat(win.draft ? [win.draft] : []).filter(s => s.t === "blur")

            Item {
                required property var modelData
                x: Math.min(modelData.x1, modelData.x2)
                y: Math.min(modelData.y1, modelData.y2)
                width: Math.abs(modelData.x2 - modelData.x1)
                height: Math.abs(modelData.y2 - modelData.y1)
                clip: true

                ShaderEffectSource {
                    anchors.fill: parent
                    sourceItem: shot
                    sourceRect: Qt.rect(parent.x, parent.y, parent.width, parent.height)
                    textureSize: Qt.size(Math.max(1, Math.round(parent.width / 9)), Math.max(1, Math.round(parent.height / 9)))
                    smooth: false
                }
            }
        }

        Canvas {
            id: inkCanvas
            anchors.fill: parent

            Connections {
                target: win
                function onShapesChanged() { inkCanvas.requestPaint(); }
                function onDraftChanged() { inkCanvas.requestPaint(); }
            }

            function arrow(ctx, s) {
                const w = 4, dx = s.x2 - s.x1, dy = s.y2 - s.y1;
                const a = Math.atan2(dy, dx), head = 18;
                ctx.lineWidth = w;
                ctx.beginPath();
                ctx.moveTo(s.x1, s.y1);
                ctx.lineTo(s.x2 - Math.cos(a) * head * 0.6, s.y2 - Math.sin(a) * head * 0.6);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(s.x2, s.y2);
                ctx.lineTo(s.x2 - head * Math.cos(a - 0.45), s.y2 - head * Math.sin(a - 0.45));
                ctx.lineTo(s.x2 - head * Math.cos(a + 0.45), s.y2 - head * Math.sin(a + 0.45));
                ctx.closePath();
                ctx.fill();
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                for (const s of win.shapes.concat(win.draft ? [win.draft] : [])) {
                    if (s.t === "blur") continue;
                    ctx.globalAlpha = 1;
                    ctx.strokeStyle = s.c;
                    ctx.fillStyle = s.c;
                    if (s.t === "arrow") arrow(ctx, s);
                    else if (s.t === "rect") {
                        ctx.lineWidth = 3;
                        ctx.strokeRect(Math.min(s.x1, s.x2), Math.min(s.y1, s.y2), Math.abs(s.x2 - s.x1), Math.abs(s.y2 - s.y1));
                    } else if (s.t === "pen" || s.t === "marker") {
                        ctx.lineWidth = s.t === "pen" ? 3 : 18;
                        ctx.globalAlpha = s.t === "pen" ? 1 : 0.35;
                        ctx.beginPath();
                        s.pts.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1]));
                        ctx.stroke();
                    } else if (s.t === "num") {
                        ctx.beginPath();
                        ctx.arc(s.x, s.y, 15, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.fillStyle = s.c === "#ffffff" ? "#151515" : "#ffffff";
                        ctx.font = `bold 16px '${Theme.font}'`;
                        ctx.textAlign = "center";
                        ctx.textBaseline = "middle";
                        ctx.fillText(String(s.n), s.x, s.y + 1);
                    } else if (s.t === "text") {
                        ctx.font = `bold 22px '${Theme.font}'`;
                        ctx.textAlign = "left";
                        ctx.textBaseline = "middle";
                        ctx.lineWidth = 4;
                        ctx.strokeStyle = "rgba(0,0,0,0.55)";
                        ctx.strokeText(s.text, s.x, s.y);
                        ctx.fillText(s.text, s.x, s.y);
                    }
                }
            }
        }
    }

    // ═════════════════════════ интерфейс поверх
    // затемнение вокруг выделения
    Item {
        anchors.fill: parent
        readonly property rect r: win.hasSel ? win.sel : Qt.rect(0, 0, 0, 0)
        readonly property real a: win.hasSel ? 0.5 : 0.22
        Rectangle { x: 0; y: 0; width: parent.width; height: parent.r.y; color: "black"; opacity: parent.a }
        Rectangle { x: 0; y: parent.r.y + parent.r.height; width: parent.width; height: parent.height - y; color: "black"; opacity: parent.a }
        Rectangle { x: 0; y: parent.r.y; width: parent.r.x; height: parent.r.height; color: "black"; opacity: parent.a }
        Rectangle { x: parent.r.x + parent.r.width; y: parent.r.y; width: parent.width - x; height: parent.r.height; color: "black"; opacity: parent.a }
    }

    // что выделит клик
    Rectangle {
        visible: win.tool === "select" && !win.hasSel && !win.hasText && area.containsMouse && !area.pressed && win.hover.width < win.width
        x: win.hover.x; y: win.hover.y; width: win.hover.width; height: win.hover.height
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
        border.width: 1
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.8)
        radius: 6
    }

    // выделенные слова
    Repeater {
        model: win.hasText ? win.tHi - win.tLo + 1 : 0

        Rectangle {
            required property int index
            readonly property rect r: win.wordRect(win.tLo + index)
            x: r.x - 2; y: r.y - 2; width: r.width + 4; height: r.height + 4
            radius: 4
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
        }
    }

    // QR и штрихкоды: метка с текстом, клик — скопировать, Ctrl+клик — открыть ссылку
    Repeater {
        model: win.codes

        Rectangle {
            required property var modelData
            x: modelData.x / win.k
            y: (modelData.y + modelData.h) / win.k + 6
            width: Math.min(320, codeRow.implicitWidth + 16)
            height: 28
            radius: 8
            color: codeArea.containsMouse ? Theme.accent : Theme.surface
            border.width: 1
            border.color: Theme.accent

            Row {
                id: codeRow
                anchors.verticalCenter: parent.verticalCenter
                x: 8
                spacing: 6
                Text {
                    text: String.fromCodePoint(0xF0432)
                    color: codeArea.containsMouse ? Theme.bg : Theme.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize
                }
                Text {
                    width: Math.min(implicitWidth, 270)
                    elide: Text.ElideRight
                    text: parent.parent.modelData.text
                    color: codeArea.containsMouse ? Theme.bg : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
            MouseArea {
                id: codeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    const t = parent.modelData.text;
                    if ((mouse.modifiers & Qt.ControlModifier) && /^\w+:\/\//.test(t)) Quickshell.execDetached(["xdg-open", t]);
                    else win.ctl.copyText(t);
                    win.ctl.close();
                }
            }
        }
    }

    // рамка выделения, размер, ручки
    Rectangle {
        id: frame
        visible: win.hasSel
        x: win.sel.x; y: win.sel.y; width: win.sel.width; height: win.sel.height
        color: "transparent"
        border.width: 2
        border.color: Theme.accent

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.top
            anchors.bottomMargin: 8
            visible: parent.y > 36
            width: sizeText.implicitWidth + 16
            height: 24
            radius: 7
            color: Theme.surface
            border.width: 1
            border.color: Theme.line

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

    // линейка
    Item {
        visible: !!win.ruler
        anchors.fill: parent
        readonly property var r: win.ruler ?? { x1: 0, y1: 0, x2: 0, y2: 0 }
        readonly property real len: Math.hypot((r.x2 - r.x1) * win.k, (r.y2 - r.y1) * win.k)

        Canvas {
            anchors.fill: parent
            readonly property var r: parent.r
            onRChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = String(Theme.accent);
                ctx.lineWidth = 2;
                ctx.setLineDash([6, 4]);
                ctx.beginPath();
                ctx.moveTo(r.x1, r.y1);
                ctx.lineTo(r.x2, r.y2);
                ctx.stroke();
                ctx.setLineDash([]);
                ctx.fillStyle = String(Theme.accent);
                for (const p of [[r.x1, r.y1], [r.x2, r.y2]]) { ctx.beginPath(); ctx.arc(p[0], p[1], 4, 0, Math.PI * 2); ctx.fill(); }
            }
        }
        Rectangle {
            x: (parent.r.x1 + parent.r.x2) / 2 + 12
            y: (parent.r.y1 + parent.r.y2) / 2 - height - 6
            width: rulerText.implicitWidth + 16
            height: 26
            radius: 8
            color: Theme.surface
            border.width: 1
            border.color: Theme.accent
            Text {
                id: rulerText
                anchors.centerIn: parent
                text: `${Math.round(parent.parent.len)} px   ·   ${Math.round(Math.abs(parent.parent.r.x2 - parent.parent.r.x1) * win.k)} × ${Math.round(Math.abs(parent.parent.r.y2 - parent.parent.r.y1) * win.k)}`
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    // ── мышь
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: {
            if (win.tool === "select") return pressed && mode === "text" ? Qt.IBeamCursor
                : !pressed && win.wordAt(mouseX, mouseY) >= 0 ? Qt.IBeamCursor : Qt.CrossCursor;
            if (win.tool === "text") return Qt.IBeamCursor;
            return Qt.CrossCursor;
        }

        property point p0
        property string mode: ""     // region | text | draw
        property bool moved: false

        onPositionChanged: mouse => {
            win.mouse = Qt.point(mouse.x, mouse.y);
            if (!pressed) {
                if (win.tool === "select") win.hover = win.candidateAt(mouse.x, mouse.y);
                return;
            }
            if (!moved && Math.abs(mouse.x - p0.x) + Math.abs(mouse.y - p0.y) < 4) return;
            moved = true;
            win.ctl.current = win;
            if (mode === "text") {
                win.tB = win.nearestWord(mouse.x, mouse.y);
            } else if (mode === "region") {
                win.sel = Qt.rect(Math.min(p0.x, mouse.x), Math.min(p0.y, mouse.y), Math.abs(mouse.x - p0.x), Math.abs(mouse.y - p0.y));
            } else if (mode === "draw" && win.draft) {
                const d = Object.assign({}, win.draft);
                if (d.pts) d.pts = d.pts.concat([[mouse.x, mouse.y]]);
                else { d.x2 = mouse.x; d.y2 = mouse.y; }
                if (win.tool === "ruler") win.ruler = d;
                else win.draft = d;
            }
        }
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) return;
            win.commitText();
            win.translation = null;
            p0 = Qt.point(mouse.x, mouse.y);
            moved = false;
            const t = win.tool;
            if (t === "select") {
                const w = (mouse.modifiers & Qt.AltModifier) ? -1 : win.wordAt(mouse.x, mouse.y);
                mode = w >= 0 ? "text" : "region";
                if (mode === "text") {
                    win.sel = Qt.rect(0, 0, 0, 0);
                    win.tA = w;
                    win.tB = w;
                } else {
                    win.tA = win.tB = -1;
                }
                return;
            }
            mode = "draw";
            if (t === "pen" || t === "marker") win.draft = { t, pts: [[mouse.x, mouse.y]], c: String(win.ink) };
            else if (t === "ruler") { win.draft = { t, x1: mouse.x, y1: mouse.y, x2: mouse.x, y2: mouse.y }; win.ruler = win.draft; }
            else if (t === "arrow" || t === "rect" || t === "blur") win.draft = { t, x1: mouse.x, y1: mouse.y, x2: mouse.x, y2: mouse.y, c: String(win.ink) };
            else win.draft = null;
        }
        onReleased: mouse => {
            if (mouse.button === Qt.RightButton) {
                // ПКМ: снять выделение / вернуться к выделению; без них — закрыть
                if (win.tool !== "select") win.setTool("select");
                else if (win.hasSel || win.hasText) { win.sel = Qt.rect(0, 0, 0, 0); win.tA = win.tB = -1; }
                else win.ctl.close();
                return;
            }
            const t = win.tool;
            if (t === "select") {
                if (moved) return;
                // клик — выделить по границам того, что под курсором
                win.tA = win.tB = -1;
                win.sel = win.candidateAt(mouse.x, mouse.y);
                win.ctl.current = win;
            } else if (t === "num") {
                win.addShape({ t, x: mouse.x, y: mouse.y, n: win.numNext++, c: String(win.ink) });
            } else if (t === "text") {
                win.startText(mouse.x, mouse.y);
            } else if (t === "picker") {
                const hex = win.hexAt(mouse.x, mouse.y);
                if (hex) {
                    Quickshell.execDetached(["wl-copy", hex]);
                    win.say(`${I18n.tr("Copied")}: ${hex}`);
                }
            } else if (t === "ruler") {
                win.draft = null;
            } else if (win.draft) {
                const d = win.draft;
                win.draft = null;
                if (d.pts ? d.pts.length > 1 : Math.abs(d.x2 - d.x1) + Math.abs(d.y2 - d.y1) > 6) win.addShape(d);
            }
        }
        onDoubleClicked: mouse => {
            if (win.tool !== "select") return;
            const w = win.wordAt(mouse.x, mouse.y);
            if (w >= 0) win.selectLine(w);
        }
        onExited: win.mouse = Qt.point(-100, -100)
    }

    // ручки: потянуть край или угол выделения
    Repeater {
        model: win.tool === "select" && win.hasSel ? [[0, 0], [0.5, 0], [1, 0], [1, 0.5], [1, 1], [0.5, 1], [0, 1], [0, 0.5]] : []

        Rectangle {
            id: handle
            required property var modelData
            readonly property real fx: modelData[0]
            readonly property real fy: modelData[1]
            x: win.sel.x + win.sel.width * fx - width / 2
            y: win.sel.y + win.sel.height * fy - height / 2
            width: 12
            height: 12
            radius: 3
            color: Theme.accent
            border.width: 2
            border.color: Theme.bg

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: handle.fx === 0.5 ? Qt.SizeVerCursor : handle.fy === 0.5 ? Qt.SizeHorCursor
                    : (handle.fx === handle.fy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor)
                onPositionChanged: mouse => {
                    if (!pressed) return;
                    const p = mapToItem(null, mouse.x, mouse.y);
                    win.mouse = p;
                    let x1 = win.sel.x, y1 = win.sel.y, x2 = x1 + win.sel.width, y2 = y1 + win.sel.height;
                    if (handle.fx === 0) x1 = p.x; else if (handle.fx === 1) x2 = p.x;
                    if (handle.fy === 0) y1 = p.y; else if (handle.fy === 1) y2 = p.y;
                    win.sel = Qt.rect(Math.min(x1, x2), Math.min(y1, y2), Math.abs(x2 - x1), Math.abs(y2 - y1));
                }
            }
        }
    }

    // ввод текста на картинку
    TextInput {
        id: editor
        visible: false
        color: win.ink
        font.family: Theme.font
        font.pixelSize: 22
        font.bold: true
        cursorVisible: true
        Keys.onReturnPressed: win.commitText()
        Keys.onEscapePressed: { visible = false; keys.forceActiveFocus(); }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            z: -1
            color: "transparent"
            radius: 4
            border.width: 1
            border.color: Theme.accent
        }
    }

    // лупа: пиксели под курсором и их цвет
    Rectangle {
        id: loupe
        readonly property bool want: (win.tool === "picker" || win.tool === "ruler" || (area.pressed && area.mode === "region"))
            && win.mouse.x >= 0
        visible: want
        width: 132
        height: 156
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
        x: win.mouse.x + 24 + width < win.width ? win.mouse.x + 24 : win.mouse.x - width - 24
        y: win.mouse.y + 24 + height < win.height ? win.mouse.y + 24 : win.mouse.y - height - 24

        Item {
            id: zoom
            x: 6; y: 6
            width: 120; height: 120
            clip: true
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: shot
                sourceRect: Qt.rect(win.mouse.x - 7.5, win.mouse.y - 7.5, 15, 15)
                smooth: false
                live: true
            }
            // центральный пиксель
            Rectangle {
                anchors.centerIn: parent
                width: 9; height: 9
                color: "transparent"
                border.width: 1
                border.color: "white"
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7
            spacing: 6
            readonly property string hex: loupe.visible ? win.hexAt(win.mouse.x, win.mouse.y) : ""
            Rectangle {
                width: 14; height: 14; radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: parent.hex || "transparent"
                border.width: 1
                border.color: Theme.line
            }
            Text {
                text: `${parent.hex}  ${Math.round(win.mouse.x * win.k)},${Math.round(win.mouse.y * win.k)}`
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }

    // ── действия у выделения
    Rectangle {
        id: actionsCard
        visible: (win.hasSel || win.hasText) && !area.pressed && !editor.visible
        readonly property rect anchorRect: win.hasSel ? win.sel : (win.hasText ? (() => {
            const a = win.wordRect(win.tLo), b = win.wordRect(win.tHi);
            const x0 = Math.min(a.x, b.x), y0 = Math.min(a.y, b.y);
            return Qt.rect(x0, y0, Math.max(a.x + a.width, b.x + b.width) - x0, Math.max(a.y + a.height, b.y + b.height) - y0);
        })() : Qt.rect(0, 0, 0, 0))
        readonly property bool below: anchorRect.y + anchorRect.height + 12 + height < win.height - 70
        x: Math.max(8, Math.min(win.width - width - 8, anchorRect.x + anchorRect.width - width))
        y: below ? anchorRect.y + anchorRect.height + 12
           : anchorRect.y - height - 12 > 8 ? anchorRect.y - height - 12 : anchorRect.y + 12
        width: acts.implicitWidth + 12
        height: 46
        radius: 14
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        RowLayout {
            id: acts
            anchors.centerIn: parent
            spacing: 2

            // текст
            ToolButton { visible: win.hasText; icon: 0xF018F; label: "Copy text"; key: "Enter"; active: true; onClicked: win.primary() }
            ToolButton { visible: win.hasText; icon: 0xF05CA; tip: "Translate"; key: "T"; onClicked: win.translate(win.selectedText()) }
            // картинка
            ToolButton { visible: !win.hasText; icon: 0xF018F; label: "Copy"; key: "Enter"; active: true; onClicked: win.exportSel(true, true, false) }
            ToolButton { visible: !win.hasText; icon: 0xF0193; tip: "Save"; key: "Ctrl+S"; onClicked: win.exportSel(false, true, false) }
            ToolButton { visible: !win.hasText; icon: 0xF0403; tip: "Pin on screen"; key: "Ctrl+P"; onClicked: win.exportSel(false, false, true) }
            ToolButton { visible: !win.hasText; icon: 0xF113D; tip: win.ocrDone ? "Copy text from the area" : "Recognizing text…"; key: "T"; off: !win.ocrDone
                onClicked: { win.ctl.copyText(win.textInSel()); win.ctl.close(); } }
            ToolButton { visible: !win.hasText; icon: 0xF05CA; tip: "Translate text in the area"; off: !win.ocrDone; onClicked: win.translate(win.textInSel()) }
            ToolButton { visible: !win.hasText; icon: 0xF0209; tip: "Hide private data"; key: "D"; off: !win.ocrDone; onClicked: win.hideSensitive() }
            ToolButton { visible: !win.hasText; icon: 0xF0BBE; tip: "Long screenshot (scroll)"; key: "L"; onClicked: win.startLong() }
        }
    }

    // перевод: под действиями; длинный — прокручивается
    Rectangle {
        visible: !!win.translation
        width: Math.min(620, win.width - 32)
        height: Math.min(trCol.implicitHeight + 24, win.height * 0.5)
        x: Math.max(16, Math.min(win.width - width - 16, actionsCard.x + actionsCard.width - width))
        y: actionsCard.below ? Math.min(win.height - height - 80, actionsCard.y + actionsCard.height + 8)
           : Math.max(16, actionsCard.y - height - 8)
        radius: 14
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: trText.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Text {
                    id: trText
                    width: parent.width
                    text: win.translation?.busy ? I18n.tr("Translating…") : (win.translation?.text ?? "")
                    wrapMode: Text.Wrap
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
            }
            RowLayout {
                spacing: 4
                ToolButton {
                    icon: 0xF018F
                    label: "Copy"
                    off: win.translation?.busy ?? true
                    onClicked: { win.ctl.copyText(win.translation.text); win.ctl.close(); }
                }
                ToolButton { icon: 0xF0156; tip: "Close"; onClicked: win.translation = null }
            }
        }
        // высота по содержимому: колонка без Flickable
        ColumnLayout {
            id: trCol
            visible: false
            width: parent.width - 24
            Text { Layout.fillWidth: true; text: trText.text; wrapMode: Text.Wrap; font: trText.font }
            Item { implicitHeight: 42 }
        }
    }

    // ── панель инструментов внизу
    Rectangle {
        id: toolbar
        visible: win.focused
        anchors.horizontalCenter: parent.horizontalCenter
        // выделение у нижнего края — панель наверх
        readonly property bool atTop: win.hasSel && win.sel.y + win.sel.height > win.height - 90
        y: atTop ? 16 : win.height - height - 22
        width: tb.implicitWidth + 16
        height: 50
        radius: 16
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        RowLayout {
            id: tb
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: win.tools
                ToolButton {
                    required property var modelData
                    icon: modelData.icon
                    tip: modelData.tip
                    key: modelData.key
                    active: win.tool === modelData.id
                    onClicked: win.setTool(modelData.id)
                }
            }

            Rectangle { implicitWidth: 1; implicitHeight: 24; color: Theme.line; Layout.leftMargin: 6; Layout.rightMargin: 6 }

            // цвет рисунков
            Repeater {
                model: win.inks
                Rectangle {
                    required property var modelData
                    required property int index
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: 13
                    color: "transparent"
                    border.width: 2
                    border.color: win.colorIdx === index ? Theme.fg : "transparent"
                    Rectangle {
                        anchors.centerIn: parent
                        width: 16; height: 16; radius: 8
                        color: parent.modelData
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.colorIdx = parent.index
                    }
                }
            }

            Rectangle { implicitWidth: 1; implicitHeight: 24; color: Theme.line; Layout.leftMargin: 6; Layout.rightMargin: 6 }

            ToolButton { icon: 0xF054C; tip: "Undo"; key: "Ctrl+Z"; off: !win.shapes.length; onClicked: win.undo() }
            ToolButton { icon: 0xF0293; tip: "Whole screen"; key: "F"; onClicked: win.fullScreen() }
            ToolButton { icon: 0xF051B; tip: "Timer 3 s"; key: "Shift+Print"; onClicked: win.ctl.startIn(3) }
            ToolButton { icon: 0xF02DA; tip: "History"; key: "Ctrl+H"; onClicked: { win.ctl.close(); win.ctl.historyOpen = true; } }
            ToolButton { icon: 0xF0156; tip: "Close"; key: "Esc"; onClicked: win.ctl.close() }
        }
    }

    // ── подсказка сверху
    Rectangle {
        visible: win.focused && !toolbar.atTop
        anchors.horizontalCenter: parent.horizontalCenter
        y: 16
        width: hint.implicitWidth + 28
        height: 34
        radius: 11
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        Row {
            id: hint
            anchors.centerIn: parent
            spacing: 10

            Text {
                visible: !win.ocrDone || win.toast !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: win.toast !== "" ? String.fromCodePoint(0xF012C) : String.fromCodePoint(0xF113D)
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.iconSize
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.toast !== "" ? win.toast
                    : !win.ocrDone ? I18n.tr("Recognizing text…")
                    : ({
                        select: "Drag — area   ·   click — by edges   ·   drag over text — select it",
                        arrow: "Drag to draw an arrow", rect: "Drag to draw a rectangle", pen: "Draw freely",
                        marker: "Highlight with a marker", text: "Click to type, Enter — done",
                        num: "Click to put numbers 1, 2, 3…", blur: "Drag over what to hide",
                        ruler: "Drag to measure", picker: "Click to copy the color",
                    })[win.tool].split("   ·   ").map(s => I18n.tr(s)).join("   ·   ")
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    // ── клавиатура
    Item {
        id: keys
        anchors.fill: parent
        focus: win.focused
        Component.onCompleted: if (win.focused) forceActiveFocus()
        Keys.onPressed: event => {
            const w = win.ctl.current ?? win;
            const ctrl = event.modifiers & Qt.ControlModifier;
            const k = event.key;
            const tools = { [Qt.Key_V]: "select", [Qt.Key_A]: "arrow", [Qt.Key_R]: "rect", [Qt.Key_P]: "pen", [Qt.Key_H]: "marker",
                            [Qt.Key_X]: "text", [Qt.Key_N]: "num", [Qt.Key_B]: "blur", [Qt.Key_U]: "ruler", [Qt.Key_C]: "picker" };
            if (k === Qt.Key_Escape) win.ctl.close();
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || (ctrl && k === Qt.Key_C)) w.primary();
            else if (ctrl && k === Qt.Key_S) w.exportSel(false, true, false);
            else if (ctrl && k === Qt.Key_P) w.exportSel(false, false, true);
            else if (ctrl && k === Qt.Key_Z) w.undo();
            else if (ctrl && k === Qt.Key_A) w.selectAllText();
            else if (ctrl && k === Qt.Key_H) { win.ctl.close(); win.ctl.historyOpen = true; }
            else if (ctrl) return;
            else if (k === Qt.Key_F) w.fullScreen();
            else if (k === Qt.Key_T) {
                if (w.hasText) w.translate(w.selectedText());
                else if (w.ocrDone) { win.ctl.copyText(w.textInSel()); win.ctl.close(); }
            }
            else if (k === Qt.Key_D && w.ocrDone) w.hideSensitive();
            else if (k === Qt.Key_L) w.startLong();
            else if (k >= Qt.Key_1 && k <= Qt.Key_5) win.colorIdx = k - Qt.Key_1;
            else if (tools[k] !== undefined) win.setTool(tools[k]);
            else return;
            event.accepted = true;
        }
    }
}
