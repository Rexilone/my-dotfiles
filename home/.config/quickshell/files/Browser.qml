import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.services

// проводник в духе Nautilus: боковая панель (недавние, избранное, папки, закладки, телефон через Rexlink, диски),
// шапка со строкой пути и поиском, файлы сеткой или списком, параметры и свойства — диалогами внутри окна.
// Операции с файлами — scripts/files.py (копирование с прогрессом, корзина, поиск, архивы, «Открыть с помощью»)
Item {
    id: br

    property string startPath: ""
    property string revealPath: ""        // выделить этот файл после открытия
    property bool startPrefs: false
    signal closeRequested
    signal quitRequested
    signal newWindowRequested(string path)

    readonly property string home: Quickshell.env("HOME")
    readonly property string helper: Quickshell.shellDir + "/scripts/files.py"
    readonly property var cfg: Settings.files ?? {}
    readonly property bool sidebarOn: cfg.sidebar ?? true

    // ── где мы
    property string path: ""
    property string mode: "dir"        // dir | search | trash | recent | starred
    property var back: []
    property var fwd: []
    property var places: ({ dirs: [], bookmarks: [], drives: [], trash: 0, remote: [] })

    // заголовок окна — как в Nautilus, имя папки
    readonly property string title: mode === "trash" ? I18n.tr("Trash")
        : mode === "recent" ? I18n.tr("Recent")
        : mode === "starred" ? I18n.tr("Starred")
        : mode === "search" ? `${I18n.tr("Search")}: ${query}`
        : path === home ? I18n.tr("Home Folder")
        : path === "/" ? I18n.tr("Computer")
        : (path.split("/").pop() ?? "").startsWith("dav:host=") ? I18n.tr("Phone")
        : path.split("/").pop() || I18n.tr("Files")

    // ── что показываем: [{ name, path, dir, size, mtime, sub? }]
    property var items: []
    property var searchItems: []
    property var trashItems: []
    property var recentItems: []
    property var starredItems: []
    property string filter: ""          // фильтр по имени (поиск на телефоне, в корзине, недавних)
    property bool searching: false
    readonly property bool loading: mode === "dir" && fm.status === FolderListModel.Loading
    readonly property var shown: {
        if (mode === "search") return searchItems;
        const l = mode === "trash" ? trashItems : mode === "recent" ? recentItems : mode === "starred" ? starredItems : items;
        const q = filter.trim().toLowerCase();
        return q ? l.filter(i => i.name.toLowerCase().includes(q)) : l;
    }

    // ── выделение
    property var sel: ({})
    property int cur: -1                // элемент под «курсором» клавиатуры
    property int anchorIdx: -1
    property bool keyboardUsed: false   // рамку фокуса показываем только при работе с клавиатуры
    readonly property var selPaths: Object.keys(sel)
    readonly property var selItems: shown.filter(i => sel[i.path])

    // ── буфер, переименование, операция, диалоги
    property var clip: ({ mode: "", paths: [] })
    property string renaming: ""
    property var job: null              // { title, done, total }
    property string toast: ""
    property bool showPreview: false
    property var info: null             // свойства
    property var confirm: null          // { title, body, action, act } — подтверждение
    property bool showPrefs: false
    property bool showShortcuts: false
    property var menuOwner: null        // кнопка, открывшая меню (подсвечена, пока меню открыто)

    // ── избранное (звёздочки): пути в Settings.files.starred
    readonly property var starredList: cfg.starred ?? []
    readonly property var starredSet: {
        const s = {};
        for (const p of starredList) s[p] = true;
        return s;
    }
    function isStarred(p) {
        return !!starredSet[p];
    }
    function toggleStar(paths) {
        if (!paths.length) return;
        const all = paths.every(p => starredSet[p]);
        const next = all ? starredList.filter(p => !paths.includes(p)) : starredList.concat(paths.filter(p => !starredSet[p]));
        Settings.setFiles("starred", next);
        say(I18n.tr(all ? "Removed from Starred" : "Added to Starred") + (paths.length > 1 ? `: ${paths.length}` : ""));
        if (mode === "starred") Qt.callLater(loadStarred);
    }

    // ── размер значков
    readonly property var zoomSteps: [0.5, 0.75, 1, 1.25, 1.5, 2]
    function zoomBy(d) {
        const z = cfg.zoom ?? 1;
        let i = zoomSteps.findIndex(s => s >= z - 0.001);
        if (i < 0) i = zoomSteps.length - 1;
        Settings.setFiles("zoom", zoomSteps[Math.max(0, Math.min(zoomSteps.length - 1, i + d))]);
    }

    // ═════════════════════════ навигация
    function norm(p) {
        p = p.replace(/\/+$/, "");
        return p || "/";
    }
    function pushHistory() {
        back = back.concat([{ path, mode }]).slice(-50);
        fwd = [];
    }
    function go(p, keepHistory) {
        p = norm(p);
        if (mode === "dir" && p === path) {
            if (searchOpen) closeSearch();
            return;
        }
        if (!keepHistory && (path || mode !== "dir")) pushHistory();
        searchOpen = false;
        query = "";
        mode = "dir";
        path = p;
        filter = "";
        searching = false;
        clearSel();
        renaming = "";
    }
    function openSpecial(m, keepHistory) {
        if (mode === m && !searchOpen) return;
        if (!keepHistory) pushHistory();
        searchOpen = false;
        query = "";
        filter = "";
        mode = m;
        clearSel();
        if (m === "trash") trashProc.running = true;
        else if (m === "recent") recentProc.running = true;
        else if (m === "starred") loadStarred();
    }
    function openTrash(keepHistory) {
        openSpecial("trash", keepHistory);
    }
    function restore(h) {
        if (h.mode === "dir" || h.mode === "search") go(h.path, true);
        else openSpecial(h.mode, true);
    }
    function goBack() {
        if (!back.length) return;
        fwd = fwd.concat([{ path, mode }]);
        const b = back[back.length - 1];
        back = back.slice(0, -1);
        restore(b);
    }
    function goFwd() {
        if (!fwd.length) return;
        back = back.concat([{ path, mode }]);
        const f = fwd[fwd.length - 1];
        fwd = fwd.slice(0, -1);
        restore(f);
    }
    function up() {
        if (mode !== "dir") { go(path || home); return; }
        if (path === "/") return;
        go(path.substring(0, path.lastIndexOf("/")) || "/");
    }
    function refresh() {
        if (mode === "trash") trashProc.running = true;
        else if (mode === "recent") recentProc.running = true;
        else if (mode === "starred") loadStarred();
        else if (mode === "search") runSearch();
        else rebuild.restart();
        placesProc.running = true;
    }

    // ── папка
    FolderListModel {
        id: fm
        // в поиске папка остаётся загруженной — после него не перечитывать
        folder: br.path && (br.mode === "dir" || br.mode === "search") ? "file://" + br.path : ""
        showHidden: br.cfg.hidden ?? false
        showDirsFirst: br.cfg.dirsFirst ?? true
        showDotAndDotDot: false
        caseSensitive: false
        sortField: ({ name: FolderListModel.Name, time: FolderListModel.Time, size: FolderListModel.Size, type: FolderListModel.Type })[br.cfg.sort ?? "name"]
        sortReversed: br.cfg.reverse ?? false
        onCountChanged: rebuild.restart()
        onStatusChanged: rebuild.restart()
        onFolderChanged: rebuild.restart()
        onRowsInserted: rebuild.restart()
        onRowsRemoved: rebuild.restart()
        onDataChanged: rebuild.restart()
        onModelReset: rebuild.restart()
    }
    Timer {
        id: rebuild
        interval: 40
        onTriggered: {
            const a = [];
            for (let i = 0; i < fm.count; i++) {
                a.push({
                    name: fm.get(i, "fileName"),
                    path: fm.get(i, "filePath"),
                    dir: fm.get(i, "fileIsDir"),
                    size: fm.get(i, "fileSize"),
                    mtime: fm.get(i, "fileModified"),
                });
            }
            br.items = a;
            if (br.mode !== "dir") return;
            // выделение — только то, что ещё есть
            const s = {};
            for (const p in br.sel) if (a.some(x => x.path === p)) s[p] = true;
            br.sel = s;
            if (br.pendingSelect) {
                const i = a.findIndex(x => x.path === br.pendingSelect);
                if (i >= 0) {
                    br.sel = { [br.pendingSelect]: true };
                    br.cur = i;
                    br.anchorIdx = i;
                    if (br.pendingRename) br.renaming = br.pendingSelect;
                    br.pendingSelect = "";
                    br.pendingRename = false;
                    Qt.callLater(() => view.positionAt(i));
                }
            }
            if (br.cur >= a.length) br.cur = a.length - 1;
        }
    }
    property string pendingSelect: ""
    property bool pendingRename: false

    // ── места
    Process {
        id: placesProc
        running: true
        command: ["python3", br.helper, "places"]
        stdout: StdioCollector {
            onStreamFinished: { try { br.places = JSON.parse(text); } catch (e) {} }
        }
    }
    function isBookmarked(p) {
        return (places.bookmarks ?? []).some(b => b.path === p);
    }

    // ── корзина, недавние, избранное
    function fromList(l, subOf) {
        return l.map(r => ({ name: r.name, path: r.path, dir: r.dir, size: r.size, mtime: new Date(r.mtime * 1000), sub: subOf(r) }));
    }
    function parentOf(p) {
        return (p.substring(0, p.lastIndexOf("/")) || "/").replace(home, "~");
    }
    Process {
        id: trashProc
        command: ["python3", br.helper, "trashlist"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = [];
                try { l = JSON.parse(text); } catch (e) {}
                br.trashItems = l.map(t => ({ name: t.name, path: t.path, dir: t.dir, size: 0, mtime: t.date ? new Date(t.date) : null,
                                              sub: t.orig ? br.parentOf(t.orig) : "" }));
            }
        }
    }
    Process {
        id: recentProc
        command: ["python3", br.helper, "recent"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = [];
                try { l = JSON.parse(text); } catch (e) {}
                br.recentItems = br.fromList(l, r => br.parentOf(r.path));
            }
        }
    }
    function loadStarred() {
        if (!starredList.length) { starredItems = []; return; }
        starredProc.command = ["python3", helper, "stat"].concat(starredList);
        starredProc.running = true;
    }
    Process {
        id: starredProc
        stdout: StdioCollector {
            onStreamFinished: {
                let l = [];
                try { l = JSON.parse(text); } catch (e) {}
                br.starredItems = br.fromList(l, r => br.parentOf(r.path));
            }
        }
    }

    // ═════════════════════════ поиск: как в Nautilus — в строке пути, сразу по мере ввода, во вложенных папках.
    // На телефоне (WebDAV), в корзине, недавних и избранном — фильтр того, что видно
    property bool searchOpen: false
    property string query: ""
    property string searchBase: ""
    property string searchFrom: "dir"
    property string searchQ: ""
    readonly property bool searchRemote: mode !== "search" && mode !== "dir" || searchBase.includes("/gvfs/")
    readonly property string searchBaseName: searchBase === home ? I18n.tr("Home Folder") : searchBase.split("/").pop() || "/"
    onSearchOpenChanged: if (searchOpen) {
        searchBase = mode === "dir" ? path : home;
        searchFrom = mode;
    }
    function setQuery(q) {
        query = q;
        if (searchRemote) { filter = q; return; }
        if (!q.trim()) {
            searchTimer.stop();
            if (mode === "search") backFromSearch();
            return;
        }
        searchTimer.restart();
    }
    function backFromSearch() {
        searching = false;
        clearSel();
        if (searchFrom === "dir") { mode = "dir"; path = searchBase; }
        else openSpecial(searchFrom, true);
    }
    function closeSearch() {
        searchTimer.stop();
        const was = mode === "search";
        searchOpen = false;
        query = "";
        filter = "";
        if (was) backFromSearch();
    }
    Timer {
        id: searchTimer
        interval: 250
        onTriggered: br.runSearch()
    }
    Timer {
        id: searchRestart
        interval: 30
        onTriggered: br.runSearch()
    }
    function runSearch() {
        const q = query.trim();
        if (!q) return;
        mode = "search";
        searching = true;
        clearSel();
        if (searchProc.running) {
            searchProc.running = false;
            searchRestart.restart();
            return;
        }
        searchQ = q;
        searchProc.command = ["python3", helper, "search", searchBase, q];
        searchProc.running = true;
    }
    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (br.mode !== "search" || br.searchQ !== br.query.trim()) return;
                let l = [];
                try { l = JSON.parse(text); } catch (e) {}
                br.searchItems = br.fromList(l, r => br.parentOf(r.path));
                br.searching = false;
            }
        }
    }

    // ═════════════════════════ выделение
    function clearSel() {
        sel = {};
        cur = -1;
        anchorIdx = -1;
    }
    function selectOnly(i) {
        const it = shown[i];
        if (!it) return;
        sel = { [it.path]: true };
        cur = i;
        anchorIdx = i;
    }
    function toggleSel(i) {
        const it = shown[i];
        if (!it) return;
        const s = Object.assign({}, sel);
        if (s[it.path]) delete s[it.path];
        else s[it.path] = true;
        sel = s;
        cur = i;
        anchorIdx = i;
    }
    function rangeSel(i) {
        const a = anchorIdx < 0 ? i : anchorIdx;
        const s = {};
        for (let k = Math.min(a, i); k <= Math.max(a, i); k++) if (shown[k]) s[shown[k].path] = true;
        sel = s;
        cur = i;
    }
    function selectAll() {
        const s = {};
        for (const it of shown) s[it.path] = true;
        sel = s;
    }
    // щелчок мышью: обычный / Ctrl / Shift
    function clickItem(i, mods) {
        if (mods & Qt.ShiftModifier) rangeSel(i);
        else if (mods & Qt.ControlModifier) toggleSel(i);
        else selectOnly(i);
    }
    function moveCur(delta, shift) {
        if (!shown.length) return;
        keyboardUsed = true;
        const i = Math.max(0, Math.min(shown.length - 1, (cur < 0 ? 0 : cur + delta)));
        if (shift) rangeSel(i);
        else selectOnly(i);
        view.positionAt(i);
    }

    // ═════════════════════════ открыть
    function openItem(it) {
        if (!it) return;
        if (mode === "trash") { showPreview = true; return; }
        if (it.dir) go(it.path);
        else Quickshell.execDetached(["gio", "open", it.path]);
    }
    function openWith(it, desktopId) {
        Quickshell.execDetached(["gtk-launch", desktopId.replace(/\.desktop$/, ""), it.path]);
    }
    function openTerminal(p) {
        Quickshell.execDetached(["foot", "--working-directory", p || path]);
    }
    function revealItem(it) {
        pendingSelect = it.path;
        go(it.path.substring(0, it.path.lastIndexOf("/")) || "/");
        rebuild.restart();
    }
    function copyText(t) {
        Quickshell.execDetached(["wl-copy", "--", t]);
        say(I18n.tr("Copied"));
    }

    // ═════════════════════════ файловые операции
    function say(t) {
        toast = t;
        toastTimer.restart();
    }
    Timer {
        id: toastTimer
        interval: 3000
        onTriggered: br.toast = ""
    }

    function fileUris(paths) {
        return paths.map(p => "file://" + p.split("/").map(encodeURIComponent).join("/"));
    }
    // копировать/вырезать: и себе, и в системный буфер (другие окна, GTK-программы и браузеры поймут)
    function copySel(cut) {
        if (!selPaths.length || mode === "trash") return;
        clip = { mode: cut ? "move" : "copy", paths: selPaths };
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy --type x-special/gnome-copied-files', "sh",
                                 (cut ? "cut" : "copy") + "\n" + fileUris(selPaths).join("\n")]);
        say(selPaths.length === 1 ? `«${selItems[0]?.name ?? ""}» ${I18n.tr(cut ? "will be moved" : "will be copied")}`
                                  : `${I18n.tr(cut ? "Cut" : "Copied")}: ${selPaths.length}`);
    }
    property string pasteTarget: ""
    function paste() {
        if (mode !== "dir") return;
        pasteTarget = path;
        pasteProc.running = true;
    }
    // вставка: системный буфер (скопированное в другом окне, браузере, Telegram…), иначе свой
    Process {
        id: pasteProc
        command: ["sh", "-c", 'wl-paste -n -t x-special/gnome-copied-files 2>/dev/null || wl-paste -n -t text/uri-list 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split(/\r?\n/).map(l => l.trim()).filter(l => l);
                let m = "copy", paths = [];
                if (lines.length && (lines[0] === "copy" || lines[0] === "cut")) {
                    m = lines[0] === "cut" ? "move" : "copy";
                    lines.shift();
                }
                paths = lines.filter(l => l.startsWith("file://")).map(l => decodeURIComponent(l.slice(7)));
                if (!paths.length && br.clip.paths.length) { m = br.clip.mode; paths = br.clip.paths; }
                if (!paths.length) { br.say(I18n.tr("Nothing to paste")); return; }
                br.transfer(m, paths, br.pasteTarget || br.path);
                if (m === "move") br.clip = { mode: "", paths: [] };
            }
        }
    }
    function transfer(m, paths, dest) {
        if (jobProc.running) { say(I18n.tr("Wait for the current operation")); return; }
        job = { title: I18n.tr(m === "move" ? "Moving" : "Copying") + (paths.length === 1 ? ` «${paths[0].split("/").pop()}»` : ` (${paths.length})`), done: 0, total: 0 };
        jobProc.command = ["python3", helper, m, dest].concat(paths);
        jobProc.running = true;
    }
    Process {
        id: jobProc
        stdout: SplitParser {
            onRead: line => {
                let o = null;
                try { o = JSON.parse(line); } catch (e) { return; }
                if (o.error) br.say(o.error);
                else if (br.job) br.job = Object.assign({}, br.job, { done: o.done, total: o.total });
            }
        }
        onExited: {
            br.job = null;
            br.refresh();
        }
    }
    function cancelJob() {
        jobProc.signal(15);
    }

    function trashSel() {
        if (!selPaths.length) return;
        // в корзине и на телефоне (WebDAV) корзины нет — только удалить
        if (mode === "trash" || path.includes("/gvfs/")) { askDelete(); return; }
        const n = selPaths.length, first = selItems[0]?.name ?? "";
        runSimple(["python3", helper, "trash"].concat(selPaths), n === 1 ? `«${first}» ${I18n.tr("moved to the trash")}` : `${I18n.tr("Moved to trash")}: ${n}`);
        clearSel();
    }
    function askDelete() {
        if (!selPaths.length) return;
        const n = selPaths.length;
        confirm = {
            title: n === 1 ? `${I18n.tr("Permanently delete")} «${selItems[0]?.name ?? ""}»?`
                           : `${I18n.tr("Permanently delete")} ${n} ${I18n.plural(n, "item", "items", "объект", "объекта", "объектов")}?`,
            body: I18n.tr("If you delete an item, it will be permanently lost."),
            action: I18n.tr("Delete"),
            act: () => deleteSel(),
        };
    }
    function askEmptyTrash() {
        confirm = {
            title: I18n.tr("Empty all items from Trash?"),
            body: I18n.tr("All items in the Trash will be permanently deleted."),
            action: I18n.tr("Empty Trash"),
            act: () => emptyTrash(),
        };
    }
    function deleteSel() {
        if (!selPaths.length) return;
        if (mode === "trash")
            runSimple(["sh", "-c", 'for f; do rm -rf -- "$f"; rm -f -- "$HOME/.local/share/Trash/info/$(basename -- "$f").trashinfo"; done', "sh"].concat(selPaths),
                      I18n.tr("Deleted") + `: ${selPaths.length}`);
        else runSimple(["rm", "-rf", "--"].concat(selPaths), I18n.tr("Deleted") + `: ${selPaths.length}`);
        clearSel();
    }
    function restoreSel() {
        if (mode !== "trash" || !selPaths.length) return;
        runSimple(["python3", helper, "restore"].concat(selItems.map(i => i.name)), I18n.tr("Restored") + `: ${selPaths.length}`);
        clearSel();
    }
    function emptyTrash() {
        runSimple(["gio", "trash", "--empty"], I18n.tr("Trash emptied"));
    }
    function runSimple(cmd, okText) {
        simple.okText = okText;
        simple.command = cmd;
        simple.running = true;
    }
    Process {
        id: simple
        property string okText: ""
        stderr: StdioCollector { id: simpleErr }
        onExited: code => {
            const t = code === 0 ? simple.okText : (simpleErr.text.trim().split("\n").pop() || I18n.tr("Failed"));
            if (t) br.say(t);
            br.refresh();
        }
    }

    // ── новая папка, переименование
    function freeName(base) {
        const names = new Set(items.map(i => i.name));
        if (!names.has(base)) return base;
        let n = 2;
        while (names.has(`${base} ${n}`)) n++;
        return `${base} ${n}`;
    }
    function newFolder() {
        if (mode !== "dir") return;
        const p = `${path}/${freeName(I18n.tr("New Folder"))}`;
        pendingSelect = p;
        pendingRename = true;
        Quickshell.execDetached(["mkdir", "-p", p]);
    }
    function rename(it, name) {
        renaming = "";
        name = name.trim();
        if (!name || name === it.name || name.includes("/")) return;
        const dst = it.path.substring(0, it.path.lastIndexOf("/") + 1) + name;
        pendingSelect = dst;
        runSimple(["mv", "-n", "--", it.path, dst], "");
    }

    // ── закладки GTK (их видят окна выбора файлов)
    function bookmark(p) {
        if (isBookmarked(p)) { say(I18n.tr("Already in bookmarks")); return; }
        runSimple(["sh", "-c", 'mkdir -p ~/.config/gtk-3.0; grep -qxF "$1" ~/.config/gtk-3.0/bookmarks 2>/dev/null || printf "%s\\n" "$1" >> ~/.config/gtk-3.0/bookmarks', "sh",
                   fileUris([p])[0]], I18n.tr("Added to bookmarks"));
    }
    function unbookmark(p) {
        runSimple(["sh", "-c", 'f=~/.config/gtk-3.0/bookmarks; [ -f "$f" ] && grep -v "^$1\\( \\|$\\)" "$f" > "$f.tmp"; mv "$f.tmp" "$f"', "sh",
                   fileUris([p])[0]], I18n.tr("Removed from bookmarks"));
    }

    // ── архивы
    function compress(fmt) {
        if (!selPaths.length) return;
        const base = selPaths.length === 1 ? selItems[0].name.replace(/\.[^.\/]+$/, "") || selItems[0].name : I18n.tr("Archive");
        const out = `${path}/${freeName(base + "." + fmt).replace("." + fmt + " ", " ")}`;
        runSimple(["python3", helper, "compress", out.endsWith("." + fmt) ? out : out + "." + fmt].concat(selPaths), I18n.tr("Archive created"));
    }
    function extract(it) {
        runSimple(["python3", helper, "extract", it.path, path], I18n.tr("Extracted"));
    }
    function isArchive(name) {
        return /\.(zip|7z|rar|tar|tgz|tar\.(gz|xz|zst|bz2))$/i.test(name);
    }
    function isImage(name) {
        return /\.(png|jpe?g|webp|gif|bmp|svg|avif|tiff?|ico|jxl)$/i.test(name);
    }

    // ── телефон (Rexlink): память как папка через WebDAV и gvfs
    function phonePath(dev) {
        const u = dev?.files?.uri ?? "";
        const m = /^dav:\/\/[^@]*@([^:\/]+):(\d+)/.exec(u);
        if (!m) return "";
        return (places.remote ?? []).find(r => r.includes(`host=${m[1]}`) && r.includes(`port=${m[2]}`)) ?? "";
    }
    property string waitPhone: ""      // id устройства, которое ждём (включили доступ к файлам)
    function openPhone(dev) {
        const p = phonePath(dev);
        if (p) { go(p); return; }
        if (!(Rexlink.settings.phoneFiles ?? false)) Rexlink.set("phoneFiles", true);
        waitPhone = dev.id;
        say(I18n.tr("Opening the phone storage…"));
        placesProc.running = true;
    }
    Connections {
        target: Rexlink
        function onDevicesChanged() {
            placesProc.running = true;
        }
    }
    onPlacesChanged: if (waitPhone) {
        const d = Rexlink.devices.find(x => x.id === waitPhone);
        const p = phonePath(d);
        if (p) { waitPhone = ""; go(p); }
        else if (d?.files?.state === "permission") { waitPhone = ""; say(I18n.tr("Allow «All files» in Rexlink on the phone")); }
    }
    // ── диски и флешки
    property string waitDrive: ""
    function openDrive(d) {
        if (d.mount) { go(d.mount); return; }
        waitDrive = d.dev;
        Drives.mount(d.dev, false);
    }
    function leaveDrive(d) {
        if (d.mount && mode === "dir" && (path === d.mount || path.startsWith(d.mount + "/"))) go(home);
    }
    function unmountDrive(d) {
        leaveDrive(d);
        Drives.unmount(d.dev);
    }
    function ejectDrive(d) {
        leaveDrive(d);
        Drives.eject(d);
    }
    Connections {
        target: Drives
        function onMounted(dev, p) {
            if (dev === br.waitDrive && p) br.go(p);
            br.waitDrive = "";
        }
    }

    function sendToPhone(dev) {
        const files = selItems.filter(i => !i.dir).map(i => i.path);
        if (!files.length) { say(I18n.tr("Pick files, not folders")); return; }
        Rexlink.sendFiles(files, dev.id);
        say(`${I18n.tr("Sending to")} ${dev.name}: ${files.length}`);
    }

    // ── размеры, даты
    function human(n) {
        if (n === undefined || n === null) return "";
        const u = I18n.ru ? ["байт", "КБ", "МБ", "ГБ", "ТБ"] : ["bytes", "kB", "MB", "GB", "TB"];
        let i = 0;
        while (n >= 1000 && i < u.length - 1) { n /= 1000; i++; }
        return `${i === 0 ? n : n < 10 ? n.toFixed(1) : Math.round(n)} ${u[i]}`.replace(".", I18n.ru ? "," : ".");
    }
    function when(d) {
        if (!d) return "";
        const now = new Date();
        const same = d.toDateString() === now.toDateString();
        const y = new Date(now);
        y.setDate(now.getDate() - 1);
        if (same) return Qt.locale(I18n.locale).toString(d, "HH:mm");
        if (d.toDateString() === y.toDateString()) return `${I18n.tr("Yesterday")} ${Qt.locale(I18n.locale).toString(d, "HH:mm")}`;
        return Qt.locale(I18n.locale).toString(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy");
    }
    // значок по типу
    function iconFor(it) {
        if (it.dir) {
            const p = (places.dirs ?? []).find(d => d.path === it.path);
            return p ? ({ home: "user-home", desktop: "user-desktop", documents: "folder-documents", download: "folder-download",
                          music: "folder-music", pictures: "folder-pictures", videos: "folder-videos" })[p.icon] ?? "folder" : "folder";
        }
        const ext = it.name.includes(".") ? it.name.split(".").pop().toLowerCase() : "";
        const map = {
            image: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "tif", "tiff", "ico", "jxl", "heic", "psd", "xcf", "kra"],
            video: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg", "3gp"],
            audio: ["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac", "wma", "mid"],
            pdf: ["pdf"],
            archive: ["zip", "7z", "rar", "tar", "gz", "xz", "zst", "bz2", "tgz", "deb", "rpm", "apk", "pkg", "jar"],
            script: ["sh", "bash", "zsh", "fish", "py", "js", "ts", "qml", "rs", "go", "c", "cpp", "h", "hpp", "java", "kt", "lua", "rb", "php", "nix", "kdl", "toml", "yaml", "yml", "json", "xml", "css", "conf", "ini"],
            html: ["html", "htm"],
            doc: ["doc", "docx", "odt", "rtf"],
            sheet: ["xls", "xlsx", "ods", "csv"],
            slides: ["ppt", "pptx", "odp"],
            font: ["ttf", "otf", "woff", "woff2"],
            exec: ["appimage", "exe", "msi", "bin", "run"],
            disk: ["iso", "img"],
        };
        const icons = { image: "image-x-generic", video: "video-x-generic", audio: "audio-x-generic", pdf: "x-office-document",
                        archive: "package-x-generic", script: "text-x-script", html: "text-html", doc: "x-office-document",
                        sheet: "x-office-spreadsheet", slides: "x-office-presentation", font: "font-x-generic",
                        exec: "application-x-executable", disk: "application-x-firmware" };
        for (const k in map) if (map[k].includes(ext)) return icons[k];
        return "text-x-generic";
    }

    // ═════════════════════════ раскладка
    function reveal(p) {
        pendingSelect = p;
        go(p.substring(0, p.lastIndexOf("/")) || "/");
        rebuild.restart();
    }
    Component.onCompleted: {
        Drives.refresh();
        if (revealPath) pendingSelect = revealPath;
        go(startPath || home, true);
        view.forceFocus();
        if (startPrefs) showPrefs = true;
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            Layout.fillHeight: true
            Layout.preferredWidth: 240
            visible: br.sidebarOn
            br: br
        }

        Rectangle {
            id: content
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: FStyle.view

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                HeaderBar {
                    Layout.fillWidth: true
                    br: br
                }

                // корзина: полоса с действиями, как AdwBanner
                Rectangle {
                    Layout.fillWidth: true
                    visible: br.mode === "trash" && br.trashItems.length > 0
                    implicitHeight: 50
                    color: FStyle.alpha(Theme.accent, 0.14)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 10
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Deleted files stay here until you empty the trash")
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: FStyle.ui
                            font.pixelSize: FStyle.fs
                        }
                        FButton { flat: false; text: I18n.tr("Restore"); off: !br.selPaths.length; onClicked: br.restoreSel() }
                        FButton { destructive: true; text: I18n.tr("Empty…"); onClicked: br.askEmptyTrash() }
                    }
                }

                FileGrid {
                    id: view
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    br: br
                }
            }

            // выделено — плашка внизу справа, как в Nautilus
            Rectangle {
                readonly property var s: br.selItems
                readonly property real size: s.filter(i => !i.dir).reduce((a, i) => a + (i.size ?? 0), 0)
                visible: s.length > 0 && !br.renaming
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                width: Math.min(selText.implicitWidth + 24, parent.width - 40)
                height: 30
                radius: 8
                color: FStyle.popover
                border.width: 1
                border.color: FStyle.sep
                Text {
                    id: selText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - 24)
                    elide: Text.ElideMiddle
                    text: parent.s.length === 1
                        ? `«${parent.s[0].name}» ${I18n.tr(parent.s[0].dir ? "selected (folder)" : "selected")}${parent.s[0].dir || br.mode === "trash" ? "" : ` (${br.human(parent.size)})`}`
                        : `${I18n.tr("Selected")}: ${parent.s.length}${parent.size ? ` (${br.human(parent.size)})` : ""}`
                    color: Theme.fg
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fsSmall + 1
                }
            }
        }
    }

    // ── поверх
    PreviewCard {
        anchors.fill: parent
        visible: br.showPreview
        br: br
    }
    InfoCard {
        anchors.fill: parent
        visible: !!br.info
        br: br
    }
    Prefs {
        anchors.fill: parent
        visible: br.showPrefs
        br: br
    }
    Shortcuts {
        anchors.fill: parent
        visible: br.showShortcuts
        br: br
    }

    // подтверждение — как AdwAlertDialog
    Item {
        anchors.fill: parent
        visible: !!br.confirm
        Rectangle {
            anchors.fill: parent
            color: FStyle.shade
            MouseArea { anchors.fill: parent; onClicked: br.confirm = null }
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 380)
            height: col.implicitHeight + 48
            radius: 14
            color: FStyle.card
            border.width: 1
            border.color: FStyle.sep
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: col
                anchors.fill: parent
                anchors.margins: 24
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: br.confirm?.title ?? ""
                    color: Theme.fg
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fs + 4
                    font.weight: Font.Bold
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: br.confirm?.body ?? ""
                    color: Theme.dim
                    font.family: FStyle.ui
                    font.pixelSize: FStyle.fs
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    spacing: 12
                    FButton {
                        Layout.fillWidth: true
                        flat: false
                        text: I18n.tr("Cancel")
                        onClicked: br.confirm = null
                    }
                    FButton {
                        Layout.fillWidth: true
                        destructive: true
                        text: br.confirm?.action ?? ""
                        onClicked: { const a = br.confirm?.act; br.confirm = null; a?.(); }
                    }
                }
            }
        }
    }

    // всплывающее сообщение — как AdwToast
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        visible: br.toast !== ""
        width: Math.min(toastText.implicitWidth + 40, parent.width - 60)
        height: 40
        radius: 20
        color: Theme.surfaceHi2
        border.width: 1
        border.color: FStyle.sep
        z: 90
        Text {
            id: toastText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 40)
            elide: Text.ElideMiddle
            text: br.toast
            color: Theme.fg
            font.family: FStyle.ui
            font.pixelSize: FStyle.fs
        }
    }

    // боковые кнопки мыши — назад / вперёд (остальные кнопки проходят дальше)
    MouseArea {
        anchors.fill: parent
        z: 50
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        onClicked: mouse => {
            if (mouse.button === Qt.BackButton) br.goBack();
            else br.goFwd();
        }
    }

    FileMenu {
        id: menu
        br: br
        onVisibleChanged: if (!visible) br.menuOwner = null
    }
    function popupMenu(x, y, list, alignRight) {
        menu.openAt(x, y, list, alignRight);
    }

    // ═════════════════════════ меню
    function mainMenu(x, y, owner, left) {
        menuOwner = owner;
        popupMenu(x, y, [
            { text: I18n.tr("New Window"), key: "Ctrl+N", act: () => newWindowRequested(mode === "dir" ? path : home) },
            { sep: true },
            { text: I18n.tr("Show Hidden Files"), key: "Ctrl+H", check: cfg.hidden ?? false, act: () => Settings.setFiles("hidden", !(cfg.hidden ?? false)) },
            { text: I18n.tr("Sidebar"), key: "F9", check: sidebarOn, act: () => Settings.setFiles("sidebar", !sidebarOn) },
            { sep: true },
            { text: I18n.tr("Preferences"), key: "Ctrl+,", act: () => showPrefs = true },
            { text: I18n.tr("Keyboard Shortcuts"), key: "Ctrl+?", act: () => showShortcuts = true },
        ], !left);
    }
    function locationMenu(x, y, owner) {
        menuOwner = owner;
        const dir = mode === "dir";
        const L = [
            { text: I18n.tr("New Folder…"), key: "Ctrl+Shift+N", off: !dir, act: () => newFolder() },
            { text: I18n.tr("Add to Bookmarks"), key: "Ctrl+D", off: !dir || isBookmarked(path), act: () => bookmark(path) },
            { sep: true },
            { text: I18n.tr("Paste"), key: "Ctrl+V", off: !dir, act: () => paste() },
            { text: I18n.tr("Select All"), key: "Ctrl+A", act: () => selectAll() },
            { sep: true },
            { text: I18n.tr("Open in Terminal"), off: !dir, act: () => openTerminal(path) },
            { text: I18n.tr("Copy Location"), off: !dir, act: () => copyText(path) },
        ];
        if (mode === "trash") L.push({ sep: true }, { text: I18n.tr("Empty Trash…"), danger: true, off: !trashItems.length, act: () => askEmptyTrash() });
        L.push({ sep: true }, { text: I18n.tr("Properties"), off: !dir, act: () => showInfo({ name: path.split("/").pop() || "/", path, dir: true }) });
        popupMenu(x, y, L, true);
    }
    function viewMenu(x, y, owner) {
        menuOwner = owner;
        const s = cfg.sort ?? "name", r = cfg.reverse ?? false;
        const opt = (k, rev, t) => ({ text: I18n.tr(t), check: s === k && r === rev, act: () => { Settings.setFiles("sort", k); Settings.setFiles("reverse", rev); } });
        popupMenu(x, y, [
            { zoom: true },
            { sep: true },
            { header: I18n.tr("Sort") },
            opt("name", false, "A–Z"), opt("name", true, "Z–A"),
            opt("time", false, "Last Modified"), opt("time", true, "First Modified"),
            opt("size", false, "Size"), opt("type", false, "Type"),
            { sep: true },
            { text: I18n.tr("Show Hidden Files"), key: "Ctrl+H", check: cfg.hidden ?? false, act: () => Settings.setFiles("hidden", !(cfg.hidden ?? false)) },
        ], true);
    }
    function jobMenu(x, y, owner) {
        menuOwner = owner;
        popupMenu(x, y, [{ job: true }], true);
    }
    // ── меню файла
    function itemMenu(x, y) {
        const its = selItems;
        if (!its.length) return;
        const one = its.length === 1 ? its[0] : null;
        const L = [];
        if (mode === "trash") {
            L.push({ text: I18n.tr("Restore From Trash"), act: () => restoreSel() });
            L.push({ text: I18n.tr("Delete Permanently…"), danger: true, act: () => askDelete() });
            popupMenu(x, y, L);
            return;
        }
        L.push({ text: I18n.tr("Open"), key: "Enter", act: () => { if (one) openItem(one); else for (const i of its) if (!i.dir) Quickshell.execDetached(["gio", "open", i.path]); } });
        if (one && one.dir) L.push({ text: I18n.tr("Open in New Window"), act: () => newWindowRequested(one.path) });
        if (one && !one.dir) L.push({ text: I18n.tr("Open With…"), openWith: one.path });
        if (one && one.dir) L.push({ text: I18n.tr("Open in Terminal"), act: () => openTerminal(one.path) });
        if (mode !== "dir" && one) L.push({ text: I18n.tr("Open Item Location"), act: () => revealItem(one) });
        L.push({ sep: true });
        L.push({ text: I18n.tr("Cut"), key: "Ctrl+X", act: () => copySel(true) });
        L.push({ text: I18n.tr("Copy"), key: "Ctrl+C", act: () => copySel(false) });
        if (one && one.dir) L.push({ text: I18n.tr("Paste Into Folder"), act: () => { pasteTarget = one.path; pasteProc.running = true; } });
        L.push({ sep: true });
        if (one && mode === "dir") L.push({ text: I18n.tr("Rename…"), key: "F2", act: () => renaming = one.path });
        const allStarred = its.every(i => isStarred(i.path));
        L.push({ text: I18n.tr(allStarred ? "Unstar" : "Star"), act: () => toggleStar(selPaths) });
        if (one && isArchive(one.name)) L.push({ text: I18n.tr("Extract Here"), act: () => extract(one) });
        if (mode === "dir") L.push({ text: I18n.tr("Compress to ZIP"), act: () => compress("zip") });
        if (one && isImage(one.name)) L.push({ text: I18n.tr("Set as Background"), act: () => { Wallpapers.apply(one.path); say(I18n.tr("Wallpaper set")); } });
        L.push({ text: I18n.tr("Copy Location"), act: () => copyText(selPaths.join("\n")) });
        // телефон, планшет: отправить файлы (Rexlink)
        const devs = (Rexlink.connected ? Rexlink.devices : []).filter(d => d.online);
        if (devs.length) L.push({ sep: true });
        for (const d of devs)
            L.push({ text: `${I18n.tr("Send to")} ${d.name}`, off: !its.some(i => !i.dir), act: () => sendToPhone(d) });
        L.push({ sep: true });
        L.push({ text: I18n.tr("Move to Trash"), key: "Delete", act: () => trashSel() });
        L.push({ text: I18n.tr("Delete Permanently…"), key: "Shift+Del", danger: true, act: () => askDelete() });
        L.push({ sep: true });
        L.push({ text: I18n.tr("Properties"), key: "Ctrl+I", act: () => showInfo(one ?? its[0]) });
        popupMenu(x, y, L);
    }
    // ── меню пустого места
    function folderMenu(x, y) {
        if (mode === "trash") {
            popupMenu(x, y, [{ text: I18n.tr("Empty Trash…"), danger: true, off: !trashItems.length, act: () => askEmptyTrash() }]);
            return;
        }
        if (mode !== "dir") {
            popupMenu(x, y, [{ text: I18n.tr("Select All"), key: "Ctrl+A", act: () => selectAll() }]);
            return;
        }
        popupMenu(x, y, [
            { text: I18n.tr("New Folder…"), key: "Ctrl+Shift+N", act: () => newFolder() },
            { text: I18n.tr("Paste"), key: "Ctrl+V", act: () => paste() },
            { text: I18n.tr("Select All"), key: "Ctrl+A", act: () => selectAll() },
            { sep: true },
            { text: I18n.tr("Open in Terminal"), act: () => openTerminal(path) },
            { text: I18n.tr("Add to Bookmarks"), key: "Ctrl+D", off: isBookmarked(path), act: () => bookmark(path) },
            { text: I18n.tr("Show Hidden Files"), key: "Ctrl+H", check: cfg.hidden ?? false, act: () => Settings.setFiles("hidden", !(cfg.hidden ?? false)) },
            { sep: true },
            { text: I18n.tr("Properties"), act: () => showInfo({ name: path.split("/").pop() || "/", path, dir: true }) },
        ]);
    }

    function showInfo(it) {
        info = { name: it.name, path: it.path, dir: it.dir, loading: true };
        infoProc.command = ["python3", helper, "info", it.path];
        infoProc.running = true;
    }
    Process {
        id: infoProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { br.info = Object.assign(JSON.parse(text), { loading: false }); } catch (e) { br.info = null; }
            }
        }
    }

    // ═════════════════════════ клавиатура. Esc закрывает диалоги, поиск и снимает выделение, но не окно
    function key(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        const alt = event.modifiers & Qt.AltModifier;
        const k = event.key;
        const it = shown[cur];
        if (renaming) return false;
        if (menu.visible) {
            if (k === Qt.Key_Escape) { menu.close(); return true; }
            return false;
        }
        if (confirm) {
            if (k === Qt.Key_Escape) { confirm = null; return true; }
            if (k === Qt.Key_Return || k === Qt.Key_Enter) { const a = confirm.act; confirm = null; a?.(); return true; }
            return true;
        }
        if (showPrefs || showShortcuts || info) {
            if (k === Qt.Key_Escape) { showPrefs = false; showShortcuts = false; info = null; return true; }
            if (ctrl && k === Qt.Key_W) { closeRequested(); return true; }
            return true;
        }
        if (showPreview) {
            if (k === Qt.Key_Space || k === Qt.Key_Escape) { showPreview = false; return true; }
            if (k === Qt.Key_Left || k === Qt.Key_Up) { moveCur(-1, false); return true; }
            if (k === Qt.Key_Right || k === Qt.Key_Down) { moveCur(1, false); return true; }
            return false;
        }
        // окна и диалоги
        if (ctrl && k === Qt.Key_N && !shift) { newWindowRequested(mode === "dir" ? path : home); return true; }
        if (ctrl && k === Qt.Key_W) { closeRequested(); return true; }
        if (ctrl && k === Qt.Key_Q) { quitRequested(); return true; }
        if (ctrl && k === Qt.Key_Comma) { showPrefs = true; return true; }
        if ((ctrl && k === Qt.Key_Question) || (ctrl && shift && k === Qt.Key_Slash) || k === Qt.Key_F1) { showShortcuts = true; return true; }
        if (k === Qt.Key_F9) { Settings.setFiles("sidebar", !sidebarOn); return true; }
        // файлы
        if (ctrl && k === Qt.Key_C) { copySel(false); return true; }
        if (ctrl && k === Qt.Key_X) { copySel(true); return true; }
        if (ctrl && k === Qt.Key_V) { paste(); return true; }
        if (ctrl && k === Qt.Key_A) { selectAll(); return true; }
        if (ctrl && k === Qt.Key_H) { Settings.setFiles("hidden", !(cfg.hidden ?? false)); return true; }
        if (ctrl && k === Qt.Key_L) { topBar().editPath(); return true; }
        if (ctrl && k === Qt.Key_F) { topBar().focusSearch(); return true; }
        if (ctrl && k === Qt.Key_D && mode === "dir") { bookmark(path); return true; }
        if (ctrl && shift && k === Qt.Key_N) { newFolder(); return true; }
        if (ctrl && k === Qt.Key_1) { Settings.setFiles("view", "grid"); return true; }
        if (ctrl && k === Qt.Key_2) { Settings.setFiles("view", "list"); return true; }
        if (ctrl && (k === Qt.Key_Plus || k === Qt.Key_Equal)) { zoomBy(1); return true; }
        if (ctrl && k === Qt.Key_Minus) { zoomBy(-1); return true; }
        if (ctrl && k === Qt.Key_0) { Settings.setFiles("zoom", 1); return true; }
        if (((ctrl && k === Qt.Key_I) || (alt && (k === Qt.Key_Return || k === Qt.Key_Enter))) && it) { showInfo(selItems.length === 1 ? selItems[0] : it); return true; }
        if ((ctrl && k === Qt.Key_R) || k === Qt.Key_F5) { refresh(); return true; }
        if (alt && k === Qt.Key_Left) { goBack(); return true; }
        if (alt && k === Qt.Key_Right) { goFwd(); return true; }
        if (alt && k === Qt.Key_Home) { go(home); return true; }
        if ((alt && k === Qt.Key_Up) || k === Qt.Key_Backspace) { up(); return true; }
        if (k === Qt.Key_F2 && selItems.length === 1 && mode === "dir") { renaming = selItems[0].path; return true; }
        if (k === Qt.Key_Delete) { if (shift) askDelete(); else trashSel(); return true; }
        if (k === Qt.Key_Space && shown.length) { if (!it) selectOnly(0); showPreview = true; return true; }
        if ((k === Qt.Key_Return || k === Qt.Key_Enter) && it) {
            if (selItems.length > 1) for (const s of selItems) { if (!s.dir) Quickshell.execDetached(["gio", "open", s.path]); }
            else openItem(it);
            return true;
        }
        if (k === Qt.Key_Escape) {
            if (searchOpen || filter) { topBar().clearSearch(); return true; }
            if (selPaths.length) { clearSel(); return true; }
            return true;
        }
        const cols = view.columns;
        if (k === Qt.Key_Right) { moveCur(1, shift); return true; }
        if (k === Qt.Key_Left) { moveCur(-1, shift); return true; }
        if (k === Qt.Key_Down) { moveCur(cols, shift); return true; }
        if (k === Qt.Key_Up) { moveCur(-cols, shift); return true; }
        if (k === Qt.Key_Home) { moveCur(-cur, shift); return true; }
        if (k === Qt.Key_End) { moveCur(shown.length, shift); return true; }
        // набор букв — поиск, как в Nautilus
        if (event.text && /\S/.test(event.text) && !ctrl && !alt) {
            topBar().focusSearch(event.text);
            return true;
        }
        return false;
    }
    function topBar() {
        return topBarItem;
    }
    property var topBarItem: null

    function forceViewFocus() {
        view.forceFocus();
    }
}
