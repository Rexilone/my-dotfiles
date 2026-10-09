pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// «Программы» (окно StoreWindow, «Программы» в меню приложений): приложения из репозиториев Arch и AUR.
// Данные — scripts/store.py (каталог appstream, поиск, сведения, обновления), действия — очередь задач:
// pacman через pkexec (пароль спросит окно polkit шелла), AUR — через paru/yay с --sudo pkexec.
Singleton {
    id: root

    readonly property string script: `${Quickshell.shellDir}/scripts/store.py`

    // ── каталог: [{ id, pkg, repo, name, summary, description, icon, categories, keywords, homepage, license, developer, screenshots }]
    property var catalog: []
    property var byPkg: ({})
    property bool appstream: true
    property bool catalogLoading: false

    // ── установленное
    property var versions: ({})       // пакет -> версия (все установленные)
    property var apps: ({})           // пакет -> id .desktop (то, что можно запустить)
    property var packages: []         // явно установленные: [{ name, version, aur, app, desc, size, date }]
    property var foreign: []          // из AUR / вручную

    // ── обновления
    property var updates: []          // [{ name, from, to, repo: repo|aur }]
    property bool checkingUpdates: false
    property real lastUpdateCheck: 0
    property bool hasCheckupdates: true
    property string helper: ""        // paru | yay — для AUR

    // ── поиск
    property string query: ""
    property var repoResults: []
    property var aurResults: []
    property bool aurError: false
    property bool searching: false

    // ── задачи: [{ id, kind: install|remove|upgrade, pkgs, aur, state: queued|running|done|failed|cancelled, line, log, step, total }]
    property var jobs: []
    property int jobSeq: 1
    readonly property var current: jobs.find(j => j.state === "running") ?? null
    readonly property var queued: jobs.filter(j => j.state === "queued")
    signal jobFinished(var job)

    // разделы магазина: категории freedesktop → название и значок
    readonly property var categories: [
        { key: "Network", label: "Internet", icon: 0xF059F },
        { key: "AudioVideo", label: "Music & video", icon: 0xF0C34 },
        { key: "Graphics", label: "Graphics & photo", icon: 0xF02E9 },
        { key: "Office", label: "Office", icon: 0xF0219 },
        { key: "Development", label: "Development", icon: 0xF0169 },
        { key: "Game", label: "Games", icon: 0xF0297 },
        { key: "Education", label: "Education", icon: 0xF0474 },
        { key: "Science", label: "Science", icon: 0xF0668 },
        { key: "System", label: "System", icon: 0xF048B },
        { key: "Utility", label: "Utilities", icon: 0xF0AD7 },
    ]

    // подборки на главной (что есть в каталоге — с иконками; AUR — отдельно)
    readonly property var picks: ["firefox", "chromium", "telegram-desktop", "discord", "obs-studio", "vlc", "gimp", "krita",
        "inkscape", "blender", "libreoffice-fresh", "obsidian", "thunderbird", "steam", "lutris", "prismlauncher", "code",
        "qbittorrent", "kdenlive", "audacity", "keepassxc", "signal-desktop", "spotify-launcher", "mpv"]
    readonly property var aurPicks: [
        { name: "visual-studio-code-bin", desc: "Visual Studio Code (official build)" },
        { name: "google-chrome", desc: "The popular web browser by Google" },
        { name: "spotify", desc: "Music streaming service" },
        { name: "zen-browser-bin", desc: "A calmer Firefox-based browser" },
        { name: "heroic-games-launcher-bin", desc: "Epic, GOG and Amazon games" },
        { name: "onlyoffice-bin", desc: "Office suite compatible with MS Office" },
        { name: "anydesk-bin", desc: "Remote desktop" },
        { name: "ayugram-desktop-bin", desc: "Telegram client with extras" },
    ]

    // главная категория приложения (первая известная)
    function categoryOf(app) {
        for (const c of app?.categories ?? []) if (categories.some(x => x.key === c)) return c;
        return "";
    }

    function inCategory(key) {
        return catalog.filter(a => (a.categories ?? []).includes(key));
    }

    function isInstalled(pkg) { return versions[pkg] !== undefined; }
    function hasUpdate(pkg) { return updates.some(u => u.name === pkg); }
    function busyWith(pkg) {
        const j = jobs.find(x => (x.state === "running" || x.state === "queued") && x.pkgs.includes(pkg));
        return j ? j.kind : "";
    }

    // иконка: из appstream, иначе из темы значков (установленные приложения)
    function iconFor(pkg) {
        const a = byPkg[pkg];
        if (a?.icon) {
            if (a.icon.startsWith("stock:")) return Quickshell.iconPath(a.icon.slice(6), true);
            return "file://" + a.icon;
        }
        const id = apps[pkg];
        if (id) {
            const e = DesktopEntries.byId(id);
            if (e?.icon) return Quickshell.iconPath(e.icon, true);
        }
        return Quickshell.iconPath(pkg, true);
    }

    function displayName(pkg) {
        return byPkg[pkg]?.name || pkg;
    }

    // запустить установленное приложение
    function launch(pkg) {
        const id = apps[pkg] ?? byPkg[pkg]?.id?.replace(/\.desktop$/, "");
        const e = id ? DesktopEntries.byId(id) : null;
        if (e) e.execute();
    }
    function canLaunch(pkg) {
        const id = apps[pkg] ?? byPkg[pkg]?.id?.replace(/\.desktop$/, "");
        return isInstalled(pkg) && !!id && !!DesktopEntries.byId(id);
    }

    // ── загрузка данных
    function loadCatalog() {
        if (catalogLoading) return;
        catalogLoading = true;
        catProc.running = true;
    }
    Process {
        id: catProc
        command: ["python3", root.script, "catalog"]
        environment: ({ STORE_LANG: I18n.lang })
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    root.appstream = r.appstream;
                    catFile.path = "";
                    catFile.path = r.path;
                } catch (e) {
                    root.catalogLoading = false;
                }
            }
        }
    }
    FileView {
        id: catFile
        blockLoading: false
        printErrors: false
        onLoaded: {
            try {
                const list = JSON.parse(text());
                const m = {};
                for (const a of list) m[a.pkg] = a;
                root.byPkg = m;
                root.catalog = list;
            } catch (e) {}
            root.catalogLoading = false;
        }
        onLoadFailed: root.catalogLoading = false
    }
    Connections {
        target: I18n
        function onLangChanged() { if (root.catalog.length) root.loadCatalog(); }
    }

    function refreshInstalled() {
        if (!instProc.running) instProc.running = true;
    }
    Process {
        id: instProc
        command: ["python3", root.script, "installed"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    root.versions = r.versions;
                    root.apps = r.apps;
                    root.packages = r.packages;
                    root.foreign = r.foreign;
                } catch (e) {}
            }
        }
    }

    function checkUpdates() {
        if (checkingUpdates) return;
        checkingUpdates = true;
        updProc.running = true;
    }
    Process {
        id: updProc
        command: ["python3", root.script, "updates"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    root.updates = r.updates;
                    root.hasCheckupdates = r.checkupdates;
                    root.helper = r.helper;
                } catch (e) {}
                root.lastUpdateCheck = Date.now();
                root.checkingUpdates = false;
            }
        }
        onExited: root.checkingUpdates = false
    }

    // поиск: по каталогу — сразу (в окне), по pacman и AUR — с задержкой
    function search(q) {
        query = q;
        searchTimer.restart();
    }
    Timer {
        id: searchTimer
        interval: 350
        onTriggered: {
            if (root.query.trim().length < 2) {
                root.repoResults = [];
                root.aurResults = [];
                return;
            }
            root.searching = true;
            searchProc.running = false;
            searchProc.command = ["python3", root.script, "search", root.query.trim()];
            searchProc.running = true;
        }
    }
    Process {
        id: searchProc
        property string forQuery: ""
        onStarted: forQuery = root.query
        stdout: StdioCollector {
            onStreamFinished: {
                if (searchProc.forQuery !== root.query) return;
                try {
                    const r = JSON.parse(text);
                    const q = root.query.trim().toLowerCase();
                    // точное совпадение имени — вверх
                    const rank = p => p.name === q ? 0 : p.name.startsWith(q) ? 1 : p.name.includes(q) ? 2 : 3;
                    root.repoResults = r.repo.sort((a, b) => rank(a) - rank(b));
                    root.aurResults = r.aur.sort((a, b) => rank(a) - rank(b) || b.popularity - a.popularity);
                    root.aurError = r.aurError;
                } catch (e) {}
                root.searching = false;
            }
        }
    }

    // локальный поиск по каталогу (названия, описания, ключевые слова, имя пакета)
    function searchCatalog(q) {
        q = q.trim().toLowerCase();
        if (!q) return [];
        const score = a => {
            const n = a.name.toLowerCase();
            if (n === q || a.pkg === q) return 0;
            if (n.startsWith(q) || a.pkg.startsWith(q)) return 1;
            if (n.includes(q) || a.pkg.includes(q)) return 2;
            return 3;
        };
        return catalog.filter(a => `${a.name} ${a.pkg} ${a.summary} ${a.keywords}`.toLowerCase().includes(q))
            .sort((a, b) => score(a) - score(b) || a.name.localeCompare(b.name)).slice(0, 60);
    }

    // сведения о пакете (с кэшем)
    property var infoCache: ({})
    signal infoReady(string pkg)
    function loadInfo(pkg, force) {
        if (infoCache[pkg] && !force) return;
        const p = infoComp.createObject(root, { pkg });
        p.running = true;
    }
    Component {
        id: infoComp
        Process {
            id: ip
            property string pkg
            command: ["python3", root.script, "info", pkg]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const c = Object.assign({}, root.infoCache);
                        c[ip.pkg] = JSON.parse(text);
                        root.infoCache = c;
                        root.infoReady(ip.pkg);
                    } catch (e) {}
                    ip.destroy();
                }
            }
        }
    }

    // ── задачи
    function enqueue(kind, pkgs, aur) {
        const j = { id: jobSeq++, kind, pkgs, aur: !!aur, state: "queued", line: "", log: "", step: 0, total: 0 };
        jobs = jobs.concat([j]);
        next();
        return j.id;
    }
    function install(pkg, aur) { return enqueue("install", [pkg], aur); }
    function remove(pkg) { return enqueue("remove", [pkg], false); }
    function upgradeAll() { return enqueue("upgrade", [], helper !== ""); }
    function cancel(id) {
        jobs = jobs.map(j => j.id === id && j.state === "queued" ? Object.assign({}, j, { state: "cancelled" }) : j);
    }
    function clearFinished() {
        jobs = jobs.filter(j => j.state === "running" || j.state === "queued");
    }

    function aurCmd(args) {
        const h = helper || "paru";
        const extra = h === "paru" ? ["--skipreview"] : ["--answerdiff", "None", "--answerclean", "None", "--answeredit", "None"];
        return [h].concat(args, ["--noconfirm", "--sudo", "pkexec"], extra);
    }

    function commandFor(j, retry) {
        if (j.kind === "remove") return ["pkexec", "pacman", "-Rns", "--noconfirm"].concat(j.pkgs);
        if (j.kind === "upgrade") return j.aur ? aurCmd(["-Syu"]) : ["pkexec", "pacman", "-Syu", "--noconfirm"];
        if (j.aur) return aurCmd(["-S", "--needed"].concat(j.pkgs));
        // база пакетов устарела (404 при скачивании) — повтор с обновлением системы, как положено в Arch
        return ["pkexec", "pacman", retry ? "-Syu" : "-S", "--needed", "--noconfirm"].concat(j.pkgs);
    }

    function patch(id, fields) {
        jobs = jobs.map(j => j.id === id ? Object.assign({}, j, fields) : j);
    }

    function next() {
        if (runner.running || current) return;
        const j = jobs.find(x => x.state === "queued");
        if (!j) return;
        runner.job = j.id;
        runner.retried = false;
        runner.buf = "";
        patch(j.id, { state: "running", line: I18n.tr("Waiting for the password…") });
        runner.command = commandFor(j, false);
        runner.running = true;
    }

    Process {
        id: runner
        property int job: 0
        property bool retried: false
        property string buf: ""
        environment: ({ LC_ALL: "C", PACMAN_COLOR: "never" })

        stdout: SplitParser {
            onRead: line => runner.feed(line)
        }
        stderr: SplitParser {
            onRead: line => runner.feed(line)
        }

        function feed(line) {
            line = line.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").trim();
            if (!line) return;
            buf = (buf + line + "\n").slice(-12000);
            const fields = { log: buf };
            const m = line.match(/^\(\s*(\d+)\/(\d+)\)\s+(.*)$/);
            if (m) {
                fields.step = +m[1];
                fields.total = +m[2];
                fields.line = m[3];
            } else if (!/^[#\-\s]*$/.test(line)) {
                fields.line = line.slice(0, 160);
            }
            root.patch(job, fields);
        }

        onExited: (code, status) => {
            const j = root.jobs.find(x => x.id === job);
            if (!j) return;
            // пакет пропал с зеркала: база устарела — один раз повторяем с -Syu
            if (code !== 0 && !retried && j.kind === "install" && !j.aur && /failed retrieving file|404/.test(buf)) {
                retried = true;
                root.patch(job, { line: I18n.tr("Updating the package database…") });
                command = root.commandFor(j, true);
                running = true;
                return;
            }
            const state = code === 0 ? "done" : (code === 126 || code === 127) ? "cancelled" : "failed";
            root.patch(job, { state, line: state === "done" ? "" : state === "cancelled" ? I18n.tr("Cancelled — no password") : (j.line || I18n.tr("Failed")) });
            const fin = root.jobs.find(x => x.id === job);
            root.jobFinished(fin);
            root.refreshInstalled();
            if (j.kind === "upgrade" || state === "done") root.checkUpdates();
            if (state === "done") {
                const what = j.kind === "upgrade" ? I18n.tr("System updated")
                    : `${root.displayName(j.pkgs[0])} — ${I18n.tr(j.kind === "install" ? "installed" : "removed")}`;
                Quickshell.execDetached(["notify-send", "-a", I18n.tr("Software"), "-i", "system-software-install", what]);
            }
            root.next();
        }
    }

    // обновления — раз в 3 часа (и при открытии магазина)
    Timer {
        interval: 3 * 3600 * 1000
        repeat: true
        running: true
        onTriggered: root.checkUpdates()
    }

    // помощник AUR: paru или yay
    Process {
        running: true
        command: ["sh", "-c", "basename \"$(command -v paru || command -v yay)\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: if (!root.helper) root.helper = text.trim()
        }
    }

    Component.onCompleted: refreshInstalled()
}
