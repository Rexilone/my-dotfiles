import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// Бинды: список из конфига niri + свои; смена клавиш, отключение, добавление
Page {
    id: page

    title: "Keyboard shortcuts"
    subtitle: "Change, turn off or add shortcuts. Changes apply instantly."

    readonly property string cfgPath: `${Quickshell.env("HOME")}/.config/niri/config.kdl`
    property var cfgBinds: []        // [{ line, key, props, action, enabled }]
    property string query: ""

    // захват сочетания
    property var capture: null       // { mode: "edit" | "new", target }
    property string captured: ""

    // готовые действия для новых биндов
    readonly property var actions: [
        { value: "custom", label: "Run a command…" },
        { value: 'spawn "qs" "ipc" "call" "launcher" "toggle";', label: "Shell · App launcher" },
        { value: 'spawn "qs" "ipc" "call" "clipboard" "toggle";', label: "Shell · Clipboard" },
        { value: 'spawn "qs" "ipc" "call" "settings" "toggle";', label: "Shell · Settings" },
        { value: 'spawn "qs" "ipc" "call" "wallpaper" "toggle";', label: "Shell · Wallpapers" },
        { value: 'spawn "qs" "ipc" "call" "wallpaper" "random";', label: "Shell · Random wallpaper" },
        { value: 'spawn "qs" "ipc" "call" "power" "toggle";', label: "Shell · Power menu" },
        { value: 'spawn "qs" "ipc" "call" "recorder" "toggle";', label: "Shell · Screen recorder" },
        { value: 'spawn "qs" "ipc" "call" "recorder" "record";', label: "Shell · Start/stop recording" },
        { value: 'spawn "qs" "ipc" "call" "recorder" "saveReplay";', label: "Shell · Save replay" },
        { value: 'spawn "qs" "ipc" "call" "idle" "caffeine";', label: "Shell · Keep awake on/off" },
        { value: 'spawn "qs" "ipc" "call" "idle" "lock";', label: "Shell · Lock screen" },
        { value: "close-window;", label: "Close window" },
        { value: "fullscreen-window;", label: "Fullscreen" },
        { value: "maximize-column;", label: "Maximize column" },
        { value: "toggle-window-floating;", label: "Float / tile window" },
        { value: "center-column;", label: "Center column" },
        { value: "toggle-overview;", label: "Overview" },
        { value: "screenshot;", label: "Screenshot (region)" },
        { value: "screenshot-screen;", label: "Screenshot (screen)" },
        { value: "screenshot-window;", label: "Screenshot (window)" },
        { value: "focus-workspace-up;", label: "Workspace up" },
        { value: "focus-workspace-down;", label: "Workspace down" },
        { value: "focus-column-left;", label: "Focus left" },
        { value: "focus-column-right;", label: "Focus right" },
        { value: "move-column-left;", label: "Move window left" },
        { value: "move-column-right;", label: "Move window right" },
        { value: "switch-preset-column-width;", label: "Cycle window width" },
        { value: "power-off-monitors;", label: "Turn off screens" },
        { value: "show-hotkey-overlay;", label: "Show shortcuts overlay" },
    ]

    // ── разбор config.kdl
    function parse() {
        const lines = cfg.text().split("\n");
        const start = lines.findIndex(l => /^binds\s*\{/.test(l));
        const out = [];
        if (start >= 0) {
            for (let i = start + 1; i < lines.length && !/^\}/.test(lines[i]); i++) {
                const m = lines[i].match(/^\s*(\/-)?([^\s{/]+)((?:\s+[a-z-]+=(?:"[^"]*"|\S+))*)\s*\{\s*(.*?)\s*\}\s*$/);
                if (m) out.push({ line: i, enabled: !m[1], key: m[2], props: m[3].trim(), action: m[4] });
            }
        }
        cfgBinds = out;
    }

    function setCfgEnabled(b, on) {
        const lines = cfg.text().split("\n");
        const l = lines[b.line];
        const disabled = /^\s*\/-/.test(l);
        if (on && disabled) lines[b.line] = l.replace(/^(\s*)\/-\s*/, "$1");
        else if (!on && !disabled) lines[b.line] = l.replace(/^(\s*)/, "$1/-");
        else return;
        cfg.setText(lines.join("\n"));
    }

    function titleOf(b) {
        const t = (b.props ?? "").match(/hotkey-overlay-title="([^"]*)"/);
        if (t) return t[1];
        const known = actions.find(a => a.value === b.action);
        if (known) return known.label.replace(/^Shell · /, "");
        const sp = b.action.match(/^spawn(?:-sh)?\s+(.*?);?$/);
        if (sp) return "Run " + sp[1].replace(/"/g, "");
        return b.action.replace(/;$/, "").replace(/-/g, " ").replace(/^./, c => c.toUpperCase());
    }

    // все активные бинды: свои перекрывают конфиг
    function activeKeys() {
        const m = {};
        for (const b of cfgBinds) if (b.enabled) m[b.key.toLowerCase()] = { src: "cfg", b };
        for (const [i, b] of (Settings.binds ?? []).entries()) if (b.enabled !== false) m[b.key.toLowerCase()] = { src: "own", b, i };
        return m;
    }

    function conflict(key, except) {
        const hit = activeKeys()[key.toLowerCase()];
        return hit && hit.b !== except ? hit : null;
    }

    // сохранить сочетание
    function applyCapture(key) {
        const c = capture;
        capture = null;
        if (!c || !key) return;
        const clash = conflict(key, c.target);
        if (clash) {
            if (clash.src === "cfg") setCfgEnabled(clash.b, false);
            else setOwn(clash.i, "enabled", false);
        }
        if (c.mode === "edit" && c.src === "cfg") {
            // бинд из конфига: отключаем исходную строку и добавляем свою копию с новыми клавишами
            setCfgEnabled(c.target, false);
            Settings.binds = (Settings.binds ?? []).concat([{ key, props: c.target.props, action: c.target.action, enabled: true }]);
        } else if (c.mode === "edit") {
            setOwn(c.index, "key", key);
        } else {
            const action = newAction.value === "custom" ? `spawn-sh "${newCommand.text.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}";` : newAction.value;
            const label = newAction.value === "custom" ? newCommand.text : (actions.find(a => a.value === newAction.value)?.label ?? "").replace(/^Shell · /, "");
            Settings.binds = (Settings.binds ?? []).concat([{ key, props: `hotkey-overlay-title="${label.replace(/"/g, "")}"`, action, enabled: true }]);
            newCommand.text = "";
        }
    }

    function setOwn(i, k, v) {
        const a = JSON.parse(JSON.stringify(Settings.binds ?? []));
        if (v === undefined) a.splice(i, 1);
        else a[i][k] = v;
        Settings.binds = a;
    }

    // клавиша по скан-коду (не зависит от раскладки) -> имя xkb для niri
    readonly property var scanNames: ({
        2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "6", 8: "7", 9: "8", 10: "9", 11: "0", 12: "Minus", 13: "Equal",
        14: "BackSpace", 15: "Tab", 16: "Q", 17: "W", 18: "E", 19: "R", 20: "T", 21: "Y", 22: "U", 23: "I", 24: "O", 25: "P",
        26: "BracketLeft", 27: "BracketRight", 28: "Return", 30: "A", 31: "S", 32: "D", 33: "F", 34: "G", 35: "H", 36: "J",
        37: "K", 38: "L", 39: "Semicolon", 40: "Apostrophe", 41: "Grave", 43: "Backslash", 44: "Z", 45: "X", 46: "C", 47: "V",
        48: "B", 49: "N", 50: "M", 51: "Comma", 52: "Period", 53: "Slash", 57: "Space", 1: "Escape",
        59: "F1", 60: "F2", 61: "F3", 62: "F4", 63: "F5", 64: "F6", 65: "F7", 66: "F8", 67: "F9", 68: "F10", 87: "F11", 88: "F12",
        99: "Print", 102: "Home", 103: "Up", 104: "Page_Up", 105: "Left", 106: "Right", 107: "End", 108: "Down",
        109: "Page_Down", 110: "Insert", 111: "Delete", 119: "Pause",
    })

    // зажатые модификаторы: считаем сами по нажатию/отпусканию (флаги событий на Wayland ненадёжны)
    property var held: ({ Mod: false, Ctrl: false, Alt: false, Shift: false })

    function modOf(key) {
        if (key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R) return "Mod";
        if (key === Qt.Key_Control) return "Ctrl";
        if (key === Qt.Key_Alt || key === Qt.Key_AltGr) return "Alt";
        if (key === Qt.Key_Shift) return "Shift";
        return "";
    }

    function setHeld(mod, on) {
        const h = Object.assign({}, held);
        h[mod] = on;
        held = h;
    }

    function keyName(event) {
        const name = scanNames[event.nativeScanCode - 8];
        if (!name) return "";
        const m = event.modifiers;
        const mods = [];
        if (held.Mod || (m & Qt.MetaModifier)) mods.push("Mod");
        if (held.Ctrl || (m & Qt.ControlModifier)) mods.push("Ctrl");
        if (held.Alt || (m & Qt.AltModifier)) mods.push("Alt");
        if (held.Shift || (m & Qt.ShiftModifier)) mods.push("Shift");
        return mods.concat([name]).join("+");
    }

    // без модификатора можно только F-клавиши, Print, Pause — иначе бинд съест букву при наборе
    function validKey(k) {
        return k.includes("+") || /^(F\d+|Print|Pause|Insert)$/.test(k);
    }

    FileView {
        id: cfg
        path: page.cfgPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: page.parse()
        onSaved: page.parse()
    }

    // пока ждём сочетание, niri не перехватывает клавиши
    ShortcutInhibitor {
        window: page.Window.window
        enabled: page.capture !== null
    }

    // ── компонент строки
    component BindRow: Rectangle {
        id: row
        property var bind
        property bool own: false
        property int ownIndex: -1
        readonly property bool on: bind.enabled !== false

        Layout.fillWidth: true
        implicitHeight: 52
        radius: 10
        color: rowArea.containsMouse ? Theme.surfaceHi : Theme.surface
        opacity: on ? 1 : 0.5

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 12

            // клавиши
            Row {
                Layout.preferredWidth: 250
                spacing: 4

                Repeater {
                    model: row.bind.key.split("+")

                    Rectangle {
                        required property string modelData
                        width: keyText.implicitWidth + 14
                        height: 24
                        radius: 6
                        color: Theme.surfaceHi2
                        border.width: 1
                        border.color: Theme.line

                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: parent.modelData === "Mod" ? "Super" : parent.modelData.replace(/_/g, " ")
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: page.titleOf(row.bind)
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }

            Rectangle {
                visible: row.own
                implicitWidth: ownText.implicitWidth + 12
                implicitHeight: 18
                radius: 5
                color: "transparent"
                border.width: 1
                border.color: Theme.accent

                Text {
                    id: ownText
                    anchors.centerIn: parent
                    text: I18n.tr("custom")
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 4
                }
            }

            SButton {
                text: I18n.tr("Change")
                visible: rowArea.containsMouse || editHover.hovered
                HoverHandler { id: editHover }
                onClicked: page.capture = row.own
                    ? { mode: "edit", src: "own", index: row.ownIndex, target: row.bind }
                    : { mode: "edit", src: "cfg", target: row.bind }
            }
            SButton {
                visible: row.own
                icon: Icons.trash
                danger: true
                onClicked: page.setOwn(row.ownIndex)
            }
            SSwitch {
                checked: row.on
                onToggled: v => row.own ? page.setOwn(row.ownIndex, "enabled", v) : page.setCfgEnabled(row.bind, v)
            }
        }
    }

    // ── добавить
    SSection { text: I18n.tr("Add a shortcut") }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: addCol.implicitHeight + 28
        radius: 10
        color: Theme.surface

        ColumnLayout {
            id: addCol
            x: 18
            y: 14
            width: parent.width - 36
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                SDropdown {
                    id: newAction
                    property string value: "custom"
                    minWidth: 260
                    options: page.actions
                    current: value
                    onPicked: v => value = v
                }

                Rectangle {
                    visible: newAction.value === "custom"
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 8
                    color: Theme.surfaceHi
                    border.width: 1
                    border.color: newCommand.activeFocus ? Theme.line : Theme.surfaceHi2

                    TextInput {
                        id: newCommand
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        clip: true

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: !newCommand.text
                            text: I18n.tr("Command, e.g. telegram-desktop")
                            color: Theme.dim
                            font: newCommand.font
                        }
                    }
                }

                Item {
                    visible: newAction.value !== "custom"
                    Layout.fillWidth: true
                }

                SButton {
                    text: I18n.tr("Choose keys…")
                    primary: true
                    enabled: newAction.value !== "custom" || newCommand.text.trim() !== ""
                    onClicked: page.capture = { mode: "new" }
                }
            }
        }
    }

    // ── поиск
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 14

        SSection {
            Layout.fillWidth: true
            Layout.topMargin: 0
            text: I18n.tr("Shortcuts")
        }

        Rectangle {
            implicitWidth: 260
            implicitHeight: 34
            radius: 8
            color: Theme.surface
            border.width: 1
            border.color: search.activeFocus ? Theme.line : Theme.surfaceHi

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: Icons.search
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize - 1
                }
                TextInput {
                    id: search
                    Layout.fillWidth: true
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    clip: true
                    onTextChanged: page.query = text.toLowerCase()

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !search.text
                        text: I18n.tr("Search keys or actions")
                        color: Theme.dim
                        font: search.font
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        // свои — сверху
        Repeater {
            model: Settings.binds ?? []

            BindRow {
                required property var modelData
                required property int index
                visible: !page.query || `${modelData.key} ${page.titleOf(modelData)} ${modelData.action}`.toLowerCase().includes(page.query)
                bind: modelData
                own: true
                ownIndex: index
            }
        }

        Repeater {
            model: page.cfgBinds

            BindRow {
                required property var modelData
                visible: !page.query || `${modelData.key} ${page.titleOf(modelData)} ${modelData.action}`.toLowerCase().includes(page.query)
                bind: modelData
            }
        }
    }

    // ── окно захвата сочетания
    Rectangle {
        parent: page
        anchors.fill: parent
        visible: page.capture !== null
        color: Qt.rgba(0, 0, 0, 0.55)
        z: 100

        onVisibleChanged: if (visible) {
            page.captured = "";
            page.held = { Mod: false, Ctrl: false, Alt: false, Shift: false };
            catcher.forceActiveFocus();
        }

        MouseArea {
            anchors.fill: parent
            onClicked: page.capture = null
        }

        Rectangle {
            anchors.centerIn: parent
            width: 460
            height: 240
            radius: 16
            color: Theme.surface
            border.width: 1
            border.color: Theme.line

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: I18n.tr("Press the new shortcut")
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: page.captured ? page.captured.replace(/Mod/, "Super").split("+").join("  +  ") : "…"
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 6
                    font.bold: true
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    readonly property var hit: page.captured ? page.conflict(page.captured, page.capture?.target) : null
                    text: !page.captured ? "Hold modifiers (Super, Ctrl, Alt, Shift) and press a key"
                        : !page.validKey(page.captured) ? "Add a modifier — a single letter would block typing"
                        : hit ? `Already used by «${page.titleOf(hit.b)}» — it will be turned off` : "Looks good"
                    color: !page.captured ? Theme.dim : !page.validKey(page.captured) ? Theme.urgent : hit ? Theme.warn : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    spacing: 8

                    SButton {
                        text: I18n.tr("Cancel")
                        onClicked: page.capture = null
                    }
                    SButton {
                        text: I18n.tr("Retry")
                        enabled: page.captured !== ""
                        onClicked: {
                            page.captured = "";
                            catcher.forceActiveFocus();
                        }
                    }
                    SButton {
                        text: I18n.tr("Save")
                        primary: true
                        enabled: page.captured !== "" && page.validKey(page.captured)
                        onClicked: page.applyCapture(page.captured)
                    }
                }
            }
        }

        Item {
            id: catcher
            focus: true
            Keys.onPressed: event => {
                event.accepted = true;
                if (event.key === Qt.Key_Escape && !event.modifiers) {
                    page.capture = null;
                    return;
                }
                const mod = page.modOf(event.key);
                if (mod) {
                    page.setHeld(mod, true);
                    return;
                }
                const k = page.keyName(event);
                if (k) page.captured = k;
            }
            Keys.onReleased: event => {
                event.accepted = true;
                const mod = page.modOf(event.key);
                if (mod) page.setHeld(mod, false);
            }
        }

    }
}
