import QtQuick
import qs.services

// телефон в баре (Rexlink): заряд, уведомления, звонок
// ЛКМ — меню телефона, ПКМ — найти телефон, СКМ — окно Rexlink
BarText {
    id: root

    signal openMenu

    readonly property int level: Rexlink.status.battery ?? Rexlink.dev?.battery ?? -1
    readonly property bool charging: Rexlink.status.charging ?? false
    readonly property bool showPct: Settings.moduleOn("phonePercent", true)

    visible: Rexlink.connected && (Rexlink.online || Settings.moduleOn("phoneOffline", false))
    active: Rexlink.online
    color: Rexlink.ringing ? Theme.warn
        : level >= 0 && level <= 15 && !charging ? Theme.urgent
        : Rexlink.online ? Theme.fg : Theme.dim
    text: !Rexlink.online ? `${Rexlink.kindIcon(Rexlink.dev?.kind)} —`
        : Rexlink.ringing ? `${String.fromCodePoint(0xF03F2)} ${Rexlink.call.name || Rexlink.call.number || "Call"}`
        : `${Rexlink.kindIcon(Rexlink.dev?.kind)} ${Rexlink.batteryIcon(level, charging)}${showPct && level >= 0 ? " " + level + "%" : ""}`
          + (Rexlink.notifs.length ? `  ${String.fromCodePoint(0xF009A)} ${Rexlink.notifs.length}` : "")

    // мигание при входящем звонке
    SequentialAnimation on opacity {
        running: Rexlink.ringing
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.opacity = 1
        NumberAnimation { to: 0.35; duration: 450 }
        NumberAnimation { to: 1; duration: 450 }
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) Rexlink.ring();
        else if (mouse.button === Qt.MiddleButton) Rexlink.show("overview");
        else openMenu();
    }
}
