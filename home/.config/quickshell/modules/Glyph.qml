import QtQuick
import qs.services

// значок Nerd Font точно по центру кнопки. В обычном варианте шрифта значки шире своей ячейки,
// и Text с anchors.centerIn рисует их со сдвигом; в моно-варианте значок вписан в ячейку,
// поэтому центровка по ширине символа совпадает с центром рисунка. Моно-значки мельче —
// размер увеличен, чтобы значок выглядел как раньше. Вращение идёт вокруг центра значка.
Item {
    id: root

    property string text: ""
    property color color: Theme.fg
    property int pixelSize: Theme.iconSize

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.color
        font.family: "JetBrainsMono Nerd Font Mono"
        font.pixelSize: Math.round(root.pixelSize * 1.4)

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
}
