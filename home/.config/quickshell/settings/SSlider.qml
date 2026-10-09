import QtQuick
import qs.services
import qs.modules

// слайдер со значением справа
Row {
    id: s

    property real value: 0
    property real from: 0
    property real to: 1
    property real step: 0.05
    property string suffix: ""
    property int decimals: 0
    property real display: value        // что показывать в подписи
    signal moved(real value)

    spacing: 12

    Slider {
        width: 200
        anchors.verticalCenter: parent.verticalCenter
        value: s.value
        from: s.from
        to: s.to
        step: s.step
        snapToOne: false
        showMark: false
        onMoved: v => s.moved(Math.round(v / s.step) * s.step)
    }

    Text {
        width: 56
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: `${Number(s.display).toFixed(s.decimals)}${s.suffix}`
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }
}
