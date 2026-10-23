import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services

// длинный скриншот: рамка вокруг области (снаружи — в кадр не попадает) и панель «Готово / Отмена».
// Всё, кроме панели, пропускает мышь: область прокручивают как обычно.
PanelWindow {
    id: win

    required property var modelData     // ctl.longCap
    required property var ctl

    screen: Quickshell.screens.find(s => s.name === modelData.screen) ?? Quickshell.screens[0]
    readonly property rect r: Qt.rect(modelData.x - screen.x, modelData.y - screen.y, modelData.w, modelData.h)

    color: "transparent"
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: card }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-screenshot-long"

    Rectangle {
        x: win.r.x - 3
        y: win.r.y - 3
        width: win.r.width + 6
        height: win.r.height + 6
        color: "transparent"
        radius: 4
        border.width: 2
        border.color: Theme.accent
    }

    Rectangle {
        id: card
        x: Math.max(8, Math.min(win.width - width - 8, win.r.x + (win.r.width - width) / 2))
        y: win.r.y + win.r.height + 12 + height < win.height ? win.r.y + win.r.height + 12 : Math.max(8, win.r.y - height - 12)
        width: row.implicitWidth + 24
        height: 50
        radius: 14
        color: Theme.panel
        border.width: 1
        border.color: Theme.line

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 10

            Text {
                text: String.fromCodePoint(0xF0BBE)
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 2
            }
            Text {
                text: I18n.tr("Scroll the area") + (win.ctl.longHeight ? `   ·   ${win.ctl.longHeight} px` : "")
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
            ToolButton {
                label: "Done"
                active: true
                onClicked: win.ctl.stopLong(true)
            }
            ToolButton {
                label: "Cancel"
                onClicked: win.ctl.stopLong(false)
            }
        }
    }
}
