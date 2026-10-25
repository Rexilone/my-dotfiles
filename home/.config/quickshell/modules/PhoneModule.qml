import QtQuick
import qs.services

// телефон в баре (Rexlink): заряд, уведомления, звонок
// ЛКМ — меню телефона, ПКМ — найти телефон, СКМ — окно Rexlink; файлы, брошенные на значок, уходят на телефон
BarText {
    id: root

    signal openMenu

    readonly property int level: Rexlink.status.battery ?? Rexlink.dev?.battery ?? -1
    readonly property bool charging: Rexlink.status.charging ?? false
    readonly property bool showPct: Settings.moduleOn("phonePercent", true)
    // бросить файлы на значок — отправить (Настройки → Бар → «Файлы на значок телефона»)
    readonly property bool dropOn: Settings.moduleOn("phoneDrop", true) && Rexlink.online
    readonly property bool dropping: drop.containsDrag

    visible: Rexlink.connected && (Rexlink.online || Settings.moduleOn("phoneOffline", false))
    active: Rexlink.online
    color: dropping ? Theme.accent
        : Rexlink.ringing ? Theme.warn
        : level >= 0 && level <= 15 && !charging ? Theme.urgent
        : Rexlink.online ? Theme.fg : Theme.dim
    text: dropping ? `${Rexlink.kindIcon(Rexlink.dev?.kind)} ${String.fromCodePoint(0xF0552)} ${I18n.tr("Send to phone")}`
        : !Rexlink.online ? `${Rexlink.kindIcon(Rexlink.dev?.kind)} —`
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

    DropArea {
        id: drop
        anchors.fill: parent
        anchors.margins: -6
        enabled: root.dropOn
        onEntered: d => d.accept(Qt.CopyAction)
        onDropped: d => {
            const paths = (d.urls ?? []).map(u => String(u)).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.slice(7)));
            if (!paths.length) return;
            d.accept(Qt.CopyAction);
            Rexlink.sendFiles(paths);
            Sounds.play("plug");
        }
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) Rexlink.ring();
        else if (mouse.button === Qt.MiddleButton) Rexlink.show("overview");
        else openMenu();
    }
}
