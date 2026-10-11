import QtQuick
import qs.services

// бар как в шелле (стиль из темы: flat | floating | pills): система, часы, раскладка, сеанс, питание
Item {
    id: bar

    property bool main: false
    readonly property string style: G.barStyle
    readonly property int gap: style === "flat" ? 0 : 6
    readonly property int side: style === "floating" ? 10 : style === "pills" ? 8 : 0
    property string armed: ""            // действие питания, ждущее второго нажатия

    implicitHeight: G.barHeight + gap
    height: implicitHeight

    Timer {
        id: disarm
        interval: 3000
        onTriggered: bar.armed = ""
    }
    function power(action) {
        if (action === "suspend" || bar.armed === action) {
            bar.armed = "";
            G.power(action);
        } else {
            bar.armed = action;
            disarm.restart();
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: bar.gap
        anchors.leftMargin: bar.side
        anchors.rightMargin: bar.side
        visible: bar.style !== "pills"
        radius: bar.style === "floating" ? 14 : 0
        color: G.panel
        border.width: bar.style === "floating" ? 1 : 0
        border.color: G.surfaceHi2
    }

    Item {
        anchors.fill: parent
        anchors.topMargin: bar.gap
        anchors.leftMargin: bar.side + (bar.style === "pills" ? 0 : 12)
        anchors.rightMargin: bar.side + (bar.style === "pills" ? 0 : 12)

        // ── слева: система
        Pill {
            anchors.left: parent.left
            pills: bar.style === "pills"
            BarText { text: String.fromCodePoint(0xF08C7); size: G.iconSize + 2 }
            BarText { text: G.host || "Rexilone"; color: G.muted }
        }

        // ── по центру: дата и время
        Pill {
            id: clockPill
            visible: G.clock
            anchors.horizontalCenter: parent.horizontalCenter
            pills: bar.style === "pills"
            property date now: new Date()
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: clockPill.now = new Date()
            }
            BarText {
                text: clockPill.now.toLocaleDateString(Qt.locale(G.ru ? "ru_RU" : "en_US"), "ddd, d MMMM")
                color: G.muted
            }
            BarText {
                text: Qt.formatTime(clockPill.now, "HH:mm")
                bold: true
            }
        }

        // ── справа: раскладка, сеанс, питание
        Row {
            anchors.right: parent.right
            height: parent.height
            spacing: 10

            Pill {
                visible: bar.main && G.layouts.length > 0
                pills: bar.style === "pills"
                BarText {
                    text: `${String.fromCodePoint(0xF030C)}  ${G.layout}`
                    clickable: true
                    onClicked: G.nextLayout()
                }
            }
            Pill {
                visible: bar.main
                pills: bar.style === "pills"
                BarText {
                    text: `${String.fromCodePoint(0xF0379)}  ${G.session.name}`
                    color: G.sessions.length > 1 ? G.fg : G.muted
                    clickable: G.sessions.length > 1
                    onClicked: G.nextSession()
                }
            }
            Pill {
                pills: bar.style === "pills"
                Repeater {
                    model: [
                        { action: "suspend", icon: 0xF0904, en: "Sleep", ru: "Сон" },
                        { action: "reboot", icon: 0xF0709, en: "Restart", ru: "Перезагрузить" },
                        { action: "poweroff", icon: 0xF0425, en: "Shut down", ru: "Выключить" },
                    ]
                    BarText {
                        required property var modelData
                        readonly property bool isArmed: bar.armed === modelData.action
                        text: isArmed ? `${String.fromCodePoint(modelData.icon)}  ${G.tr(modelData.en, modelData.ru)}?`
                                      : String.fromCodePoint(modelData.icon)
                        size: G.iconSize + 1
                        color: isArmed ? G.urgent : G.fg
                        clickable: true
                        opacity: !isArmed && hovered ? 0.75 : 1
                        onClicked: bar.power(modelData.action)
                    }
                }
            }
        }
    }

    // группа элементов; в стиле pills — своя плашка
    component Pill: Item {
        id: pill
        property bool pills: false
        default property alias content: row.data
        height: parent.height
        implicitWidth: row.implicitWidth + (pills ? 28 : 0)
        width: implicitWidth

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            visible: pill.pills
            radius: height / 2
            color: G.panel
            border.width: 1
            border.color: G.surfaceHi2
        }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 12
        }
    }

    component BarText: Text {
        id: bt
        property int size: G.fontSize
        property bool bold: false
        property bool clickable: false
        signal clicked
        anchors.verticalCenter: parent?.verticalCenter
        color: G.fg
        font.family: G.font
        font.pixelSize: size
        font.bold: bold
        readonly property bool hovered: ma.containsMouse
        Behavior on color { ColorAnimation { duration: G.animFast } }

        MouseArea {
            id: ma
            anchors.fill: parent
            anchors.margins: -6
            enabled: bt.clickable
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: bt.clicked()
        }
    }
}
