import QtQuick
import qs.services

// график нагрузки процессора и его температуры за последние ~2 минуты
Column {
    id: root

    property bool active: true
    readonly property int samples: 80
    property var load: []
    property var temp: []

    readonly property string uid: `graph-${Math.random()}`
    onActiveChanged: SysStats.need(uid, active)
    Component.onCompleted: SysStats.need(uid, active)
    Component.onDestruction: SysStats.need(uid, false)

    spacing: 12

    // новый замер каждые 1.5 с (как опрос SysStats)
    Timer {
        running: root.active
        interval: 1500
        repeat: true
        onTriggered: {
            root.load = root.load.concat([SysStats.cpu]).slice(-root.samples);
            // 30..100 °C → 0..1
            root.temp = root.temp.concat([Math.max(0, Math.min(1, (SysStats.cpuTemp - 30) / 70))]).slice(-root.samples);
            graph.requestPaint();
        }
    }

    Canvas {
        id: graph
        width: 300
        height: 96

        function line(ctx, data, top, h, color) {
            if (data.length < 2) return;
            const dx = width / (root.samples - 1), x0 = width - (data.length - 1) * dx;
            ctx.beginPath();
            data.forEach((v, i) => {
                const x = x0 + i * dx, y = top + h - v * h;
                i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
            });
            ctx.strokeStyle = color;
            ctx.lineWidth = 1.6;
            ctx.lineJoin = "round";
            ctx.stroke();
            // мягкая заливка под линией
            ctx.lineTo(width, top + h);
            ctx.lineTo(x0, top + h);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.1);
            ctx.fill();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const h = (height - 8) / 2;
            line(ctx, root.load, 0, h, Theme.fg);
            line(ctx, root.temp, h + 8, h, Theme.accent);
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 22

        Text {
            text: `${String.fromCodePoint(0xF0EE0)}  ${Math.round(SysStats.cpu * 100)}%`
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
        Text {
            text: `${String.fromCodePoint(0xF0238)}  ${Math.round(SysStats.cpuTemp)}°C`
            color: Theme.accent
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
    }
}
