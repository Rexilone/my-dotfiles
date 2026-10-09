import QtQuick
import qs.services

// ЛКМ — информация о сети
BarText {
    signal openInfo

    active: Net.type !== "none"
    text: Net.type === "ethernet" ? Icons.ethernet
        : Net.type === "wifi" ? Icons.wifi
        : Icons.offline
    font.pixelSize: Theme.iconSize

    onClicked: openInfo()
}
