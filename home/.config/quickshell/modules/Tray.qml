import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.services

// значки трея в баре. ЛКМ — открыть приложение, ПКМ — меню, СКМ — вторичное действие.
// items — какие показывать (по умолчанию все; в режиме «в меню» — только закреплённые)
Row {
    id: root

    property var items: SystemTray.items.values
    signal menuRequested(SystemTrayItem item, Item icon)

    spacing: 10

    Repeater {
        model: ScriptModel { values: root.items }

        TrayIcon {
            id: icon
            required property SystemTrayItem modelData
            item: modelData
            hovered: area.containsMouse
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -3
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: mouse => {
                    const item = icon.modelData;
                    if (mouse.button === Qt.MiddleButton)
                        item.secondaryActivate();
                    else if (mouse.button === Qt.RightButton || item.onlyMenu) {
                        if (item.hasMenu) root.menuRequested(item, icon);
                    } else
                        item.activate();
                }
                onWheel: wheel => icon.modelData.scroll(wheel.angleDelta.y, false)
            }
        }
    }
}
