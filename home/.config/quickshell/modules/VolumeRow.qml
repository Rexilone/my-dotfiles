import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.services

// строка громкости: [иконка-мьют] [слайдер 0–150%] [проценты]
RowLayout {
    id: root

    required property PwNode node
    property bool input: false
    property bool meter: false

    readonly property bool muted: node?.audio?.muted ?? true
    readonly property real volume: node?.audio?.volume ?? 0

    spacing: 10

    BarText {
        Layout.preferredWidth: 18
        text: Icons.volumeIcon(root.input, root.muted, root.volume)
        font.pixelSize: Theme.iconSize
        active: !root.muted
        onClicked: if (root.node?.audio) root.node.audio.muted = !root.muted
    }

    LevelMeter {
        id: lm
        node: root.node
        active: root.meter
    }

    Slider {
        level: root.meter ? lm.level : -1
        Layout.fillWidth: true
        value: root.volume
        muted: root.muted
        onMoved: v => {
            if (root.node?.audio) root.node.audio.volume = v;
        }
    }

    Text {
        Layout.preferredWidth: 38
        horizontalAlignment: Text.AlignRight
        text: `${Math.round(root.volume * 100)}%`
        color: root.muted ? Theme.dim : Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
    }
}
