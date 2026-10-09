pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// запись экрана через gpu-screen-recorder
Singleton {
    id: root

    // настройки (сохраняются между запусками)
    property alias target: cfg.target            // имя монитора | "region" | "window"
    property alias audio: cfg.audio              // none | system | mic | both
    property alias fps: cfg.fps
    property alias quality: cfg.quality          // high | very_high | ultra
    property alias cursor: cfg.cursor
    property alias countdownEnabled: cfg.countdown
    property alias replaySeconds: cfg.replaySeconds
    // gpu — аппаратный кодер видеокарты. На RX 580 (VCE) он вешает всю видеокарту,
    // поэтому по умолчанию кодируем на процессоре (H.264, x264)
    property alias encoder: cfg.encoder

    // состояние
    readonly property bool recording: rec.running
    readonly property bool replayActive: replay.running
    property bool paused: false
    property int elapsed: 0
    property int countdown: 0
    property string region: ""
    property bool busy: countdown > 0 || slurp.running

    readonly property string videosDir: `${Quickshell.env("HOME")}/Видео`
    readonly property string recordDir: `${videosDir}/Recordings`
    readonly property string replayDir: `${videosDir}/Replays`

    readonly property string elapsedText: {
        const m = Math.floor(elapsed / 60), s = elapsed % 60;
        return `${m}:${s < 10 ? "0" : ""}${s}`;
    }

    function args(isReplay) {
        const w = target === "region" ? "region" : target === "window" ? "portal" : (target || Settings.primary);
        const a = ["gpu-screen-recorder", "-w", w];
        if (w === "region") a.push("-region", region);
        if (w === "portal") a.push("-restore-portal-session", "yes");
        a.push("-f", String(fps), "-q", quality, "-cursor", cursor ? "yes" : "no", "-c", "mp4", "-ac", "aac");
        a.push("-encoder", encoder === "gpu" ? "gpu" : "cpu", "-k", "h264");
        const dev = { system: "default_output", mic: "default_input", both: "default_output|default_input" }[audio];
        if (dev) a.push("-a", dev);
        a.push("-sc", Quickshell.shellPath("scripts/gsr-saved.sh"));
        if (isReplay) {
            a.push("-r", String(replaySeconds), "-replay-storage", "ram", "-o", replayDir);
        } else {
            const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
            a.push("-o", `${recordDir}/Recording_${stamp}.mp4`);
        }
        // создаём папку и заменяем shell на gpu-screen-recorder (сигналы идут прямо ему)
        return ["sh", "-c", 'mkdir -p "$1" && shift && exec "$@"', "sh", isReplay ? replayDir : recordDir].concat(a);
    }

    function start() {
        if (recording || busy) return;
        if (target === "region") slurp.running = true;
        else begin();
    }

    function begin() {
        if (countdownEnabled) {
            countdown = 3;
            countdownTimer.start();
        } else {
            launch();
        }
    }

    function launch() {
        countdown = 0;
        elapsed = 0;
        paused = false;
        rec.command = args(false);
        rec.running = true;
    }

    function stop() {
        if (countdown > 0) {
            countdownTimer.stop();
            countdown = 0;
        } else if (recording) {
            rec.signal(2);  // SIGINT: остановить и сохранить
        }
    }

    function toggle() {
        if (recording || countdown > 0) stop();
        else start();
    }

    function togglePause() {
        if (!recording) return;
        rec.signal(12);  // SIGUSR2
        paused = !paused;
    }

    function toggleReplay() {
        if (replay.running) {
            replay.signal(2);
        } else {
            replay.command = args(true);
            replay.running = true;
        }
    }

    function saveReplay() {
        if (replay.running) replay.signal(10);  // SIGUSR1
    }

    function openFolder() {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", recordDir]);
    }

    function fail(what, err) {
        const msg = err.trim().split("\n").slice(-3).join("\n") || "unknown error";
        Quickshell.execDetached(["notify-send", "-a", "Recorder", "-u", "critical", what, msg]);
    }

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: cfgFile.writeAdapter()
    }

    FileView {
        id: cfgFile
        path: Quickshell.statePath("recorder.json")
        blockLoading: true
        printErrors: false
        // запись с задержкой одним вызовом: запись на каждое поле теряет значения
        onAdapterUpdated: saveTimer.restart()

        JsonAdapter {
            id: cfg
            property string target: ""   // пусто — основной монитор
            property string audio: "both"
            property int fps: 60
            property string quality: "very_high"
            property bool cursor: true
            property bool countdown: false
            property int replaySeconds: 30
            property string encoder: "cpu"
        }
    }

    Process {
        id: slurp
        command: ["slurp", "-f", "%wx%h+%x+%y", "-b", "#00000066", "-c", "#d4d4d4", "-w", "1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const g = text.trim();
                if (g) {
                    root.region = g;
                    root.begin();
                }
            }
        }
    }

    Process {
        id: rec
        property bool failed: false
        stderr: StdioCollector {
            id: recErr
        }
        onExited: code => {
            root.paused = false;
            if (code !== 0 && code !== 130 && code !== 2) Qt.callLater(() => root.fail("Recording failed", recErr.text));
        }
    }

    Process {
        id: replay
        stderr: StdioCollector {
            id: replayErr
        }
        onExited: code => {
            if (code !== 0 && code !== 130 && code !== 2) Qt.callLater(() => root.fail("Replay failed", replayErr.text));
        }
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0) {
                stop();
                root.launch();
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording && !root.paused
        onTriggered: root.elapsed++
    }
}
