import QtQuick
import qs.services

// текст песни на рабочем столе: текущая строка крупно, следующая — бледнее
Column {
    id: root

    readonly property string uid: `desk-lyrics-${Math.random()}`
    Component.onCompleted: Lyrics.need(uid, true)
    Component.onDestruction: Lyrics.need(uid, false)

    width: 520
    spacing: 6

    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: Lyrics.line || (Lyrics.loading ? "…" : Lyrics.player?.trackTitle ? "♪" : I18n.tr("Nothing playing"))
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: 26
        font.bold: true
    }
    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: Lyrics.next
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 17
    }
}
