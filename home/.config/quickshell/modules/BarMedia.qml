import QtQuick
import Quickshell.Services.Mpris
import qs.services

// сейчас играет: иконка-кнопка и «исполнитель — трек»; клик по тексту — вкладка плеера
Row {
    id: root

    signal openPlayer

    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) ?? ps[0] ?? null;
    }

    visible: !!player && !!player.trackTitle
    spacing: 8

    BarText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.player?.isPlaying ? Icons.pause : Icons.play
        font.pixelSize: Theme.iconSize - 2
        onClicked: root.player.togglePlaying()
    }

    BarText {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, 280)
        elide: Text.ElideRight
        active: root.player?.isPlaying ?? false
        text: [root.player?.trackArtist, root.player?.trackTitle].filter(s => s).join(" — ")
        font.pixelSize: Theme.fontSize - 1
        onClicked: root.openPlayer()
        onWheel: w => w.angleDelta.y > 0 ? root.player.previous() : root.player.next()
    }
}
