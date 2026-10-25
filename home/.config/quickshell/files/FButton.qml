import QtQuick
import qs.services

// кнопка в духе Adwaita: плоская (значок и/или текст), flat: false — с фоном, suggested — акцентная,
// destructive — красная, circular — круглая; tip — подсказка снизу при наведении
Rectangle {
    id: b

    property int glyph: 0
    property string text: ""
    property string tip: ""
    property string key: ""
    property bool flat: true
    property bool checked: false
    property bool suggested: false
    property bool destructive: false
    property bool off: false
    property bool circular: false
    property int glyphSize: FStyle.icon + 1
    readonly property bool hovered: area.containsMouse
    signal clicked
    signal pressed

    readonly property bool tinted: suggested || destructive
    readonly property color tint: destructive ? Theme.urgent : Theme.accent

    implicitWidth: text ? row.implicitWidth + 26 : 34
    implicitHeight: 34
    radius: circular ? height / 2 : 8
    opacity: off ? 0.45 : 1
    color: tinted ? (area.pressed ? Qt.darker(tint, 1.15) : area.containsMouse ? Qt.lighter(tint, 1.08) : tint)
        : off ? (flat ? "transparent" : FStyle.field)
        : area.pressed ? FStyle.press
        : checked ? FStyle.press
        : area.containsMouse ? (flat ? FStyle.hover : FStyle.press)
        : flat ? "transparent" : FStyle.field

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            visible: b.glyph !== 0
            anchors.verticalCenter: parent.verticalCenter
            text: b.glyph ? String.fromCodePoint(b.glyph) : ""
            color: b.tinted ? Theme.bg : Theme.fg
            font.family: FStyle.glyphs
            font.pixelSize: b.glyphSize
        }
        Text {
            visible: b.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: b.text
            color: b.tinted ? Theme.bg : Theme.fg
            font.family: FStyle.ui
            font.pixelSize: FStyle.fs
            font.weight: b.flat && !b.tinted ? Font.Normal : Font.DemiBold
        }
    }

    // подсказка снизу, как в GTK — через полсекунды
    property bool tipShown: false
    Timer {
        id: tipDelay
        interval: 550
        onTriggered: b.tipShown = true
    }
    Rectangle {
        visible: b.tipShown
        z: 200
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 6
        width: tipText.implicitWidth + 18
        height: tipText.implicitHeight + 10
        radius: 7
        color: Theme.surfaceHi2
        border.width: 1
        border.color: FStyle.sep

        Text {
            id: tipText
            anchors.centerIn: parent
            text: b.tip + (b.key ? "   " + b.key : "")
            color: Theme.fg
            font.family: FStyle.ui
            font.pixelSize: FStyle.fsSmall
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: !b.off
        onContainsMouseChanged: {
            b.tipShown = false;
            if (containsMouse && b.tip) tipDelay.restart();
            else tipDelay.stop();
        }
        onPressed: { tipDelay.stop(); b.tipShown = false; b.pressed(); }
        onClicked: { Sounds.click(); b.clicked(); }
    }
}
