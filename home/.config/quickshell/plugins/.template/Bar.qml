import QtQuick
import qs.services
import qs.modules

// модуль в баре (удали "bar" из plugin.json, если не нужен)
BarText {
    property var plugin

    text: "__NAME__"
    onClicked: plugin.notify("__NAME__", "Hello from the bar!")
}
