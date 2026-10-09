import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.services

// звук (input: false) или микрофон (input: true)
// ЛКМ — mute, колесо — громкость, ПКМ — микшер, СКМ — pavucontrol
BarText {
    id: root

    property bool input: false
    signal openMixer

    readonly property PwNode node: input ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
    readonly property bool muted: node?.audio?.muted ?? true
    readonly property real volume: node?.audio?.volume ?? 0

    PwObjectTracker { objects: [root.node] }

    active: !muted
    text: {
        const icon = Icons.volumeIcon(input, muted, volume);
        return muted ? icon : `${icon} ${Math.round(volume * 100)}%`;
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            openMixer();
        else if (mouse.button === Qt.MiddleButton)
            Quickshell.execDetached(["pavucontrol", "--tab", input ? "4" : "3"]);
        else if (node?.audio)
            node.audio.muted = !node.audio.muted;
    }
    onWheel: w => {
        if (!node?.audio) return;
        const step = w.angleDelta.y > 0 ? 0.05 : -0.05;
        node.audio.volume = Math.max(0, Math.min(1.5, node.audio.volume + step));
    }
}
