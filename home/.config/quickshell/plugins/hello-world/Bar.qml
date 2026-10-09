import QtQuick
import qs.services
import qs.modules

// модуль в баре: значок и счётчик кликов (хранится между перезапусками)
BarText {
    id: root

    // шелл передаёт сюда API плагина: plugin.get/set/notify/run
    property var plugin
    property int count: plugin ? plugin.get("count", 0) : 0

    text: `${plugin ? plugin.get("icon", "👋") : "👋"} ${count}`

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            plugin.notify("Hello World", plugin.get("greeting", "Hi!"));
            return;
        }
        count++;
        plugin.set("count", count);
    }
}
