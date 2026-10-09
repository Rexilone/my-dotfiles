import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services

// иконка и заголовок активного окна
Row {
    id: root

    readonly property var win: Niri.focusedWindow
    readonly property var entry: win ? DesktopEntries.heuristicLookup(win.app_id) : null

    visible: !!win
    spacing: 8

    IconImage {
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: Theme.iconSize
        source: root.entry ? Quickshell.iconPath(root.entry.icon, true) : ""
        visible: source != ""
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, 380)
        elide: Text.ElideRight
        text: root.win ? (root.win.title || root.entry?.name || root.win.app_id) : ""
        color: Theme.muted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }
}
