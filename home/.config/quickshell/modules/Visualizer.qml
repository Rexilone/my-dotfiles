import QtQuick
import qs.services

// столбики спектра (cava); по центру — симметрично от середины, иначе — снизу вверх
Row {
    id: root

    property int count: 16
    property real barWidth: 3
    property real maxHeight: 16
    property bool centered: true
    property color color: Theme.accent
    readonly property var vals: Cava.take(count)

    height: maxHeight
    spacing: Math.max(1, Math.round(barWidth / 2))

    readonly property string uid: `viz-${Math.random()}`
    Component.onCompleted: Cava.need(uid, visible)
    onVisibleChanged: Cava.need(uid, visible)
    Component.onDestruction: Cava.need(uid, false)

    Repeater {
        model: root.count

        Rectangle {
            required property int index
            readonly property real v: root.vals[index] ?? 0
            width: root.barWidth
            height: Math.max(root.barWidth, v * root.maxHeight)
            y: root.centered ? (root.maxHeight - height) / 2 : root.maxHeight - height
            radius: root.barWidth / 2
            color: root.color
            opacity: 0.55 + 0.45 * v
            // без Behavior: cava сама сглаживает и шлёт 60 кадров в секунду, а постоянно идущая анимация
            // заставляла перерисовываться все окна шелла с частотой экрана
        }
    }
}
