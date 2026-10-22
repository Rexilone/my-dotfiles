import QtQuick
import qs.services

// кот в баре: спит, пока процессор отдыхает, идёт под нагрузкой и бежит под сильной
// глифы шрифта assets/catwalk.otf (плагин cat для Noctalia, MIT): «a» — сон, «b»…«f» — шаги
Text {
    id: root

    property real cpu: SysStats.cpu * 100
    readonly property string pace: cpu < 15 ? "idle" : cpu < 60 ? "walk" : "run"
    property int frame: 0

    text: pace === "idle" ? "a" : "bcdef"[frame]
    color: Theme.accent
    font.family: catFont.name
    font.pixelSize: Math.round(Theme.iconSize * 1.6)

    signal clicked

    FontLoader {
        id: catFont
        source: Qt.resolvedUrl("../assets/catwalk.otf")
    }

    readonly property string uid: `cat-${Math.random()}`
    Component.onCompleted: SysStats.need(uid, visible)
    onVisibleChanged: SysStats.need(uid, visible)
    Component.onDestruction: SysStats.need(uid, false)

    Timer {
        running: root.visible && root.pace !== "idle"
        repeat: true
        // шаг: 380→180 мс при ходьбе, 160→55 мс при беге
        interval: root.pace === "walk"
            ? 380 - (root.cpu - 15) / 45 * 200
            : 160 - Math.min(1, (root.cpu - 60) / 40) * 105
        onTriggered: root.frame = (root.frame + 1) % 5
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
