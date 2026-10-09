pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// плагины: ~/.config/quickshell/plugins/<id>/plugin.json
// части плагина: bar (модуль в баре), service (фоновая часть), settings (страница в Настройках → Плагины)
Singleton {
    id: root

    readonly property string dir: Quickshell.shellPath("plugins")
    property var list: []        // [{ id, name, version, author, description, bar, service, settings, dir, error }]
    property bool scanning: false

    readonly property var enabled: list.filter(p => !p.error && Settings.plugins[p.id] === true)
    readonly property var barPlugins: enabled.filter(p => p.bar)
    readonly property var servicePlugins: enabled.filter(p => p.service)

    function reload() {
        scanning = true;
        scan.running = true;
    }

    function url(p, file) {
        return `file://${p.dir}/${file}`;
    }

    // ── данные плагинов (переживают перезапуск)
    property var data: ({})

    function get(id, key, def) {
        const v = (data[id] ?? {})[key];
        return v === undefined ? def : v;
    }

    function set(id, key, value) {
        const d = Object.assign({}, data);
        d[id] = Object.assign({}, d[id] ?? {}, { [key]: value });
        data = d;
        store.data = JSON.parse(JSON.stringify(d));
        saveTimer.restart();
    }

    // объект, который получает плагин в свойство `plugin`
    function api(p) {
        return {
            id: p.id,
            name: p.name,
            version: p.version,
            dir: p.dir,
            get: (key, def) => root.get(p.id, key, def),
            set: (key, value) => root.set(p.id, key, value),
            notify: (title, body) => Quickshell.execDetached(["notify-send", "-a", p.name, String(title), String(body ?? "")]),
            run: cmd => Quickshell.execDetached(cmd),
            openSettings: () => Ui.openSettings("plugins"),
        };
    }

    Process {
        id: scan
        command: ["sh", "-c", `
            for f in "$1"/*/plugin.json; do
                [ -f "$f" ] || continue
                printf '@@PLUGIN %s\\n' "$(dirname "$f")"
                cat "$f"
                printf '\\n'
            done`, "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const chunk of text.split("@@PLUGIN ").slice(1)) {
                    const nl = chunk.indexOf("\n");
                    const dir = chunk.slice(0, nl).trim();
                    const folder = dir.split("/").pop();
                    let m = null, error = "";
                    try {
                        m = JSON.parse(chunk.slice(nl + 1));
                    } catch (e) {
                        error = `plugin.json: ${e.message}`;
                    }
                    if (m && !/^[a-z0-9][a-z0-9-]*$/.test(m.id ?? "")) error = 'plugin.json: "id" must be lowercase letters, digits and dashes';
                    if (m && m.id !== folder && !error) error = `plugin.json: "id" must match the folder name (${folder})`;
                    out.push({
                        id: m?.id ?? folder,
                        name: m?.name ?? folder,
                        version: m?.version ?? "",
                        author: m?.author ?? "",
                        description: m?.description ?? "",
                        bar: m?.bar ?? "",
                        service: m?.service ?? "",
                        settings: m?.settings ?? "",
                        dir,
                        error,
                    });
                }
                root.list = out.sort((a, b) => a.name.localeCompare(b.name));
                root.scanning = false;
            }
        }
    }

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: storeFile.writeAdapter()
    }

    FileView {
        id: storeFile
        path: Quickshell.statePath("plugins.json")
        blockLoading: true
        printErrors: false

        JsonAdapter {
            id: store
            property var data: ({})
        }
    }

    IpcHandler {
        target: "plugins"
        // qs ipc call plugins reload
        function reload(): void { root.reload(); }
    }

    Component.onCompleted: {
        try {
            data = JSON.parse(JSON.stringify(store.data ?? {}));
        } catch (e) {}
        reload();
    }
}
