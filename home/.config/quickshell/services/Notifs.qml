pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// сервер уведомлений вместо mako
Singleton {
    id: root

    readonly property var list: server.trackedNotifications.values
    readonly property bool dnd: persist.dnd
    property var popups: []   // уведомления, показанные сейчас всплывающими
    property var times: ({})  // id -> время прихода
    property date now: new Date()

    function toggleDnd() {
        persist.dnd = !persist.dnd;
        if (persist.dnd) popups = popups.filter(n => n.urgency === NotificationUrgency.Critical);
    }

    function hidePopup(n) {
        popups = popups.filter(p => p !== n);
    }

    function clearAll() {
        for (const n of list.slice()) n.dismiss();
        popups = [];
    }

    function timeAgo(n) {
        const t = times[n.id];
        if (!t) return "";
        const min = Math.floor((now - t) / 60000);
        if (min < 1) return "now";
        if (min < 60) return `${min}m`;
        const h = Math.floor(min / 60);
        if (h < 24) return `${h}h`;
        return Qt.locale(I18n.locale).toString(t, "d MMM");
    }

    function iconFor(n) {
        if (n.image) return n.image;
        const icon = n.appIcon || n.desktopEntry;
        if (!icon) return "";
        if (icon.startsWith("/") || icon.includes("://")) return icon;
        return Quickshell.iconPath(icon, true);
    }

    PersistentProperties {
        id: persist
        reloadableId: "notifs"
        property bool dnd: false
    }

    NotificationServer {
        id: server

        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: n => {
            n.tracked = true;
            // уведомления, пережившие перезагрузку конфига, повторно не показываем
            if (n.lastGeneration) return;
            root.times[n.id] = new Date();
            root.timesChanged();
            n.closed.connect(() => root.hidePopup(n));
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                root.popups = root.popups.filter(p => p !== n).concat([n]);
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }
}
