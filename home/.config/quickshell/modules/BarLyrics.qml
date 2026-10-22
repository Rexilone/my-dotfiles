import QtQuick
import qs.services

// строка песни, которая звучит сейчас (Lyrics); нет синхронного текста — модуль скрыт
BarText {
    id: root

    property int maxWidth: 380
    // модуль включён: текст ищется, даже пока строка пустая и модуль скрыт
    property bool on: true

    readonly property string uid: `lyrics-${Math.random()}`
    Component.onCompleted: Lyrics.need(uid, on)
    onOnChanged: Lyrics.need(uid, on)
    Component.onDestruction: Lyrics.need(uid, false)

    width: Math.min(implicitWidth, maxWidth)
    elide: Text.ElideRight
    text: Lyrics.line || "♪"
    color: Lyrics.line ? Theme.fg : Theme.dim
    font.pixelSize: Theme.fontSize - 1
}
