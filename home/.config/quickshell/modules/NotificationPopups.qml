import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.services

// всплывающие уведомления в правом верхнем углу.
// phone: true — только уведомления телефона (Rexlink), на своём слое: niri может
// скрывать его с демонстрации экрана (Настройки → Телефон)
PanelWindow {
    id: root

    property bool phone: false
    property bool allowed: true
    property real topOffset: 0

    function isPhone(n) {
        return (n?.desktopEntry ?? "") === "rexlink";
    }
    readonly property var shown: Notifs.popups.filter(n => isPhone(n) === root.phone)

    visible: allowed && shown.length > 0

    anchors {
        top: true
        right: true
    }
    margins {
        top: 8 + root.topOffset
        right: 8
    }
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    implicitWidth: 380
    implicitHeight: Math.max(1, column.implicitHeight)
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: root.phone ? "quickshell-notifications-phone" : "quickshell-notifications"

    Column {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            model: ScriptModel { values: root.shown }

            Item {
                id: wrapper

                required property Notification modelData
                property bool leaving: false

                width: column.width
                height: card.height

                function leave(dismiss) {
                    if (leaving) return;
                    leaving = true;
                    out.dismiss = dismiss;
                    out.start();
                }

                NotificationCard {
                    id: card
                    width: parent.width
                    notif: wrapper.modelData
                    bordered: true
                    x: parent.width
                    onCloseRequested: wrapper.leave(true)

                    Component.onCompleted: slideIn.start()

                    NumberAnimation on x {
                        id: slideIn
                        running: false
                        to: 0
                        duration: Theme.animSlow + 60
                        easing.type: Easing.OutCubic
                    }
                }

                SequentialAnimation {
                    id: out
                    property bool dismiss: false

                    NumberAnimation {
                        target: card
                        property: "x"
                        to: wrapper.width
                        duration: Theme.animSlow
                        easing.type: Easing.InCubic
                    }
                    ScriptAction {
                        script: {
                            if (out.dismiss) wrapper.modelData.dismiss();
                            else Notifs.hidePopup(wrapper.modelData);
                        }
                    }
                }

                Timer {
                    readonly property real seconds: wrapper.modelData.expireTimeout
                    interval: seconds > 0 ? seconds * 1000 : Settings.popupTimeout * 1000
                    running: !wrapper.leaving && !card.containsMouse
                        && wrapper.modelData.urgency !== NotificationUrgency.Critical
                    onTriggered: wrapper.leave(false)
                }
            }
        }
    }
}
