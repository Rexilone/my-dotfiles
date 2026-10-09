import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.services

// значок приложения из трея в стиле бара: известные приложения — глиф Nerd Font,
// остальные — родная иконка, обесцвеченная
Item {
    id: root

    required property SystemTrayItem item
    property bool hovered: false
    property int size: Theme.iconSize

    implicitWidth: size
    implicitHeight: size

    // id/название приложения -> глиф Nerd Font
    readonly property var glyphs: [
        [/steam/, 0xF04D3],
        [/discord|vesktop|webcord|legcord|equibop/, 0xF066F],
        [/telegram|ayugram|64gram|kotatogram/, 0xF2C6],
        [/throne|nekoray|nekobox|v2ray|hiddify|clash|amnezia|vpn/, 0xF0565],
        [/obs/, 0xF044A],
        [/spotify/, 0xF04C7],
        [/blueman|bluetooth/, 0xF00AF],
        [/udiskie/, 0xF0553],
        [/keepass/, 0xF0306],
        [/firefox|zen|chrom|brave/, 0xF059F],
    ]
    readonly property string glyph: {
        const key = `${item?.id ?? ""} ${item?.title ?? ""}`.toLowerCase();
        const hit = glyphs.find(g => g[0].test(key));
        return hit ? String.fromCodePoint(hit[1]) : "";
    }

    Text {
        anchors.centerIn: parent
        visible: root.glyph !== ""
        text: root.glyph
        color: root.hovered ? Theme.fgHover : Theme.fg
        font.family: Theme.font
        font.pixelSize: root.size + 1

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    IconImage {
        id: image
        anchors.fill: parent
        source: root.item?.icon ?? ""
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.glyph === ""
        source: image
        saturation: -1.0
        brightness: root.hovered ? 0.25 : 0.1
        opacity: root.hovered ? 1 : 0.85

        Behavior on brightness { NumberAnimation { duration: Theme.animFast } }
    }
}
