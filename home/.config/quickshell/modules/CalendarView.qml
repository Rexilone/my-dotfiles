import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// месяц: клик по дню выбирает его, точка — у дня есть заметки
ColumnLayout {
    id: root

    property bool active: false
    property date selected: new Date()
    property int month: 0
    property int year: 0

    readonly property var locale: Qt.locale(I18n.locale)
    readonly property int cell: 32

    function reset() {
        const now = new Date();
        month = now.getMonth();
        year = now.getFullYear();
        selected = now;
    }

    function shift(delta) {
        const d = new Date(year, month + delta, 1);
        month = d.getMonth();
        year = d.getFullYear();
    }

    onActiveChanged: if (active) reset()
    Component.onCompleted: reset()

    spacing: 8

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    RowLayout {
        Layout.fillWidth: true

        Text {
            Layout.fillWidth: true
            leftPadding: 4
            text: `${root.locale.standaloneMonthName(root.month)} ${root.year}`
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
        }

        BarText {
            text: "‹"
            font.pixelSize: Theme.iconSize + 2
            active: false
            onClicked: root.shift(-1)
        }
        BarText {
            text: "›"
            font.pixelSize: Theme.iconSize + 2
            active: false
            onClicked: root.shift(1)
        }
    }

    Grid {
        columns: 7

        Repeater {
            model: Settings.weekStartsMonday ? ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"] : ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

            Text {
                required property string modelData
                width: root.cell
                height: 22
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: modelData
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }

        Repeater {
            model: 42

            Item {
                id: day

                required property int index
                readonly property int offset: (new Date(root.year, root.month, 1).getDay() + (Settings.weekStartsMonday ? 6 : 0)) % 7
                readonly property date date: new Date(root.year, root.month, 1 - offset + index)
                readonly property bool inMonth: date.getMonth() === root.month
                readonly property bool today: date.toDateString() === clock.date.toDateString()
                readonly property bool isSelected: date.toDateString() === root.selected.toDateString()
                readonly property bool hasNotes: Notes.notes && Notes.has(date)

                width: root.cell
                height: root.cell

                Rectangle {
                    anchors.centerIn: parent
                    width: root.cell - 4
                    height: root.cell - 4
                    radius: 9
                    color: day.today ? Theme.accent : dayArea.containsMouse ? Theme.surfaceHi2 : "transparent"
                    border.width: day.isSelected && !day.today ? 1.5 : 0
                    border.color: Theme.fg

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: day.hasNotes ? -2 : 0
                    text: day.date.getDate()
                    color: day.today ? Theme.bg : day.inMonth ? Theme.fg : Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: day.today || day.isSelected
                }

                // заметки в этот день
                Rectangle {
                    visible: day.hasNotes
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    width: 4
                    height: 4
                    radius: 2
                    color: day.today ? Theme.bg : Theme.warn
                }

                MouseArea {
                    id: dayArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selected = day.date;
                        if (!day.inMonth) root.shift(day.index < 7 ? -1 : 1);
                    }
                }
            }
        }

        WheelHandler {
            onWheel: ev => root.shift(ev.angleDelta.y > 0 ? -1 : 1)
        }
    }
}
