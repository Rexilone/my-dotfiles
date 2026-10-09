import QtQuick
import QtQuick.Layouts
import qs.services
import qs.settings

// страница плагина в Настройках → Плагины (можно использовать SCard, SSwitch, SChoice, SButton…)
ColumnLayout {
    id: root

    property var plugin

    spacing: 3

    SCard {
        title: "Greeting"
        desc: "Shown on right click and by `qs ipc call hello greet`"

        Rectangle {
            width: 240
            height: 34
            radius: 8
            color: Theme.surfaceHi
            border.width: 1
            border.color: input.activeFocus ? Theme.line : Theme.surfaceHi2

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                text: root.plugin ? root.plugin.get("greeting", "Hi!") : ""
                onEditingFinished: root.plugin.set("greeting", text)
            }
        }
    }

    SCard {
        title: "Icon"

        SChoice {
            options: ["👋", "🚀", "🐱", "⭐"].map(v => ({ value: v, label: v }))
            current: root.plugin ? root.plugin.get("icon", "👋") : "👋"
            onPicked: v => root.plugin.set("icon", v)
        }
    }

    SCard {
        title: "Reset counter"

        SButton {
            text: "Reset"
            onClicked: root.plugin.set("count", 0)
        }
    }
}
