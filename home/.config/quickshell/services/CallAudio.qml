pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// разговор по телефону через компьютер: ПК — Bluetooth-гарнитура телефона (HFP).
// Включение — роль hfp_hf в WirePlumber (~/.config/wireplumber/wireplumber.conf.d/51-rexilone-calls.conf).
// Телефон сопрягается с ПК по Bluetooth один раз; дальше звук звонка, принятого с ПК (Rexlink), идёт
// в динамики и микрофон компьютера. Без Bluetooth-адаптера — недоступно.
Singleton {
    id: root

    property bool adapter: false
    property bool enabled: false
    readonly property string conf: `${Quickshell.env("HOME")}/.config/wireplumber/wireplumber.conf.d/51-rexilone-calls.conf`
    readonly property string confText: [
        "# RexOS: ПК — гарнитура телефона (звонки через компьютер). Настройки → Телефон",
        "monitor.bluez.properties = {",
        "  bluez5.roles = [ a2dp_sink a2dp_source bap_sink bap_source hsp_hs hsp_ag hfp_hf hfp_ag ]",
        "  bluez5.hfphsp-backend = \"native\"",
        "}",
    ].join("\n") + "\n"

    // во время звонка: узлы гарнитуры от телефона
    readonly property var callNodes: Pipewire.nodes.values.filter(n => /^bluez_(input|output|source|sink)\./.test(n.name ?? "")
        && /head-unit|hfp|hsp/i.test(n.properties?.["api.bluez5.profile"] ?? n.name))
    readonly property bool inCall: callNodes.length > 0
    PwObjectTracker { objects: root.callNodes }

    function refresh() {
        probe.running = true;
    }

    function setEnabled(on) {
        apply.command = ["sh", "-c", on
            ? 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1" && systemctl --user restart wireplumber'
            : 'rm -f "$1"; systemctl --user restart wireplumber', "sh", conf, confText];
        apply.running = true;
    }

    Process {
        id: apply
        onExited: root.refresh()
    }

    Process {
        id: probe
        running: true
        command: ["sh", "-c", 'ls /sys/class/bluetooth 2>/dev/null | grep -q . && echo adapter; [ -e "$1" ] && echo on', "sh", root.conf]
        stdout: StdioCollector {
            onStreamFinished: {
                root.adapter = text.includes("adapter");
                root.enabled = text.includes("on");
            }
        }
    }
}
