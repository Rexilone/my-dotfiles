pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Приложения, скрытые с демонстрации экрана (Super+G → ~/.local/bin/niri-cast-toggle).
// Список — ~/.config/niri/screencast-hidden.list, из него — правило niri в screencast-hidden.kdl.
// Шелл следит за списком: индикатор в баре и меню со списком скрытых.
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("HOME")}/.config/niri`
    property var apps: []

    readonly property bool focusedHidden: !!Niri.focusedWindow && apps.includes(Niri.focusedWindow.app_id)

    function isHidden(appId) {
        return apps.includes(appId);
    }

    // показать приложение на демонстрации снова (скрыть — Super+G на его окне)
    function unhide(appId) {
        save(apps.filter(a => a !== appId));
    }

    function hideApp(appId) {
        if (appId && !apps.includes(appId)) save(apps.concat([appId]));
    }

    function save(next) {
        apps = next;
        listFile.setText(next.length ? next.join("\n") + "\n" : "");
        writeKdl();
    }

    function writeKdl() {
        const L = ["// генерируется niri-cast-toggle (Super+G) и шеллом, вручную не редактировать\n"];
        if (apps.length) {
            L.push("window-rule {\n");
            for (const a of apps) L.push(`    match app-id=r#"^${a.replace(/[.*+?^${}()|[\]\\-]/g, "\\$&")}$"#\n`);
            L.push('    block-out-from "screencast"\n');
            L.push("}\n");
        }
        const text = L.join("");
        if (kdlFile.text() !== text) kdlFile.setText(text);
    }

    function parse(text) {
        return (text ?? "").split("\n").map(s => s.trim()).filter(s => s);
    }

    FileView {
        id: listFile
        path: `${root.dir}/screencast-hidden.list`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const next = root.parse(text());
            if (JSON.stringify(next) !== JSON.stringify(root.apps)) root.apps = next;
            root.writeKdl();
        }
        onLoadFailed: {
            root.apps = [];
            root.writeKdl();
        }
    }

    FileView {
        id: kdlFile
        path: `${root.dir}/screencast-hidden.kdl`
        blockLoading: true
        printErrors: false
    }

    // qs ipc call cast list | unhide <app-id>
    IpcHandler {
        target: "cast"
        function list(): string { return root.apps.join("\n"); }
        function unhide(app: string): void { root.unhide(app); }
    }
}
