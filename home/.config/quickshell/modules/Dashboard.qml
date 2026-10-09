import QtQuick
import QtQuick.Layouts
import qs.services

// окно по клику на часы: вкладки Календарь / Плеер / Погода / Система
ColumnLayout {
    id: root

    property bool active: false
    property int current: 0
    signal openSettings

    readonly property var tabs: [
        { icon: 0xF00ED, label: "Calendar" },
        { icon: 0xF075A, label: "Media" },
        { icon: 0xF0595, label: "Weather" },
        { icon: 0xF061A, label: "System" },
    ]

    width: 620
    spacing: 12

    // ── вкладки
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 40
        radius: 12
        color: Theme.surface

        Rectangle {
            id: indicator
            property Item target: tabRow.children[root.current] ?? null
            x: target ? tabRow.x + target.x : 0
            y: 4
            width: target ? target.width : 0
            height: parent.height - 8
            radius: 9
            color: Theme.surfaceHi2

            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        Row {
            id: tabRow
            x: 4
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: root.tabs

                Item {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property bool selected: root.current === index

                    width: (620 - 8 - 44) / root.tabs.length
                    height: 32

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: String.fromCodePoint(tab.modelData.icon)
                            color: tab.selected ? Theme.fg : tabArea.containsMouse ? Theme.muted : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: I18n.tr(tab.modelData.label)
                            color: tab.selected ? Theme.fg : tabArea.containsMouse ? Theme.muted : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: tab.selected
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: tabArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.current = tab.index
                    }
                }
            }
        }

        WheelHandler {
            onWheel: ev => root.current = Math.max(0, Math.min(root.tabs.length - 1, root.current + (ev.angleDelta.y > 0 ? -1 : 1)))
        }

        // шестерёнка — открыть Настройки
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 32
            radius: 9
            color: gearArea.containsMouse ? Theme.surfaceHi2 : "transparent"

            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            Text {
                anchors.centerIn: parent
                text: String.fromCodePoint(0xF0493)
                rotation: gearArea.containsMouse ? 60 : 0
                color: gearArea.containsMouse ? Theme.fg : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 1

                Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                id: gearArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSettings()
            }
        }
    }

    // ── страницы
    Item {
        id: pages
        Layout.fillWidth: true
        implicitHeight: [calendarPage, mediaPage, weatherPage, systemPage][root.current].implicitHeight
        clip: true

        Behavior on implicitHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        component Page: ColumnLayout {
            required property int page
            width: pages.width
            spacing: 10
            opacity: root.current === page ? 1 : 0
            visible: opacity > 0
            x: (page - root.current) * 40

            Behavior on opacity { NumberAnimation { duration: 200 } }
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        Page {
            id: calendarPage
            page: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                DashTile {
                    Layout.alignment: Qt.AlignTop
                    CalendarView {
                        id: calendar
                        active: root.active
                    }
                }

                DashTile {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    NotesPanel {
                        width: parent.width
                        height: parent.height
                        date: calendar.selected
                    }
                }
            }
        }

        Page {
            id: mediaPage
            page: 1

            DashTile {
                Layout.fillWidth: true
                padding: 18

                MediaWidget {
                    width: parent.width
                    artSize: 150
                    active: root.active && root.current === 1
                }
            }
        }

        Page {
            id: weatherPage
            page: 2

            DashTile {
                Layout.fillWidth: true
                padding: 18

                WeatherWidget {
                    width: parent.width
                }
            }

            DashTile {
                Layout.fillWidth: true
                padding: 12

                LocationSearch {
                    width: parent.width
                }
            }
        }

        Page {
            id: systemPage
            page: 3

            DashTile {
                Layout.fillWidth: true
                padding: 22

                PerfWidget {
                    width: parent.width
                    active: root.active && root.current === 3
                }
            }
        }
    }
}
