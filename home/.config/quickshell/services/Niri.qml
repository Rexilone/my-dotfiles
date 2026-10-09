pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var workspaces: []
    property var layouts: []
    property int layoutIdx: 0

    // окна: id -> { id, title, app_id, workspace_id, is_focused }
    property var windows: ({})
    property var focusedWindowId: null
    readonly property var focusedWindow: focusedWindowId !== null ? (windows[focusedWindowId] ?? null) : null

    // монитор с фокусом (у тебя фокус следует за мышью)
    readonly property string focusedOutput: workspaces.find(ws => ws.is_focused)?.output ?? ""

    readonly property string layoutName: layouts[layoutIdx] ?? ""

    function action(args) {
        Quickshell.execDetached(["niri", "msg", "action"].concat(args));
    }

    function focusWorkspace(ws) {
        Quickshell.execDetached(["sh", "-c",
            `niri msg action focus-monitor '${ws.output}' && niri msg action focus-workspace ${ws.idx}`]);
    }

    function updateWorkspaces(fn) {
        workspaces = workspaces.map(ws => Object.assign({}, ws, fn(ws)));
    }

    function handle(ev) {
        if (ev.WorkspacesChanged) {
            workspaces = ev.WorkspacesChanged.workspaces.sort((a, b) => a.idx - b.idx);
        } else if (ev.WorkspaceActivated) {
            const e = ev.WorkspaceActivated;
            const target = workspaces.find(ws => ws.id === e.id);
            if (!target) return;
            updateWorkspaces(ws => {
                const r = {};
                if (ws.output === target.output) r.is_active = ws.id === e.id;
                if (e.focused) r.is_focused = ws.id === e.id;
                return r;
            });
        } else if (ev.WorkspaceUrgencyChanged) {
            const e = ev.WorkspaceUrgencyChanged;
            updateWorkspaces(ws => ws.id === e.id ? { is_urgent: e.urgent } : {});
        } else if (ev.WorkspaceActiveWindowChanged) {
            const e = ev.WorkspaceActiveWindowChanged;
            updateWorkspaces(ws => ws.id === e.workspace_id ? { active_window_id: e.active_window_id } : {});
        } else if (ev.WindowsChanged) {
            const m = {};
            for (const w of ev.WindowsChanged.windows) m[w.id] = w;
            windows = m;
            const f = ev.WindowsChanged.windows.find(w => w.is_focused);
            focusedWindowId = f ? f.id : null;
        } else if (ev.WindowOpenedOrChanged) {
            const w = ev.WindowOpenedOrChanged.window;
            const m = Object.assign({}, windows);
            m[w.id] = w;
            windows = m;
            if (w.is_focused) focusedWindowId = w.id;
        } else if (ev.WindowClosed) {
            const m = Object.assign({}, windows);
            delete m[ev.WindowClosed.id];
            windows = m;
            if (focusedWindowId === ev.WindowClosed.id) focusedWindowId = null;
        } else if (ev.WindowFocusChanged) {
            focusedWindowId = ev.WindowFocusChanged.id;
        } else if (ev.KeyboardLayoutsChanged) {
            const k = ev.KeyboardLayoutsChanged.keyboard_layouts;
            layouts = k.names;
            layoutIdx = k.current_idx;
        } else if (ev.KeyboardLayoutSwitched) {
            layoutIdx = ev.KeyboardLayoutSwitched.idx;
        }
    }

    Process {
        id: stream
        running: true
        command: ["niri", "msg", "-j", "event-stream"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.handle(JSON.parse(line));
                } catch (e) {}
            }
        }
        onExited: restart.start()
    }

    Timer {
        id: restart
        interval: 1000
        onTriggered: stream.running = true
    }
}
