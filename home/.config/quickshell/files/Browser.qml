import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.services
import qs.screenshot

// проводник: боковая панель (места, устройства и телефон через Rexlink, закладки), путь, файлы сеткой или списком.
// Операции с файлами — scripts/files.py (копирование с прогрессом, корзина, поиск, архивы, «Открыть в…»).
Item {
    id: br

    property string startPath: ""
    property string revealPath: ""        // выделить этот файл после открытия
    signal closeRequested

    readonly property string home: Quickshell.env("HOME")
    readonly property string helper: Quickshell.shellDir + "/scripts/files.py"
    readonly property var cfg: Settings.files ?? {}

    // ── где мы
    property string path: ""
    property string mode: "dir"        // dir | search | trash
    property var back: []
    property var fwd: []
    property var places: ({ dirs: [], bookmarks: [], drives: [], trash: 0, remote: [] })

    // ── что показываем: [{ name, path, dir, size, mtime, sub? }]
    property var items: []
    property var searchItems: []
    property var trashItems: []
    property string filter: ""          // быстрый фильтр по имени в текущей папке
    property bool searching: false
    readonly property var shown: {
        if (mode === "search") return searchItems;
        if (mode === "trash") return trashItems;
        const q = filter.trim().toLowerCase();
        return q ? items.filter(i => i.name.toLowerCase().includes(q)) : items;
    }

    // ── выделение
    property var sel: ({})
    property int cur: -1                // элемент под «курсором» клавиатуры
    property int anchorIdx: -1
    readonly property var selPaths: Object.keys(sel)
    readonly property var selItems: shown.filter(i => sel[i.path])

    // ── буфер, переименование, операция
    property var clip: ({ mode: "", paths: [] })
    property string renaming: ""
    property var job: null              // { title, done, total }
    property string toast: ""
    property bool showPreview: false
    property var info: null             // свойства
    property bool confirmDelete: false
    property string freeSpace: ""

    // ═════════════════════════ навигация
    function norm(p) {
        p = p.replace(/\/+$/, "");
        return p || "/";
    }
    function go(p, keepHistory) {
        p = norm(p);
        if (mode === "dir" && p === path) return;
        if (!keepHistory && path) {
            back = back.concat([{ path, mode }]).slice(-50);
            fwd = [];
        }
        mode = "dir";
        path = p;
        filter = "";
        searching = false;
        clearSel();
        renaming = "";
        freeProc.running = true;
    }
    function goBack() {
        if (!back.length) return;
        fwd = fwd.concat([{ path, mode }]);
        const b = back[back.length - 1];
        back = back.slice(0, -1);
        if (b.mode === "trash") openTrash(true);
        else go(b.path, true);
    }
    function goFwd() {
        if (!fwd.length) return;
        back = back.concat([{ path, mode }]);
        const f = fwd[fwd.length - 1];
        fwd = fwd.slice(0, -1);
        if (f.mode === "trash") openTrash(true);
        else go(f.path, true);
    }
    function up() {
        if (mode !== "dir") { go(path); return; }
        if (path === "/") return;
        go(path.substring(0, path.lastIndexOf("/")) || "/");
    }
    function openTrash(keepHistory) {
        if (!keepHistory && mode !== "trash") {
            back = back.concat([{ path, mode }]).slice(-50);
            fwd = [];
        }
        mode = "trash";
        clearSel();
        trashProc.running = true;
    }
    function refresh() {
        if (mode === "trash") trashProc.running = true;
        else if (mode === "search") runSearch();
        else rebuild.restart();
        placesProc.running = true;
        freeProc.running = true;
    }

    // ── папка
    FolderListModel {
        id: fm
        folder: br.mode === "dir" && br.path ? "file://" + br.path : ""
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
            // выделение — только то, что ещё есть
            const s = {};
            for (const p in br.sel) if (a.some(x => x.path === p)) s[p] = true;
            br.sel = s;
            if (br.pendingSelect) {
                const i = a.findIndex(x => x.path === br.pendingSelect);
                if (i >= 0) {
                    br.sel = { [br.pendingSelect]: true };
                    br.cur = i;
                    if (br.pendingRename) br.renaming = br.pendingSelect;
                    br.pendingSelect = "";
                    br.pendingRename = false;
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
    Process {
        id: freeProc
        command: ["sh", "-c", 'df -h --output=avail "$1" 2>/dev/null | tail -1', "sh", br.path || "/"]
        stdout: StdioCollector { onStreamFinished: br.freeSpace = text.trim() }
    }

    // ── корзина
    Process {
        id: trashProc
        command: ["python3", br.helper, "trashlist"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = [];
                try { l = JSON.parse(text); } catch (e) {}
                br.trashItems = l.map(t => ({ name: t.name, path: t.path, dir: t.dir, size: 0, mtime: t.date ? new Date(t.date) : null,
                                              sub: t.orig ? t.orig.substring(0, t.orig.lastIndexOf("/")).replace(br.home, "~") : "" }));
            }
        }
    }

    // ── поиск во вложенных папках
    function runSearch() {
        const q = filter.trim();
        if (!q) return;
        if (mode !== "search") {
            back = back.concat([{ path, mode }]).slice(-50);
            fwd = [];
        }
        mode = "search";
        searchItems = [];
        clearSel();
        searchProc.command = ["python3", helper, "search", path, q];
        searchProc.running = true;
    }
    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                let l = [];
                try { l = JSON.parse(text); } catch (e) {}
                br.searchItems = l.map(r => ({ name: r.name, path: r.path, dir: r.dir, size: r.size, mtime: new Date(r.mtime * 1000),
                                               sub: r.path.substring(0, r.path.lastIndexOf("/")).replace(br.path, ".") }));
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
    // клик мышью: обычный / Ctrl / Shift
    function clickItem(i, mods) {
        if (mods & Qt.ShiftModifier) rangeSel(i);
        else if (mods & Qt.ControlModifier) toggleSel(i);
        else selectOnly(i);
    }
    function moveCur(delta, shift) {
        if (!shown.length) return;
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

    // ═════════════════════════ файловые операции
    function say(t) {
        toast = t;
        toastTimer.restart();
    }
    Timer {
        id: toastTimer
        interval: 2600
        onTriggered: br.toast = ""
    }

    function fileUris(paths) {
        return paths.map(p => "file://" + p.split("/").map(encodeURIComponent).join("/"));
    }
    // копировать/вырезать: и себе, и в системный буфер (GTK-программы и браузеры поймут)
    function copySel(cut) {
        if (!selPaths.length || mode === "trash") return;
        clip = { mode: cut ? "move" : "copy", paths: selPaths };
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy --type x-special/gnome-copied-files', "sh",
                                 (cut ? "cut" : "copy") + "\n" + fileUris(selPaths).join("\n")]);
        say(I18n.tr(cut ? "Cut" : "Copied") + `: ${selPaths.length}`);
    }
    property string pasteTarget: ""
    function paste() {
        if (mode !== "dir") return;
        pasteTarget = path;
        pasteProc.running = true;
    }
    // вставка: свой буфер, иначе системный (скопированное в браузере, Telegram…)
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
        if (mode === "trash") { confirmDelete = true; return; }
        // на телефоне (WebDAV) корзины нет — только удалить
        if (path.includes("/gvfs/")) { confirmDelete = true; return; }
        runSimple(["python3", helper, "trash"].concat(selPaths), I18n.tr("Moved to trash") + `: ${selPaths.length}`);
        clearSel();
    }
    function deleteSel() {
        confirmDelete = false;
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
            br.say(code === 0 ? simple.okText : (simpleErr.text.trim().split("\n").pop() || I18n.tr("Failed")));
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
        const p = `${path}/${freeName(I18n.tr("New folder"))}`;
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
        const u = I18n.ru ? ["Б", "КБ", "МБ", "ГБ", "ТБ"] : ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
        return `${n < 10 && i ? n.toFixed(1) : Math.round(n)} ${u[i]}`;
    }
    function when(d) {
        if (!d) return "";
        const now = new Date();
        const same = d.toDateString() === now.toDateString();
        return Qt.locale(I18n.locale).toString(d, same ? "HH:mm" : d.getFullYear() === now.getFullYear() ? "d MMM, HH:mm" : "d MMM yyyy");
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
        const dir = p.substring(0, p.lastIndexOf("/")) || "/";
        pendingSelect = p;
        go(dir);
        rebuild.restart();
    }
    Component.onCompleted: {
        Drives.refresh();
        if (revealPath) pendingSelect = revealPath;
        go(startPath || home, true);
        view.forceFocus();
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            Layout.fillHeight: true
            Layout.preferredWidth: 230
            visible: br.cfg.sidebar ?? true
            br: br
        }

        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 1
            color: Theme.surfaceHi2
            visible: br.cfg.sidebar ?? true
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            TopBar {
                Layout.fillWidth: true
                br: br
            }

            // корзина: действия
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                visible: br.mode === "trash"
                implicitHeight: 46
                radius: 12
                color: Theme.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 6
                    Text {
                        Layout.fillWidth: true
                        text: br.trashItems.length ? I18n.tr("Deleted files stay here until you empty the trash") : I18n.tr("The trash is empty")
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                    ToolButton { label: "Restore"; icon: 0xF0A8B; off: !br.selPaths.length; onClicked: br.restoreSel() }
                    ToolButton { label: "Empty trash"; icon: 0xF0A7A; off: !br.trashItems.length; onClicked: br.emptyTrash() }
                }
            }

            FileGrid {
                id: view
                Layout.fillWidth: true
                Layout.fillHeight: true
                br: br
            }

            StatusBar {
                Layout.fillWidth: true
                br: br
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

    // подтверждение удаления навсегда
    Rectangle {
        anchors.fill: parent
        visible: br.confirmDelete
        color: Qt.rgba(0, 0, 0, 0.45)
        MouseArea { anchors.fill: parent; onClicked: br.confirmDelete = false }

        Rectangle {
            anchors.centerIn: parent
            width: 420
            height: col.implicitHeight + 40
            radius: 16
            color: Theme.surface
            border.width: 1
            border.color: Theme.line

            ColumnLayout {
                id: col
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14
                Text {
                    Layout.fillWidth: true
                    text: `${I18n.tr("Delete permanently")}: ${br.selPaths.length}?`
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 3
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: I18n.tr("This can't be undone")
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    ToolButton { label: "Cancel"; onClicked: br.confirmDelete = false }
                    ToolButton { label: "Delete"; icon: 0xF01B4; active: true; onClicked: br.deleteSel() }
                }
            }
        }
    }

    // всплывающая подсказка
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 46
        visible: br.toast !== ""
        width: toastText.implicitWidth + 28
        height: 36
        radius: 11
        color: Theme.surfaceHi2
        border.width: 1
        border.color: Theme.line
        Text {
            id: toastText
            anchors.centerIn: parent
            text: br.toast
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
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
    }
    function popupMenu(x, y, onItem) {
        menu.openAt(x, y, onItem);
    }

    // ═════════════════════════ клавиатура
    function key(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        const alt = event.modifiers & Qt.AltModifier;
        const k = event.key;
        const it = shown[cur];
        if (renaming) return false;
        if (showPreview) {
            if (k === Qt.Key_Space || k === Qt.Key_Escape) { showPreview = false; return true; }
            if (k === Qt.Key_Left || k === Qt.Key_Up) { moveCur(-1, false); return true; }
            if (k === Qt.Key_Right || k === Qt.Key_Down) { moveCur(1, false); return true; }
            return false;
        }
        if (info || confirmDelete) {
            if (k === Qt.Key_Escape) { info = null; confirmDelete = false; return true; }
            if (confirmDelete && (k === Qt.Key_Return || k === Qt.Key_Enter)) { deleteSel(); return true; }
            return false;
        }
        if (ctrl && k === Qt.Key_W) { closeRequested(); return true; }
        if (ctrl && k === Qt.Key_C) { copySel(false); return true; }
        if (ctrl && k === Qt.Key_X) { copySel(true); return true; }
        if (ctrl && k === Qt.Key_V) { paste(); return true; }
        if (ctrl && k === Qt.Key_A) { selectAll(); return true; }
        if (ctrl && k === Qt.Key_H) { Settings.setFiles("hidden", !(cfg.hidden ?? false)); return true; }
        if (ctrl && k === Qt.Key_L) { topBar().editPath(); return true; }
        if (ctrl && k === Qt.Key_F) { topBar().focusSearch(); return true; }
        if (ctrl && shift && k === Qt.Key_N) { newFolder(); return true; }
        if (ctrl && k === Qt.Key_1) { Settings.setFiles("view", "grid"); return true; }
        if (ctrl && k === Qt.Key_2) { Settings.setFiles("view", "list"); return true; }
        if (ctrl && (k === Qt.Key_Plus || k === Qt.Key_Equal)) { Settings.setFiles("zoom", Math.min(2, (cfg.zoom ?? 1) + 0.25)); return true; }
        if (ctrl && k === Qt.Key_Minus) { Settings.setFiles("zoom", Math.max(0.5, (cfg.zoom ?? 1) - 0.25)); return true; }
        if (ctrl && k === Qt.Key_I && it) { showInfo(selItems.length === 1 ? selItems[0] : it); return true; }
        if (alt && k === Qt.Key_Left) { goBack(); return true; }
        if (alt && k === Qt.Key_Right) { goFwd(); return true; }
        if ((alt && k === Qt.Key_Up) || k === Qt.Key_Backspace) { up(); return true; }
        if (k === Qt.Key_F5) { refresh(); return true; }
        if (k === Qt.Key_F2 && selItems.length === 1 && mode === "dir") { renaming = selItems[0].path; return true; }
        if (k === Qt.Key_Delete) { if (shift) confirmDelete = !!selPaths.length; else trashSel(); return true; }
        if (k === Qt.Key_Space && shown.length) { if (!it) selectOnly(0); showPreview = true; return true; }
        if ((k === Qt.Key_Return || k === Qt.Key_Enter) && it) {
            if (selItems.length > 1) for (const s of selItems) { if (!s.dir) Quickshell.execDetached(["gio", "open", s.path]); }
            else openItem(it);
            return true;
        }
        if (k === Qt.Key_Escape) {
            if (filter || mode === "search") { topBar().clearSearch(); return true; }
            if (selPaths.length) { clearSel(); return true; }
            closeRequested();
            return true;
        }
        const cols = view.columns;
        if (k === Qt.Key_Right) { moveCur(1, shift); return true; }
        if (k === Qt.Key_Left) { moveCur(-1, shift); return true; }
        if (k === Qt.Key_Down) { moveCur(cols, shift); return true; }
        if (k === Qt.Key_Up) { moveCur(-cols, shift); return true; }
        if (k === Qt.Key_Home) { moveCur(-cur, shift); return true; }
        if (k === Qt.Key_End) { moveCur(shown.length, shift); return true; }
        // набор букв — перейти к файлу с таким началом
        if (event.text && /\S/.test(event.text) && !ctrl && !alt) {
            typed += event.text.toLowerCase();
            typedTimer.restart();
            const i = shown.findIndex(x => x.name.toLowerCase().startsWith(typed));
            if (i >= 0) { selectOnly(i); view.positionAt(i); }
            return true;
        }
        return false;
    }
    property string typed: ""
    Timer {
        id: typedTimer
        interval: 900
        onTriggered: br.typed = ""
    }
    function topBar() {
        return topBarItem;
    }
    property var topBarItem: null

    function forceViewFocus() {
        view.forceFocus();
    }
    // открывать папки этим проводником : «Открыть папку» в браузере, Telegram и т. д.
    function makeDefault() {
        runSimple(["xdg-mime", "default", "rexilone-files.desktop", "inode/directory"], I18n.tr("Folders now open here"));
    }

    // ── меню файла
    function itemMenu(x, y) {
        const its = selItems;
        if (!its.length) return;
        const one = its.length === 1 ? its[0] : null;
        const L = [];
        if (mode === "trash") {
            L.push({ icon: 0xF0A8B, text: "Restore", act: () => restoreSel() });
            L.push({ icon: 0xF01B4, text: "Delete permanently", danger: true, act: () => confirmDelete = true });
            popupMenu(x, y, L);
            return;
        }
        L.push({ icon: 0xF0DCE, text: "Open", key: "Enter", act: () => { if (one) openItem(one); else for (const i of its) if (!i.dir) Quickshell.execDetached(["gio", "open", i.path]); } });
        if (one && !one.dir) L.push({ icon: 0xF0DCE, text: "Open with…", openWith: one.path });
        if (one && one.dir) L.push({ icon: 0xF018D, text: "Open terminal here", act: () => openTerminal(one.path) });
        if (mode === "search" && one) L.push({ icon: 0xF024B, text: "Show in folder", act: () => { const d = one.path.substring(0, one.path.lastIndexOf("/")); pendingSelect = one.path; go(d); } });
        L.push({ sep: true });
        L.push({ icon: 0xF0190, text: "Cut", key: "Ctrl+X", act: () => copySel(true) });
        L.push({ icon: 0xF018F, text: "Copy", key: "Ctrl+C", act: () => copySel(false) });
        if (one && one.dir) L.push({ icon: 0xF0192, text: "Paste into the folder", act: () => { pasteTarget = one.path; pasteProc.running = true; } });
        if (one) L.push({ icon: 0xF0CB6, text: "Rename", key: "F2", off: mode !== "dir", act: () => renaming = one.path });
        L.push({ icon: 0xF014D, text: "Copy path", act: () => { Quickshell.execDetached(["wl-copy", "--", selPaths.join("\n")]); say(I18n.tr("Copied")); } });
        if (one && isImage(one.name)) L.push({ icon: 0xF0E09, text: "Set as wallpaper", act: () => { Wallpapers.apply(one.path); say(I18n.tr("Wallpaper set")); } });
        // телефон, планшет: отправить файлы (Rexlink)
        for (const d of (Rexlink.connected ? Rexlink.devices : []).filter(d => d.online))
            L.push({ icon: d.kind === "tablet" ? 0xF04F7 : 0xF011C, text: `${I18n.tr("Send to")} ${d.name}`, off: !its.some(i => !i.dir), act: () => sendToPhone(d) });
        L.push({ sep: true });
        if (one && isArchive(one.name)) L.push({ icon: 0xF0D5F, text: "Extract here", act: () => extract(one) });
        L.push({ icon: 0xF05C4, text: "Compress to ZIP", act: () => compress("zip") });
        if (one && one.dir) L.push({ icon: 0xF0C5A, text: "Add to bookmarks", act: () => bookmark(one.path) });
        L.push({ sep: true });
        L.push({ icon: 0xF0A7A, text: "Move to trash", key: "Delete", act: () => trashSel() });
        L.push({ icon: 0xF01B4, text: "Delete permanently", key: "Shift+Del", danger: true, act: () => confirmDelete = true });
        L.push({ sep: true });
        L.push({ icon: 0xF02FD, text: "Properties", key: "Ctrl+I", act: () => showInfo(one ?? its[0]) });
        popupMenu(x, y, L);
    }
    // ── меню пустого места
    function folderMenu(x, y) {
        if (mode === "trash") {
            popupMenu(x, y, [{ icon: 0xF0A7A, text: "Empty trash", off: !trashItems.length, act: () => emptyTrash() }]);
            return;
        }
        popupMenu(x, y, [
            { icon: 0xF0257, text: "New folder", key: "Ctrl+Shift+N", off: mode !== "dir", act: () => newFolder() },
            { icon: 0xF0192, text: "Paste", key: "Ctrl+V", off: mode !== "dir", act: () => paste() },
            { icon: 0xF0489, text: "Select all", key: "Ctrl+A", act: () => selectAll() },
            { sep: true },
            { icon: 0xF018D, text: "Open terminal here", act: () => openTerminal(path) },
            { icon: 0xF0C5A, text: "Add to bookmarks", off: mode !== "dir", act: () => bookmark(path) },
            { text: "Hidden files", key: "Ctrl+H", check: cfg.hidden ?? false, act: () => Settings.setFiles("hidden", !(cfg.hidden ?? false)) },
            { sep: true },
            { icon: 0xF02FD, text: "Properties", act: () => showInfo({ name: path.split("/").pop() || "/", path, dir: true }) },
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
}
