import QtQuick
import qs.services

// производительность: CPU, GPU, RAM
Item {
    id: root

    property bool active: false

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    readonly property string uid: `perf-${Math.random()}`
    onActiveChanged: SysStats.need(uid, active)
    Component.onCompleted: SysStats.need(uid, active)
    Component.onDestruction: SysStats.need(uid, false)

    Row {
        id: row
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 56

        StatRing {
            value: SysStats.cpu
            label: "CPU"
            sub: `${Math.round(SysStats.cpuTemp)}°C`
        }

        StatRing {
            value: SysStats.gpu
            label: "GPU"
            sub: `${Math.round(SysStats.gpuTemp)}°C · ${(SysStats.vramUsed / 1073741824).toFixed(1)}/${Math.round(SysStats.vramTotal / 1073741824)} GB`
        }

        StatRing {
            value: SysStats.ramTotal ? SysStats.ramUsed / SysStats.ramTotal : 0
            label: "RAM"
            sub: `${SysStats.gb(SysStats.ramUsed)} / ${SysStats.gb(SysStats.ramTotal)} GB`
        }
    }
}
