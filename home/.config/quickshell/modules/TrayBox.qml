import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs.services

// трей в меню: сетка приложений. ЛКМ — открыть, ПКМ — меню приложения, СКМ — вторичное действие,
// булавка — закрепить значок прямо в баре
ColumnLayout {
    id: root

    signal menuRequested(SystemTrayItem item, Item tile)
    signal activated

    readonly property var items: SystemTray.items.values
    readonly property int columns: Math.max(1, Math.min(4, items.length))

    spacing: 10

    MenuHeader {
        Layout.preferredWidth: root.columns * 84 + (root.columns - 1) * 4
        Layout.minimumWidth: 300
        icon: String.fromCodePoint(0xF003B)
        title: "Tray"
        subtitle: root.items.length === 0 ? "No apps in the tray"
                : `${root.items.length} ${I18n.plural(root.items.length, "app", "apps", "приложение", "приложения", "приложений")}`
        settingsPage: "bar"
    }

    GridLayout {
        columns: root.columns
        columnSpacing: 4
        rowSpacing: 4

        Repeater {
            model: ScriptModel { values: root.items }

            Rectangle {
                id: tile
                required property SystemTrayItem modelData
                readonly property bool pinned: Settings.trayIsPinned(modelData.id)

                // название без HTML и переносов строк: иначе Qt не обрезает его многоточием
                // короткое название приложения; подсказка бывает многострочной (Throne: «[Tun]\nThrone\n…»)
                readonly property string label: {
                    const clean = v => String(v ?? "").replace(/<[^>]*>/g, "").split("\n").map(l => l.trim()).filter(l => l)[0] ?? "";
                    return clean(modelData.title) || clean(modelData.tooltipTitle) || clean(modelData.id);
                }

                implicitWidth: 84
                implicitHeight: 76
                Layout.preferredWidth: 84
                Layout.preferredHeight: 76
                Layout.maximumWidth: 84
                radius: 10
                clip: true
                color: area.containsMouse ? Theme.surfaceHi : Theme.surface

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        const item = tile.modelData;
                        if (mouse.button === Qt.MiddleButton) {
                            item.secondaryActivate();
                        } else if (mouse.button === Qt.RightButton || item.onlyMenu) {
                            if (item.hasMenu) root.menuRequested(item, tile);
                        } else {
                            item.activate();
                            root.activated();
                        }
                    }
                    onWheel: wheel => tile.modelData.scroll(wheel.angleDelta.y, false)
                }

                TrayIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 14
                    item: tile.modelData
                    size: 22
                    hovered: area.containsMouse
                }

                Text {
                    x: 6
                    width: tile.width - 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    horizontalAlignment: Text.AlignHCenter
                    text: I18n.tr(tile.label)
                    textFormat: Text.PlainText
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    color: area.containsMouse ? Theme.fg : Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }

                // закрепить в баре: видна при наведении или если уже закреплено
                Text {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 5
                    visible: tile.pinned || area.containsMouse || pinArea.containsMouse
                    text: String.fromCodePoint(tile.pinned ? 0xF0403 : 0xF0931)
                    color: pinArea.containsMouse ? Theme.fg : tile.pinned ? Theme.accent : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize - 2

                    MouseArea {
                        id: pinArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.setTrayPinned(tile.modelData.id, !tile.pinned)
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.maximumWidth: root.columns * 84 + (root.columns - 1) * 4
        Layout.minimumWidth: 300
        text: I18n.tr("Right-click — app menu. Pin — keep the icon in the bar.")
        wrapMode: Text.Wrap
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }
}
