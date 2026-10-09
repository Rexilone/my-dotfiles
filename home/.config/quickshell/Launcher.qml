import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.services
import qs.modules

// запуск приложений (Super+D, qs ipc call launcher toggle).
// Сверху закреплённые (Ctrl+P, Ctrl+1…9), ниже результаты по группам: приложения, калькулятор,
// разделы настроек, системные действия, поиск в интернете. «>» — команда в терминале,
// «?» — поиск в интернете, «→» — действия приложения («Новое окно» и т. п.)
PanelWindow {
    id: root

    property bool open: false
    property bool shown: false
    property string query: ""
    property var actionsFor: null        // приложение, чьи действия сейчас показаны
    property string toast: ""            // короткое сообщение в строке подсказок

    readonly property int rowHeight: 50
    readonly property int maxListHeight: 430

    // ru -> en раскладка: «ашкуащч» находит firefox
    readonly property string ruKeys: "йцукенгшщзхъфывапролджэячсмитьбю"
    readonly property string enKeys: "qwertyuiop[]asdfghjkl;'zxcvbnm,."

    readonly property var apps: {
        const seen = {};
        return DesktopEntries.applications.values.filter(e => {
            if (e.noDisplay || seen[e.id]) return false;
            seen[e.id] = true;
            return true;
        });
    }

    readonly property var pinned: (usage.pinned ?? []).map(id => apps.find(e => e.id === id)).filter(e => e)

    // системные действия: находятся по словам
    readonly property var systemActions: [
        { label: "Lock screen", keys: "lock screen", icon: 0xF033E, cmd: ["qs", "ipc", "call", "idle", "lock"] },
        { label: "Sleep", keys: "sleep suspend", icon: 0xF0904, cmd: ["systemctl", "suspend"] },
        { label: "Power menu", keys: "power shutdown reboot restart logout turn off", icon: 0xF0425, cmd: ["qs", "ipc", "call", "power", "toggle"] },
        { label: "Record screen", keys: "record video screen capture", icon: 0xF044A, cmd: ["qs", "ipc", "call", "recorder", "toggle"] },
        { label: "Wallpapers", keys: "wallpaper background", icon: 0xF0E09, cmd: ["qs", "ipc", "call", "wallpaper", "toggle"] },
        { label: "Clipboard history", keys: "clipboard paste copy history", icon: 0xF014C, cmd: ["qs", "ipc", "call", "clipboard", "toggle"] },
        { label: "Settings", keys: "settings preferences control panel", icon: 0xF0493, cmd: ["qs", "ipc", "call", "settings", "open"] },
        { label: "Do not disturb", keys: "dnd do not disturb notifications quiet", icon: 0xF009B, fn: () => Notifs.toggleDnd() },
        { label: "Dark / light theme", keys: "dark light theme mode", icon: 0xF0594, fn: () => Ui.toggleDark() },
    ]

    function translit(q) {
        return [...q].map(c => {
            const i = ruKeys.indexOf(c);
            return i >= 0 ? enKeys[i] : c;
        }).join("");
    }

    function score(e, q) {
        const name = e.name.toLowerCase();
        if (name === q) return 1000;
        if (name.startsWith(q)) return 800;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 600;
        if (name.includes(q)) return 400;
        const extra = [e.genericName, e.comment, e.id, ...(e.keywords ?? [])].join(" ").toLowerCase();
        if (extra.includes(q)) return 200;
        let i = 0;
        for (const c of name) if (c === q[i]) i++;
        return i === q.length ? 100 : -1;
    }

    // калькулятор: только цифры, скобки и операторы
    function calc(q) {
        let s = q.replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, "/").replace(/\s+/g, "");
        if (!/^[\d+\-*/%().^]+$/.test(s) || !/\d[+\-*/%^]|\)[+\-*/%^]|^-?\(/.test(s)) return null;
        s = s.replace(/\^/g, "**");
        try {
            const v = Function(`"use strict"; return (${s});`)();
            if (typeof v !== "number" || !isFinite(v)) return null;
            return String(Number(v.toPrecision(12)));
        } catch (e) {
            return null;
        }
    }

    function appItem(e, group) {
        return { type: "app", group, entry: e, label: e.name, sub: e.genericName || e.comment || "" };
    }

    readonly property var items: {
        const q = query.trim().toLowerCase();
        const raw = query.trim();
        const counts = usage.counts ?? {};

        // действия приложения
        if (actionsFor) {
            return (actionsFor.actions ?? []).map(a => ({
                type: "daction", group: actionsFor.name, label: a.name, sub: "", action: a, entry: actionsFor,
            }));
        }
        // «> команда» — в терминале
        if (raw.startsWith(">")) {
            const cmd = raw.slice(1).trim();
            return [{ type: "run", group: "Run", label: cmd || "Type a command…", sub: "Runs in a terminal, stays open", cmd, glyph: 0xF018D }];
        }
        // «? запрос» — в интернете
        if (raw.startsWith("?")) {
            const t = raw.slice(1).trim();
            return [{ type: "web", group: "Web", label: t ? `${I18n.tr("Search")} “${t}”` : "Type what to search…", sub: "Google", text: t, glyph: 0xF059F }];
        }

        // пусто: часто используемые, затем все
        if (!q) {
            const freq = apps.filter(e => (counts[e.id] ?? 0) > 0)
                .sort((a, b) => (counts[b.id] ?? 0) - (counts[a.id] ?? 0))
                .slice(0, 6);
            const rest = apps.filter(e => !freq.includes(e)).sort((a, b) => a.name.localeCompare(b.name));
            return freq.map(e => appItem(e, "Frequent")).concat(rest.map(e => appItem(e, "All apps")));
        }

        const out = [];
        const v = calc(raw.startsWith("=") ? raw.slice(1) : raw);
        if (v !== null) out.push({ type: "calc", group: "Calculator", label: v, sub: `${raw.replace(/^=/, "")}   ·   Enter copies the result`, value: v, glyph: 0xF00EC });

        const alt = translit(q);
        const found = apps.map(e => {
            const s = Math.max(score(e, q), alt !== q ? score(e, alt) - 1 : -1);
            return { e, s: s < 0 ? s : s + Math.min(counts[e.id] ?? 0, 50) * 4 };
        }).filter(r => r.s >= 0)
          .sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name))
          .map(r => appItem(r.e, "Apps"));
        out.push(...found);

        const words = [q, alt];
        const hit = text => words.some(w => text.toLowerCase().includes(w));
        out.push(...Ui.settingsPages
            .filter(p => (!p.dev || Settings.developerMode) && hit(`${p.name} ${p.keys}`))
            .slice(0, 4)
            .map(p => ({ type: "setting", group: "Settings", label: p.name, sub: "Open in Settings", page: p.name, glyph: p.icon2 })));

        out.push(...systemActions.filter(a => hit(`${a.label} ${a.keys}`))
            .map(a => ({ type: "system", group: "System", label: a.label, sub: "", act: a, glyph: a.icon })));

        out.push({ type: "web", group: "Web", label: `${I18n.tr("Search")} “${raw}”`, sub: "Google", text: raw, glyph: 0xF059F });
        return out;
    }

    function run(it) {
        if (!it) return;
        switch (it.type) {
        case "app":
            launchApp(it.entry);
            return;
        case "daction":
            it.action.execute();
            bump(it.entry);
            close();
            return;
        case "calc":
            Quickshell.execDetached(["wl-copy", it.value]);
            flash(`${I18n.tr("Copied")} ${it.value}`);
            return;
        case "run":
            if (!it.cmd) return;
            Quickshell.execDetached(["foot", "--hold", "sh", "-c", it.cmd]);
            close();
            return;
        case "web":
            if (!it.text) return;
            Qt.openUrlExternally("https://www.google.com/search?q=" + encodeURIComponent(it.text));
            close();
            return;
        case "setting":
            close();
            Quickshell.execDetached(["qs", "ipc", "call", "settings", "page", it.page]);
            return;
        case "system":
            close();
            if (it.act.fn) it.act.fn();
            else Ui.afterClose(it.act.cmd, 0.25);
            return;
        }
    }

    function launchApp(e) {
        if (!e) return;
        if (e.runInTerminal)
            Quickshell.execDetached({ command: ["foot", ...e.command], workingDirectory: e.workingDirectory || Quickshell.env("HOME") });
        else
            e.execute();
        bump(e);
        close();
    }

    function bump(e) {
        const counts = Object.assign({}, usage.counts ?? {});
        counts[e.id] = (counts[e.id] ?? 0) + 1;
        usage.counts = counts;
    }

    function togglePin(e) {
        if (!e) return;
        const p = (usage.pinned ?? []).slice();
        const i = p.indexOf(e.id);
        if (i >= 0) p.splice(i, 1);
        else p.push(e.id);
        usage.pinned = p;
        flash(I18n.ru ? `${i >= 0 ? "Откреплено" : "Закреплено"}: ${e.name}` : i >= 0 ? `Unpinned ${e.name}` : `Pinned ${e.name}`);
    }

    function flash(text) {
        toast = text;
        toastTimer.restart();
    }

    function showActions(it) {
        if (it?.type === "app" && (it.entry.actions ?? []).length) {
            actionsFor = it.entry;
            list.currentIndex = 0;
        }
    }

    function close() {
        open = false;
    }

    Timer {
        id: toastTimer
        interval: 1800
        onTriggered: root.toast = ""
    }

    onOpenChanged: {
        if (open) {
            targetScreen = Settings.activeScreen();
            hideTimer.stop();
            query = "";
            actionsFor = null;
            toast = "";
            input.text = "";
            list.currentIndex = 0;
            list.positionViewAtBeginning();
            browsing = false;
            shown = true;
            input.forceActiveFocus();
        } else {
            hideTimer.restart();
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { root.open = !root.open; }
        function open(): void { root.open = true; }
        function hide(): void { root.open = false; }
    }

    // частота запусков и закреплённые
    Timer {
        id: saveTimer
        interval: 300
        onTriggered: usageFile.writeAdapter()
    }

    FileView {
        id: usageFile
        path: Quickshell.statePath("launcher.json")
        blockLoading: true
        printErrors: false
        // запись с задержкой одним вызовом: запись на каждое поле теряет значения
        onAdapterUpdated: saveTimer.restart()

        JsonAdapter {
            id: usage
            property var counts: ({})
            property var pinned: ([])
        }
    }

    Timer {
        id: hideTimer
        interval: Theme.animSlow
        onTriggered: root.shown = false
    }

    // открывается на мониторе, где сейчас курсор/фокус
    property var targetScreen: Settings.activeScreen()
    screen: targetScreen
    visible: shown
    color: "transparent"
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    // размытие только под карточкой (Персонализация → Прозрачность)
    BackgroundEffect.blurRegion: Theme.blurOn ? blurReg : null
    Region {
        id: blurReg
        item: card
        radius: card.radius
    }
    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // затемнение фона, клик мимо закрывает
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.open ? 0.35 : 0

        Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // компактная строка: пусто — только поиск и закреплённые; результаты — под строкой
    property bool browsing: false   // ↓ на пустой строке — показать частые и все приложения
    readonly property bool expanded: query.trim() !== "" || browsing || !!actionsFor
    readonly property var current: items[list.currentIndex] ?? null
    readonly property int rowH: 46
    readonly property int maxRows: 8

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.24)
        width: 660
        height: bar.height + (root.expanded ? resultsBox.height : 0)
        radius: 16
        color: Theme.panel
        border.width: 1
        border.color: Theme.surfaceHi2
        clip: true

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.97
        transformOrigin: Item.Top

        Behavior on opacity { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        // ── строка поиска
        RowLayout {
            id: bar
            width: parent.width
            height: 58
            spacing: 12

            Item { implicitWidth: 6 }

            Text {
                text: root.actionsFor ? String.fromCodePoint(0xF0241)
                    : root.query.trim().startsWith(">") ? String.fromCodePoint(0xF018D)
                    : root.query.trim().startsWith("?") ? String.fromCodePoint(0xF059F)
                    : Icons.search
                color: input.text || root.actionsFor ? Theme.fg : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 4
            }

            Text {
                visible: !!root.actionsFor
                text: `${root.actionsFor?.name ?? ""}  ›`
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 3
            }

            TextInput {
                id: input

                // в режиме действий поле сжато, но видимо: иначе оно не получит клавиши
                Layout.fillWidth: !root.actionsFor
                Layout.maximumWidth: root.actionsFor ? 0 : 100000
                opacity: root.actionsFor ? 0 : 1
                color: Theme.fg
                selectionColor: Theme.surfaceHi2
                selectedTextColor: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 4
                clip: true
                focus: true

                onTextChanged: {
                    root.query = text;
                    if (!text) root.browsing = false;
                    list.currentIndex = 0;
                    list.positionViewAtBeginning();
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !input.text
                    text: I18n.tr("Type to search…")
                    color: Theme.dim
                    font: input.font
                }

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const cur = root.current;
                    const k = event.key;
                    if (k === Qt.Key_Escape) {
                        if (root.actionsFor) root.actionsFor = null;
                        else if (root.browsing) root.browsing = false;
                        else root.close();
                    } else if (!root.expanded && (k === Qt.Key_Down || k === Qt.Key_Tab)) {
                        root.browsing = true;
                    } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                        if (root.expanded) root.run(cur);
                        else if (root.pinned.length) root.launchApp(root.pinned[0]);
                    } else if (k === Qt.Key_Down || k === Qt.Key_Tab || (ctrl && k === Qt.Key_J)) {
                        list.incrementCurrentIndex();
                    } else if (k === Qt.Key_Up || k === Qt.Key_Backtab || (ctrl && k === Qt.Key_K)) {
                        if (root.browsing && !input.text && list.currentIndex === 0) root.browsing = false;
                        else list.decrementCurrentIndex();
                    } else if (k === Qt.Key_PageDown) {
                        list.currentIndex = Math.min(list.count - 1, list.currentIndex + root.maxRows);
                    } else if (k === Qt.Key_PageUp) {
                        list.currentIndex = Math.max(0, list.currentIndex - root.maxRows);
                    } else if (k === Qt.Key_Right && (root.actionsFor || input.cursorPosition === input.text.length) && cur?.type === "app" && root.expanded) {
                        root.showActions(cur);
                    } else if (k === Qt.Key_Left && root.actionsFor) {
                        root.actionsFor = null;
                    } else if (ctrl && k === Qt.Key_P && cur?.entry && root.expanded) {
                        root.togglePin(cur.entry);
                    } else if (ctrl && k >= Qt.Key_1 && k <= Qt.Key_9) {
                        root.launchApp(root.pinned[k - Qt.Key_1]);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }

            Item {
                Layout.fillWidth: true
                visible: !!root.actionsFor
            }

            // закреплённые — маленькие значки прямо в строке
            Row {
                visible: !root.expanded && root.pinned.length > 0
                spacing: 2

                Repeater {
                    model: root.pinned.slice(0, 6)

                    Rectangle {
                        id: pin
                        required property DesktopEntry modelData
                        width: 38
                        height: 38
                        radius: 10
                        color: pinArea.containsMouse ? Theme.surfaceHi2 : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        AppIcon {
                            anchors.centerIn: parent
                            implicitSize: 24
                            icon: pin.modelData.icon
                        }

                        MouseArea {
                            id: pinArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => mouse.button === Qt.RightButton ? root.togglePin(pin.modelData) : root.launchApp(pin.modelData)
                        }
                    }
                }
            }

            // подсказка, пока пусто
            Text {
                visible: !root.expanded && root.pinned.length === 0
                text: "↓"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            Item { implicitWidth: 6 }
        }

        // ── результаты под строкой
        Item {
            id: resultsBox
            y: bar.height
            width: parent.width
            height: (root.items.length ? Math.min(list.contentHeight, root.maxRows * root.rowH + 60) : 50) + 18
            visible: root.expanded

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.surfaceHi2
            }

            Text {
                anchors.centerIn: parent
                visible: root.items.length === 0
                text: I18n.tr(root.actionsFor ? "No actions" : "Nothing found")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            ListView {
                id: list
                x: 8
                y: 9
                width: parent.width - 16
                height: parent.height - 18
                clip: true
                model: root.expanded ? root.items : []
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 120
                highlightResizeDuration: 0
                highlightFollowsCurrentItem: true
                keyNavigationWraps: true
                currentIndex: 0

                highlight: Item {
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: list.currentItem ? list.currentItem.headerHeight : 0
                        radius: 10
                        color: Theme.surfaceHi
                    }
                }

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property bool cur: ListView.isCurrentItem
                    readonly property bool firstInGroup: index === 0 || root.items[index - 1]?.group !== modelData.group
                    readonly property int headerHeight: firstInGroup && index > 0 ? 26 : 0
                    readonly property bool hasActions: modelData.type === "app" && (modelData.entry.actions ?? []).length > 0

                    width: list.width
                    height: root.rowH + headerHeight

                    // разделитель групп — тонкая подпись
                    Text {
                        visible: row.headerHeight > 0
                        x: 14
                        y: 7
                        text: I18n.tr(row.modelData.group)
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: true
                    }

                    RowLayout {
                        y: row.headerHeight
                        width: parent.width
                        height: root.rowH
                        spacing: 12

                        Item { implicitWidth: 4 }

                        Item {
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26

                            AppIcon {
                                anchors.centerIn: parent
                                visible: row.modelData.type === "app" || row.modelData.type === "daction"
                                implicitSize: 24
                                icon: row.modelData.type === "daction" ? (row.modelData.action.icon || row.modelData.entry.icon) : (row.modelData.entry?.icon ?? "")
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !!row.modelData.glyph
                                text: row.modelData.glyph ? String.fromCodePoint(row.modelData.glyph) : ""
                                color: row.cur ? Theme.fg : Theme.muted
                                font.family: Theme.font
                                font.pixelSize: Theme.iconSize + 2
                            }
                        }

                        Text {
                            text: I18n.tr(row.modelData.label)
                            color: row.cur ? Theme.fg : Theme.muted
                            font.family: Theme.font
                            font.pixelSize: row.modelData.type === "calc" ? Theme.fontSize + 4 : Theme.fontSize + 1
                            font.bold: row.modelData.type === "calc"
                            elide: Text.ElideRight
                            Layout.maximumWidth: 330
                        }

                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr(row.modelData.type === "app" ? (row.modelData.entry.genericName || "") : row.modelData.sub)
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }

                        Text {
                            visible: row.modelData.type === "app" && (usage.pinned ?? []).includes(row.modelData.entry.id)
                            text: String.fromCodePoint(0xF0403)
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize - 3
                        }

                        Text {
                            visible: row.cur
                            text: row.hasActions && !root.actionsFor ? "→  ↵" : "↵"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }

                        Item { implicitWidth: 6 }
                    }

                    MouseArea {
                        y: row.headerHeight
                        width: parent.width
                        height: root.rowH
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onEntered: list.currentIndex = row.index
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (row.modelData.entry) root.togglePin(row.modelData.entry);
                            } else {
                                root.run(row.modelData);
                            }
                        }
                    }
                }
            }
        }

        // короткое сообщение («Скопировано», «Закреплено») — поверх строки справа
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: (bar.height - height) / 2
            visible: root.toast !== ""
            width: toastText.implicitWidth + 20
            height: 28
            radius: 8
            color: Theme.surfaceHi2

            Text {
                id: toastText
                anchors.centerIn: parent
                text: root.toast
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    onActionsForChanged: input.forceActiveFocus()
}
