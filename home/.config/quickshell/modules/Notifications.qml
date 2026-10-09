import QtQuick
import qs.services

// ЛКМ — список уведомлений, ПКМ — «Не беспокоить», СКМ — очистить всё
BarText {
    id: root

    signal openCenter

    readonly property int count: Notifs.list.length

    active: count > 0 && !Notifs.dnd
    text: {
        const icon = Notifs.dnd ? Icons.bellOff : Icons.bell;
        return count > 0 ? `${icon} ${count}` : icon;
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) Notifs.toggleDnd();
        else if (mouse.button === Qt.MiddleButton) Notifs.clearAll();
        else openCenter();
    }
}
