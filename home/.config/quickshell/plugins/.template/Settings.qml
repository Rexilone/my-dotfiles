import QtQuick
import QtQuick.Layouts
import qs.services
import qs.settings

// страница настроек (удали "settings" из plugin.json, если не нужна)
ColumnLayout {
    property var plugin
    spacing: 3

    SCard {
        title: "Example option"
        SSwitch {
            checked: plugin ? plugin.get("enabled", true) : true
            onToggled: v => plugin.set("enabled", v)
        }
    }
}
