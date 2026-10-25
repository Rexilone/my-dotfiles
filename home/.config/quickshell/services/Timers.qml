pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// таймер «острова» в баре: обратный отсчёт, пауза, «+1 мин»; в конце — звук и уведомление.
// qs ipc call timer start 5   ·   qs ipc call timer cancel
Singleton {
    id: root

    property real end: 0          // когда закончится (мс), пока идёт
    property real left: 0         // сколько осталось, пока на паузе
    property real total: 0        // на сколько ставили
    property bool paused: false
    property real now: Date.now()
    property bool justFinished: false   // «Время вышло» — несколько секунд после конца
    readonly property bool active: total > 0
    readonly property real remaining: !active ? 0 : paused ? left : Math.max(0, end - now)
    readonly property real progress: active ? 1 - remaining / total : 0
    signal finished

    function fmt(ms) {
        const t = Math.ceil(ms / 1000);
        const h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), s = t % 60;
        const p = n => String(n).padStart(2, "0");
        return h ? `${h}:${p(m)}:${p(s)}` : `${m}:${p(s)}`;
    }

    function start(minutes) {
        now = Date.now();
        total = minutes * 60000;
        end = now + total;
        paused = false;
        justFinished = false;
    }
    function add(minutes) {
        if (!active) { start(minutes); return; }
        total += minutes * 60000;
        if (paused) left += minutes * 60000;
        else end += minutes * 60000;
    }
    function pause() {
        if (!active || paused) return;
        left = Math.max(0, end - Date.now());
        paused = true;
    }
    function resume() {
        if (!active || !paused) return;
        now = Date.now();
        end = now + left;
        paused = false;
    }
    function cancel() {
        total = 0;
        paused = false;
    }

    Timer {
        running: root.active && !root.paused
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.now = Date.now();
            if (root.remaining <= 0) {
                root.total = 0;
                root.justFinished = true;
                doneTimer.restart();
                Sounds.play("timer");
                Quickshell.execDetached(["notify-send", "-a", I18n.tr("Timer"), "-i", "alarm-clock", I18n.tr("Time is up")]);
                root.finished();
            }
        }
    }
    Timer {
        id: doneTimer
        interval: 8000
        onTriggered: root.justFinished = false
    }

    IpcHandler {
        target: "timer"
        function start(minutes: int): void { root.start(minutes); }
        function cancel(): void { root.cancel(); }
    }
}
