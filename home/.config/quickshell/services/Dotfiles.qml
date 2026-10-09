pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Обновление окружения из git-репозитория dots (Настройки → Updates).
// Репозиторий находится сам: ~/.config/quickshell — ссылка в <dots>/home/.config/quickshell.
// Обновление: git pull --ff-only → install.sh --link-only (новые ссылки и начальные файлы)
// → перезапуск шелла. Локальные изменения не трогаем: с ними обновление не запускается.
Singleton {
    id: root

    readonly property string defaultRepo: "https://github.com/Rexilone/my-dotfiles"
    readonly property string repoUrl: Settings.updateRepo || defaultRepo
    readonly property string branch: Settings.updateBranch || "main"

    property string dir: ""             // корень репозитория dots
    property bool isRepo: false
    property string version: "1.0.0"    // из файла VERSION
    property string commit: ""          // текущий коммит (короткий)
    property string commitDate: ""
    property string commitSubject: ""
    property int behind: 0              // сколько новых коммитов в репозитории
    property var incoming: []           // [{ hash, author, when, subject }]
    property var changedPackages: []    // списки пакетов, изменённые в новых коммитах
    property int dirty: 0               // незакоммиченных файлов
    property bool checking: false
    property bool updating: false
    property string error: ""
    property real lastCheck: 0
    property string log: ""             // вывод последнего обновления

    readonly property bool available: behind > 0

    function check() {
        if (checking || updating) return;
        checking = true;
        error = "";
        checkProc.running = true;
    }

    function update() {
        if (updating || !isRepo || dirty > 0) return;
        updating = true;
        error = "";
        log = "";
        updateProc.running = true;
    }

    // поставить пакеты из обновлённых списков — в терминале (спросит пароль)
    function installPackages() {
        Quickshell.execDetached(["foot", "-T", "Rexilone update", "sh", "-c", `"${dir}/install.sh"; echo; read -p '${I18n.ru ? "Готово. Enter — закрыть" : "Done. Press Enter to close"}' _`]);
    }

    function restartShell() {
        Quickshell.execDetached(["sh", "-c", "sleep 0.3; pkill -x qs; sleep 0.3; setsid -f qs"]);
    }

    // ── проверка: найти репозиторий, origin, fetch, что нового
    Process {
        id: checkProc
        environment: ({ GIT_TERMINAL_PROMPT: "0", LC_ALL: "C" })
        command: ["sh", "-c", `
            cfg=$(readlink -f "$HOME/.config/quickshell")
            dir=$(git -C "$cfg" rev-parse --show-toplevel 2>/dev/null) || { echo "@norepo"; exit 0; }
            echo "@dir $dir"
            cd "$dir"
            [ -f VERSION ] && echo "@version $(head -1 VERSION)"
            # origin — репозиторий из настроек (если не задан)
            git remote get-url origin >/dev/null 2>&1 || git remote add origin "$1"
            echo "@dirty $(git status --porcelain | wc -l)"
            if git rev-parse -q --verify HEAD >/dev/null; then
                git log -1 --format='@commit %h%x09%cr%x09%s'
            fi
            if ! git fetch --quiet origin "$2" 2>/tmp/qs-dots-fetch.$$; then
                echo "@error $(tail -1 /tmp/qs-dots-fetch.$$)"; rm -f /tmp/qs-dots-fetch.$$; exit 0
            fi
            rm -f /tmp/qs-dots-fetch.$$
            if git rev-parse -q --verify HEAD >/dev/null; then
                echo "@behind $(git rev-list --count HEAD..FETCH_HEAD)"
                git log --format='@in %h%x09%an%x09%cr%x09%s' HEAD..FETCH_HEAD | head -50
                git diff --name-only HEAD FETCH_HEAD -- packages/ | sed 's/^/@pkg /'
            else
                echo "@behind $(git rev-list --count FETCH_HEAD)"
                git log --format='@in %h%x09%an%x09%cr%x09%s' FETCH_HEAD | head -50
            fi
        `, "sh", root.repoUrl, root.branch]
        stdout: StdioCollector {
            onStreamFinished: {
                const inc = [], pkgs = [];
                let behind = 0, isRepo = true;
                for (const l of text.split("\n")) {
                    const sp = l.indexOf(" ");
                    const tag = sp > 0 ? l.slice(0, sp) : l, v = sp > 0 ? l.slice(sp + 1) : "";
                    if (tag === "@norepo") isRepo = false;
                    else if (tag === "@dir") root.dir = v;
                    else if (tag === "@version") root.version = v.trim() || root.version;
                    else if (tag === "@dirty") root.dirty = parseInt(v) || 0;
                    else if (tag === "@commit") {
                        const [h, when, ...s] = v.split("\t");
                        root.commit = h; root.commitDate = when; root.commitSubject = s.join("\t");
                    } else if (tag === "@error") root.error = v;
                    else if (tag === "@behind") behind = parseInt(v) || 0;
                    else if (tag === "@in") {
                        const [hash, author, when, ...s] = v.split("\t");
                        inc.push({ hash, author, when, subject: s.join("\t") });
                    } else if (tag === "@pkg") pkgs.push(v);
                }
                root.isRepo = isRepo;
                root.behind = behind;
                root.incoming = inc;
                root.changedPackages = pkgs;
                root.lastCheck = Date.now();
                root.checking = false;
                root.notifyIfNew();
            }
        }
        onExited: (code) => { if (root.checking) root.checking = false; }
    }

    // ── обновление
    Process {
        id: updateProc
        environment: ({ GIT_TERMINAL_PROMPT: "0", LC_ALL: "C" })
        command: ["sh", "-c", `
            cd "$1" || exit 1
            git pull --ff-only origin "$2" 2>&1 || exit 2
            ./install.sh --link-only 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g' | tail -20
        `, "sh", root.dir, root.branch]
        stdout: StdioCollector {
            onStreamFinished: root.log = text
        }
        onExited: (code) => {
            root.updating = false;
            if (code !== 0) {
                root.error = I18n.ru ? "Не удалось обновить — подробности ниже" : "Update failed — see the log below";
                return;
            }
            const pkgs = root.changedPackages.length > 0;
            Quickshell.execDetached(["notify-send", "-a", "Rexilone", "-i", "system-software-update",
                I18n.ru ? "Обновлено" : "Updated",
                pkgs ? (I18n.ru ? "Изменились списки пакетов — установите их в Настройки → Обновления" : "Package lists changed — install them in Settings → Updates")
                     : (I18n.ru ? "Перезапускаю оболочку…" : "Restarting the shell…")]);
            if (!pkgs) root.restartShell();
            else root.check();
        }
    }

    // ── уведомление о новых коммитах (одно на каждую новую версию)
    property string notifiedHead: ""
    function notifyIfNew() {
        if (behind <= 0 || !incoming.length) return;
        const head = incoming[0].hash;
        if (head === notifiedHead || head === Settings.updateNotified) return;
        notifiedHead = head;
        Settings.updateNotified = head;
        Quickshell.execDetached(["notify-send", "-a", "Rexilone", "-i", "system-software-update",
            I18n.ru ? "Доступно обновление" : "Update available",
            `${incoming[0].subject}${behind > 1 ? (I18n.ru ? ` и ещё ${behind - 1}` : ` and ${behind - 1} more`) : ""} — ${I18n.ru ? "Настройки → Обновления" : "Settings → Updates"}`]);
    }

    // автопроверка: через минуту после запуска и потом раз в 6 часов
    Timer {
        interval: 60 * 1000
        running: Settings.updateAuto ?? true
        onTriggered: root.check()
    }
    Timer {
        interval: 6 * 3600 * 1000
        repeat: true
        running: Settings.updateAuto ?? true
        onTriggered: root.check()
    }

    // qs ipc call updates check | update
    IpcHandler {
        target: "updates"
        function check(): void { root.check(); }
        function update(): void { root.update(); }
    }
}
