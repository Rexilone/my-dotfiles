import QtQuick
import qs.services

// спектр звука на рабочем столе (cava); без cava — подсказка
Item {
    implicitWidth: 320
    implicitHeight: 110

    Visualizer {
        anchors.centerIn: parent
        visible: Cava.installed
        count: 32
        barWidth: 6
        maxHeight: 110
        centered: false
    }

    Text {
        anchors.centerIn: parent
        visible: !Cava.installed
        text: I18n.tr("Install cava for the visualizer")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
    }
}
