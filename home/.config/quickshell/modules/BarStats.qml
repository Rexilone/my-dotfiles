import QtQuick
import qs.services

// нагрузка в баре: CPU и RAM; клик — вкладка системы
BarText {
    id: root

    signal openSystem

    readonly property string uid: "bar-stats"
    Component.onCompleted: SysStats.need(uid, visible)
    onVisibleChanged: SysStats.need(uid, visible)
    Component.onDestruction: SysStats.need(uid, false)

    readonly property int cpu: Math.round(SysStats.cpu * 100)
    readonly property int ram: SysStats.ramTotal ? Math.round(SysStats.ramUsed / SysStats.ramTotal * 100) : 0

    color: cpu > 90 ? Theme.urgent : cpu > 75 ? Theme.warn : Theme.fg
    text: `${String.fromCodePoint(0xF061A)} ${cpu}%  ${String.fromCodePoint(0xF035B)} ${ram}%`
    font.pixelSize: Theme.fontSize - 1
    onClicked: openSystem()
}
