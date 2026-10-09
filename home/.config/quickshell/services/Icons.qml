pragma Singleton
import QtQuick
import Quickshell

// глифы Nerd Font (Material Design)
Singleton {
    readonly property string volHigh: String.fromCodePoint(0xF057E)
    readonly property string volMid: String.fromCodePoint(0xF0580)
    readonly property string volLow: String.fromCodePoint(0xF057F)
    readonly property string volMute: String.fromCodePoint(0xF075F)

    readonly property string mic: String.fromCodePoint(0xF036C)
    readonly property string micOff: String.fromCodePoint(0xF036D)

    readonly property string ethernet: String.fromCodePoint(0xF0200)
    readonly property string wifi: String.fromCodePoint(0xF05A9)
    readonly property string offline: String.fromCodePoint(0xF0318)

    readonly property string bell: String.fromCodePoint(0xF009A)
    readonly property string bellOff: String.fromCodePoint(0xF009B)

    readonly property string checkOn: String.fromCodePoint(0xF0132)
    readonly property string checkOff: String.fromCodePoint(0xF0131)
    readonly property string radioOn: String.fromCodePoint(0xF043E)
    readonly property string radioOff: String.fromCodePoint(0xF043D)

    readonly property string close: String.fromCodePoint(0xF0156)
    readonly property string down: String.fromCodePoint(0xF0045)
    readonly property string up: String.fromCodePoint(0xF005D)

    readonly property string search: String.fromCodePoint(0xF0349)

    readonly property string clock: String.fromCodePoint(0xF0954)

    readonly property string lock: String.fromCodePoint(0xF033E)

    readonly property string clipboard: String.fromCodePoint(0xF014D)
    readonly property string trash: String.fromCodePoint(0xF0A7A)

    readonly property string record: String.fromCodePoint(0xF044A)
    readonly property string stop: String.fromCodePoint(0xF04DB)
    readonly property string pause: String.fromCodePoint(0xF03E4)
    readonly property string play: String.fromCodePoint(0xF040A)
    readonly property string monitor: String.fromCodePoint(0xF0379)
    readonly property string region: String.fromCodePoint(0xF0A6C)
    readonly property string window: String.fromCodePoint(0xF05AF)
    readonly property string replay: String.fromCodePoint(0xF02DA)
    readonly property string folder: String.fromCodePoint(0xF024B)
    readonly property string pointer: String.fromCodePoint(0xF01BF)
    readonly property string timer: String.fromCodePoint(0xF051B)

    function volumeIcon(input, muted, volume) {
        if (input) return muted ? micOff : mic;
        if (muted || volume <= 0) return volMute;
        return volume < 0.34 ? volLow : volume < 0.67 ? volMid : volHigh;
    }
}
