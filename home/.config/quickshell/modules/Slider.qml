import QtQuick
import qs.services

Item {
    id: root

    property real value: 0
    property real from: 0
    property real to: 1.5
    property real step: 0.05
    property bool muted: false
    property bool snapToOne: true      // «прилипание» к 100% для громкости
    property bool showMark: true
    property real level: -1            // уровень звука 0..1; -1 — без индикатора
    signal moved(real value)

    readonly property real ratio: Math.max(0, Math.min(1, (value - from) / (to - from)))

    function set(v) {
        v = Math.max(from, Math.min(to, v));
        if (snapToOne && Math.abs(v - 1) < 0.02) v = 1;
        moved(v);
    }

    implicitWidth: 160
    implicitHeight: 16

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: Theme.faint

        Rectangle {
            width: parent.width * root.ratio
            height: parent.height
            radius: parent.radius
            color: root.muted ? Theme.dim : root.snapToOne && root.value > 1 ? Theme.warn : Theme.accent
            // с индикатором звука полоса приглушена, а яркая часть показывает громкость сигнала
            opacity: root.level >= 0 ? 0.35 : 1
        }

        Rectangle {
            visible: root.level >= 0 && !root.muted
            width: parent.width * root.ratio * Math.min(1, root.level)
            height: parent.height
            radius: parent.radius
            color: root.snapToOne && root.value > 1 ? Theme.warn : Theme.accent

            Behavior on width { NumberAnimation { duration: 70 } }
        }

        // отметка 100%
        Rectangle {
            x: parent.width * (1 - root.from) / (root.to - root.from) - 1
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: 8
            radius: 1
            color: Theme.dim
            visible: root.showMark && root.to > 1 && root.from < 1
        }
    }

    Rectangle {
        x: track.width * root.ratio - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: area.pressed || area.containsMouse ? 12 : 10
        height: width
        radius: width / 2
        color: root.muted ? Theme.dim : Theme.fg

        Behavior on width { NumberAnimation { duration: Theme.animFast } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => root.set(root.from + (mouse.x - 4) / track.width * (root.to - root.from))
        onPositionChanged: mouse => {
            if (pressed) root.set(root.from + (mouse.x - 4) / track.width * (root.to - root.from));
        }
        onWheel: wheel => root.set(root.value + (wheel.angleDelta.y > 0 ? root.step : -root.step))
    }
}
