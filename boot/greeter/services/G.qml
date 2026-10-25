pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// Экран входа RexOS: тема, пользователи, сеансы, раскладка, вход через greetd.
// Тему кладёт rexilone-boot (root) в /var/lib/rexilone/greeter/ — по теме шелла пользователя.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("REXILONE_GREETER_DIR") || "/var/lib/rexilone/greeter"
    readonly property string stateDir: Quickshell.env("REXILONE_GREETER_STATE") || "/var/lib/rexilone/greeter-state"
    // проверка без greetd: пароль «test» — «вход», остальное — «неверный пароль»
    readonly property bool test: Quickshell.env("REXILONE_GREETER_TEST") === "1"

    // ── тема
    property var t: ({})
    readonly property var c: t.colors ?? {}
    readonly property bool ru: (t.lang ?? "en") === "ru"
    function tr(en, rus) { return ru ? rus : en; }

    readonly property color bg: c.bg ?? "#151515"
    readonly property color surface: c.surface ?? "#1b1b1b"
    readonly property color surfaceHi: c.surfaceHi ?? "#222222"
    readonly property color surfaceHi2: c.surfaceHi2 ?? "#2a2a2a"
    readonly property color line: c.line ?? "#3a3a3a"
    readonly property color fg: c.fg ?? "#d4d4d4"
    readonly property color muted: c.muted ?? "#a0a0a0"
    readonly property color dim: c.dim ?? "#6b6b6b"
    readonly property color faint: c.faint ?? "#333333"
    readonly property color accent: c.accent ?? "#d4d4d4"
    readonly property color urgent: c.urgent ?? "#c96a6a"
    readonly property color warn: c.warn ?? "#d7a65f"
    readonly property real panelAlpha: t.transparency ? Math.max(0.5, t.opacity ?? 0.85) : 1
    readonly property color panel: Qt.rgba(bg.r, bg.g, bg.b, panelAlpha)

    readonly property string font: t.font || "JetBrainsMono Nerd Font"
    readonly property real scale: Math.max(0.8, Math.min(1.6, t.uiScale ?? 1))
    readonly property int fontSize: Math.round(13 * scale)
    readonly property int iconSize: Math.round(15 * scale)
    readonly property int barHeight: Math.max(24, Math.min(56, t.barHeight ?? 32))
    // «остров» (динамический остров шелла) на экране входа — как «пилюли»
    readonly property string barStyle: t.barStyle === "island" ? "pills" : (t.barStyle ?? "flat")
    readonly property bool clock: t.greeterClock ?? true
    readonly property int radius: 10
    readonly property int animFast: 120
    readonly property int animSlow: 220

    readonly property string background: t.background ? `file://${dir}/${t.background}` : ""
    readonly property string avatar: t.avatar ? `file://${dir}/${t.avatar}` : ""

    FileView {
        path: `${root.dir}/theme.json`
        printErrors: false
        blockLoading: true
        onLoaded: {
            try { root.t = JSON.parse(text()); } catch (e) {}
        }
    }

    // ── что выбрали в прошлый раз (пользователь, сеанс) — в папке, куда greeter может писать
    property string lastUser: ""
    property string lastSession: ""
    FileView {
        id: stateFile
        path: `${root.stateDir}/last.json`
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.lastUser = s.user ?? "";
                root.lastSession = s.session ?? "";
            } catch (e) {}
        }
    }
    function remember() {
        stateFile.setText(JSON.stringify({ user: user?.name ?? "", session: session?.name ?? "" }));
    }

    // экран входа поднялся — счётчик неудачных запусков (rexilone-greeter) сбросить
    Component.onCompleted: Quickshell.execDetached(["rm", "-f", `${stateDir}/fails`])

    // ── пользователи (обычные: uid 1000…59999 с настоящей оболочкой)
    property var users: []
    property int userIndex: 0
    readonly property var user: users[userIndex] ?? null
    FileView {
        path: "/etc/passwd"
        printErrors: false
        blockLoading: true
        onLoaded: {
            const list = [];
            for (const l of text().split("\n")) {
                const f = l.split(":");
                const uid = parseInt(f[2]);
                if (f.length < 7 || uid < 1000 || uid >= 60000 || /(nologin|false)$/.test(f[6])) continue;
                list.push({ name: f[0], display: (f[4] ?? "").split(",")[0] || f[0] });
            }
            root.users = list;
            root.pickUser();
        }
    }
    function pickUser() {
        const want = lastUser || t.user || "";
        const i = users.findIndex(u => u.name === want);
        userIndex = Math.max(0, i);
    }
    onTChanged: pickUser()
    onLastUserChanged: pickUser()
    function nextUser(d) {
        if (users.length < 2 || busy) return;
        if (asking) Greetd.cancelSession();
        asking = false;
        userIndex = (userIndex + d + users.length) % users.length;
        error = "";
    }

    // ── сеансы (/usr/share/wayland-sessions)
    property var sessions: []
    property int sessionIndex: 0
    readonly property var session: sessions[sessionIndex] ?? { name: "niri", exec: ["niri-session"] }
    Process {
        running: true
        command: ["sh", "-c", `for f in /usr/share/wayland-sessions/*.desktop; do
            [ -f "$f" ] || continue
            n=$(grep -m1 '^Name=' "$f" | cut -d= -f2-); e=$(grep -m1 '^Exec=' "$f" | cut -d= -f2-)
            [ -n "$e" ] && printf '%s\\t%s\\n' "\${n:-$(basename "$f" .desktop)}" "$e"
        done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(l => l.includes("\t")).map(l => {
                    const [name, exec] = l.split("\t");
                    return { name, exec: exec.replace(/%\w/g, "").trim().split(/\s+/) };
                });
                // niri — первым
                list.sort((a, b) => (b.name.toLowerCase() === "niri") - (a.name.toLowerCase() === "niri"));
                if (list.length) root.sessions = list;
                root.sessionIndex = Math.max(0, root.sessions.findIndex(s => s.name === root.lastSession));
            }
        }
    }
    function nextSession() {
        if (sessions.length > 1) sessionIndex = (sessionIndex + 1) % sessions.length;
    }

    // ── раскладка клавиатуры (niri)
    property var layouts: []
    property int layoutIndex: 0
    function layoutShort(n) {
        n = n ?? "";
        const known = { English: "EN", Russian: "RU", Ukrainian: "UA", German: "DE", French: "FR", Belarusian: "BY", Kazakh: "KZ" };
        const k = Object.keys(known).find(x => n.startsWith(x));
        return k ? known[k] : n.slice(0, 2).toUpperCase();
    }
    readonly property string layout: layoutShort(layouts[layoutIndex])
    function nextLayout() { Quickshell.execDetached(["niri", "msg", "action", "switch-layout", "next"]); }
    Process {
        running: !root.test
        command: ["niri", "msg", "-j", "event-stream"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const e = JSON.parse(line);
                    if (e.KeyboardLayoutsChanged) {
                        root.layouts = e.KeyboardLayoutsChanged.keyboard_layouts.names;
                        root.layoutIndex = e.KeyboardLayoutsChanged.keyboard_layouts.current_idx;
                    } else if (e.KeyboardLayoutSwitched) {
                        root.layoutIndex = e.KeyboardLayoutSwitched.idx;
                    }
                } catch (err) {}
            }
        }
    }

    // ── питание
    function power(action) { Quickshell.execDetached(["systemctl", action]); }

    // ── вход
    property bool busy: false
    property string error: ""
    property int shakes: 0
    property bool leaving: false        // вход удался — экран гаснет, затем сеанс
    property string pending: ""

    property bool asking: false         // PAM спросил ещё что-то (код и т.п.) — ответ из того же поля

    function login(password) {
        if (busy || !user) return;
        error = "";
        busy = true;
        if (asking) {
            asking = false;
            Greetd.respond(password);
            return;
        }
        if (test) {
            pending = password;
            testTimer.restart();
            return;
        }
        if (!Greetd.available) {
            fail(tr("greetd isn't running — the login screen can't sign in", "greetd не запущен — войти отсюда нельзя"));
            return;
        }
        pending = password;
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        Greetd.createSession(user.name);
    }
    function fail(msg) {
        busy = false;
        asking = false;
        pending = "";
        error = msg;
        shakes++;
    }
    function launch() {
        remember();
        leaving = true;
        launchTimer.restart();
    }

    Timer {
        id: testTimer
        interval: 700
        onTriggered: root.pending === "test" ? root.launch() : root.fail(root.tr("Wrong password", "Неверный пароль"))
    }
    // дать экрану плавно погаснуть
    Timer {
        id: launchTimer
        interval: 450
        onTriggered: {
            if (root.test) {
                Qt.quit();
                return;
            }
            Greetd.launch(root.session.exec, ["XDG_SESSION_TYPE=wayland"], true);
        }
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                if (root.pending !== "") {
                    Greetd.respond(root.pending);
                    root.pending = "";
                } else {
                    // второй вопрос (например, код) — показать и ждать ответа в том же поле
                    root.busy = false;
                    root.asking = true;
                    root.error = message;
                }
            } else if (error) {
                root.error = message;
            }
        }
        function onAuthFailure(message) {
            root.fail(root.tr("Wrong password", "Неверный пароль"));
        }
        function onReadyToLaunch() { root.launch(); }
        function onError(error) {
            root.leaving = false;
            root.fail(error);
        }
    }

    // ── имя компьютера
    property string host: ""
    FileView {
        path: "/etc/hostname"
        printErrors: false
        blockLoading: true
        onLoaded: root.host = text().trim()
    }
}
