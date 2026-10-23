pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// звук по приложениям: Discord — в наушники, музыка — в колонки.
// Правила в Settings.audioRoutes: { out: { приложение: node.name устройства }, in: { … } };
// каждому новому потоку приложения выставляется цель (метаданные PipeWire target.object).
Singleton {
    id: root

    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio
        && (n.type === PwNodeType.AudioOutStream || n.type === PwNodeType.AudioInStream)
        && !String(n.name).startsWith("qs-meter") && n.properties?.["application.name"] !== "qs-meter")

    PwObjectTracker { objects: root.streams }

    property var applied: ({})   // id потока → куда направлен

    function isInput(n) {
        return n.type === PwNodeType.AudioInStream;
    }
    // ключ приложения: имя программы, иначе название потока
    function appKey(n) {
        const p = n.properties ?? {};
        return p["application.process.binary"] || p["application.name"] || n.name || "";
    }
    function ruleFor(n) {
        return ((Settings.audioRoutes ?? {})[isInput(n) ? "in" : "out"] ?? {})[appKey(n)] ?? "";
    }
    function deviceExists(name, input) {
        return Pipewire.nodes.values.some(d => d.audio && d.name === name
            && d.type === (input ? PwNodeType.AudioSource : PwNodeType.AudioSink));
    }

    // выбрать устройство для приложения (пусто — как в системе) и запомнить
    function route(n, device) {
        Settings.setAudioRoute(isInput(n), appKey(n), device);
        send(n, device);
    }

    function send(n, device) {
        const a = Object.assign({}, applied);
        a[n.id] = device;
        applied = a;
        Quickshell.execDetached(device
            ? ["pw-metadata", String(n.id), "target.object", device]
            : ["pw-metadata", "-d", String(n.id), "target.object"]);
    }

    function apply() {
        for (const n of streams) {
            const r = ruleFor(n);
            if (!r || applied[n.id] === r || !deviceExists(r, isInput(n))) continue;
            send(n, r);
        }
    }

    onStreamsChanged: applyLater.restart()
    Connections {
        target: Settings
        function onAudioRoutesChanged() { applyLater.restart(); }
    }
    // свойства потока приходят чуть позже самого потока
    Timer {
        id: applyLater
        interval: 400
        onTriggered: root.apply()
    }
}
