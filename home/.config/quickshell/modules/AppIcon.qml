import QtQuick
import Quickshell
import Quickshell.Widgets

// иконка приложения с запасной, если в теме её нет
IconImage {
    id: root

    property string icon: ""
    readonly property string fallback: Quickshell.iconPath("application-x-executable")

    source: !icon ? fallback
          : icon.startsWith("/") || icon.includes("://") ? icon
          : Quickshell.iconPath(icon, fallback)
    onStatusChanged: if (status === Image.Error && source != fallback) source = fallback
}
