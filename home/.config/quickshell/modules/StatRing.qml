import QtQuick
import qs.services

// кольцевой индикатор: значение 0..1, крупный текст в центре, подписи снизу
Item {
    id: root

    property real value: 0
    property string center: `${Math.round(value * 100)}%`
    property string label: ""
    property string sub: ""
    property int size: 108
    property int thickness: 8

    property real shown: value
    Behavior on shown { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    onShownChanged: ring.requestPaint()

    // battery: true — «мало» плохо (заряд), иначе «много» плохо (нагрузка)
    property bool battery: false
    readonly property color arcColor: battery
        ? (value <= 0.15 ? Theme.urgent : value <= 0.3 ? Theme.warn : Theme.accent)
        : (value > 0.9 ? Theme.urgent : value > 0.75 ? Theme.warn : Theme.accent)

    implicitWidth: size
    implicitHeight: size + labels.implicitHeight - 4

    Canvas {
        id: ring
        width: root.size
        height: root.size
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const r = (width - root.thickness) / 2;
            const cx = width / 2, cy = height / 2;
            const start = Math.PI * 0.75, sweep = Math.PI * 1.5;  // дуга 270°, разрыв снизу
            ctx.lineCap = "round";
            ctx.lineWidth = root.thickness;

            ctx.strokeStyle = Theme.surfaceHi2;
            ctx.beginPath();
            ctx.arc(cx, cy, r, start, start + sweep);
            ctx.stroke();

            const v = Math.max(0, Math.min(1, root.shown));
            if (v > 0.005) {
                ctx.strokeStyle = root.arcColor;
                ctx.beginPath();
                ctx.arc(cx, cy, r, start, start + sweep * v);
                ctx.stroke();
            }
        }
    }

    Text {
        anchors.centerIn: ring
        text: root.center
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize + 7
        font.bold: true
    }

    Column {
        id: labels
        anchors.top: ring.bottom
        anchors.topMargin: -4
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr(root.label)
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr(root.sub)
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }
}
