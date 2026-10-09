import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// уровень звука узла (устройство или приложение); работает только пока active
Item {
    id: root

    property PwNode node: null
    property bool active: false
    property real level: 0

    readonly property bool isSink: node?.type === PwNodeType.AudioSink
    // приложения — по object.serial, устройства — по имени
    readonly property string target: node ? (node.isStream ? String(node.properties?.["object.serial"] ?? "") : node.name) : ""

    visible: false

    Process {
        running: root.active && root.target !== ""
        command: ["python3", "-u", Quickshell.shellPath("scripts/level-meter.py"), root.target, root.isSink ? "1" : "0"]
        stdout: SplitParser {
            onRead: line => {
                // в децибелах: −60 дБ … 0 дБ -> 0 … 1, иначе тихий звук почти не виден
                const peak = Number(line) || 0;
                const v = peak > 0.001 ? Math.max(0, 1 + 20 * Math.log10(peak) / 60) : 0;
                // мгновенная атака, плавный спад
                root.level = v > root.level ? v : root.level * 0.75 + v * 0.25;
            }
        }
        onRunningChanged: if (!running) root.level = 0
    }
}
