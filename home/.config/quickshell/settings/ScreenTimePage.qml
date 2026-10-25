import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services

// Экранное время: день по часам, неделя, программы. Всё считается и хранится только на этом компьютере
Page {
    id: page

    title: "Screen time"
    subtitle: "How much and in which apps the day went. Kept only on this computer"

    property string selected: ScreenTime.key()
    readonly property var week: ScreenTime.lastDays(7)
    readonly property real weekMax: Math.max(3600, ...week.map(d => d.sec))
    readonly property real dayTotal: ScreenTime.total(selected)
    readonly property var dayHours: ScreenTime.day(selected).hours
    readonly property real hourMax: Math.max(600, ...dayHours)
    readonly property var dayApps: ScreenTime.apps(selected)
    readonly property real avg: {
        const past = week.slice(0, 6).filter(d => d.sec > 0);
        return past.length ? past.reduce((a, d) => a + d.sec, 0) / past.length : 0;
    }
    readonly property bool today: selected === ScreenTime.key()

    // ── итог дня и часы
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: dayCol.implicitHeight + 44
        radius: 18
        color: Theme.surface

        ColumnLayout {
            id: dayCol
            x: 22
            y: 22
            width: parent.width - 44
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: page.today ? I18n.tr("Today") : Qt.locale(I18n.locale).toString(page.week.find(d => d.key === page.selected)?.date ?? new Date(), "dddd, d MMMM")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Text {
                        text: ScreenTime.fmt(page.dayTotal)
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 16
                        font.bold: true
                    }
                }
                // сравнение со средним за неделю
                Rectangle {
                    visible: page.today && page.avg > 0 && page.dayTotal > 0
                    readonly property real diff: (page.dayTotal - page.avg) / page.avg
                    implicitWidth: cmp.implicitWidth + 24
                    implicitHeight: 32
                    radius: 16
                    color: Theme.surfaceHi
                    Text {
                        id: cmp
                        anchors.centerIn: parent
                        text: `${parent.diff >= 0 ? "▲" : "▼"} ${Math.abs(Math.round(parent.diff * 100))}% ${I18n.tr(parent.diff >= 0 ? "more than usual" : "less than usual")}`
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }

            // часы дня
            Item {
                Layout.fillWidth: true
                implicitHeight: 110
                Row {
                    id: hours
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: hourLabels.top
                    anchors.bottomMargin: 6
                    height: 86
                    spacing: 3
                    Repeater {
                        model: 24
                        Item {
                            required property int index
                            readonly property real v: page.dayHours[index] ?? 0
                            width: (hours.width - 23 * hours.spacing) / 24
                            height: hours.height
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Math.max(3, parent.height * parent.v / page.hourMax)
                                radius: Math.min(4, width / 2)
                                color: parent.v > 0 ? Theme.accent : Theme.surfaceHi
                                opacity: parent.v > 0 ? 0.35 + 0.65 * parent.v / page.hourMax : 1
                            }
                        }
                    }
                }
                Item {
                    id: hourLabels
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 16
                    Repeater {
                        model: [0, 6, 12, 18]
                        Text {
                            required property int modelData
                            x: (hours.width / 24) * modelData
                            text: `${modelData}:00`
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 4
                        }
                    }
                }
            }
        }
    }

    // ── неделя: щелчок по дню — его подробности
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 176
        radius: 18
        color: Theme.surface

        Text {
            x: 22
            y: 18
            text: I18n.tr("Last 7 days")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
        Row {
            id: weekRow
            x: 22
            y: 48
            width: parent.width - 44
            height: 110
            spacing: 12
            Repeater {
                model: page.week
                Item {
                    id: wd
                    required property var modelData
                    readonly property bool sel: modelData.key === page.selected
                    width: (weekRow.width - 6 * weekRow.spacing) / 7
                    height: weekRow.height
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: bar.top
                        anchors.bottomMargin: 4
                        visible: wd.modelData.sec > 0
                        text: (wd.modelData.sec / 3600).toFixed(1)
                        color: wd.sel ? Theme.fg : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 4
                    }
                    Rectangle {
                        id: bar
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: dayName.top
                        anchors.bottomMargin: 6
                        width: Math.min(parent.width, 38)
                        height: Math.max(4, 66 * wd.modelData.sec / page.weekMax)
                        radius: 8
                        color: wd.sel ? Theme.accent : wdArea.containsMouse ? Theme.surfaceHi2 : Theme.surfaceHi
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }
                    Text {
                        id: dayName
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        text: Qt.locale(I18n.locale).toString(wd.modelData.date, "ddd")
                        color: wd.sel ? Theme.fg : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: wd.sel
                    }
                    MouseArea {
                        id: wdArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.selected = wd.modelData.key
                    }
                }
            }
        }
    }

    // ── программы дня
    SSection { text: I18n.tr("Apps") }

    SCard {
        visible: page.dayApps.length === 0
        icon: String.fromCodePoint(0xF0150)
        title: ScreenTime.enabled ? "Nothing yet" : "Screen time is off"
        desc: ScreenTime.enabled ? "Time in apps appears here as you use them" : "Turn it on below"
    }

    Rectangle {
        visible: page.dayApps.length > 0
        Layout.fillWidth: true
        implicitHeight: appCol.implicitHeight
        radius: 18
        color: Theme.surface
        clip: true

        ColumnLayout {
            id: appCol
            width: parent.width
            spacing: 0
            Repeater {
                model: page.dayApps.slice(0, 15)
                Item {
                    id: ar
                    required property var modelData
                    required property int index
                    // ярлыки программ читаются при запуске шелла — пересчитать, когда загрузятся
                    readonly property var info: DesktopEntries.applications.values.length >= 0 ? ScreenTime.app(modelData.id) : ({})
                    Layout.fillWidth: true
                    implicitHeight: 62
                    Rectangle {
                        visible: ar.index > 0
                        x: 72
                        width: parent.width - 92
                        height: 1
                        color: Theme.surfaceHi
                    }
                    IconImage {
                        x: 22
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 34
                        source: Quickshell.iconPath(ar.info.icon, "application-x-executable")
                    }
                    ColumnLayout {
                        x: 72
                        width: parent.width - 92
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: ar.info.name
                                elide: Text.ElideRight
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                            }
                            Text {
                                text: ScreenTime.fmt(ar.modelData.sec)
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 1
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 5
                            radius: 3
                            color: Theme.surfaceHi
                            Rectangle {
                                width: parent.width * ar.modelData.sec / Math.max(1, page.dayApps[0].sec)
                                height: parent.height
                                radius: 3
                                color: Theme.accent
                            }
                        }
                    }
                }
            }
        }
    }

    // ── настройки
    SSection { text: I18n.tr("Settings") }

    SCard {
        icon: String.fromCodePoint(0xF051B)
        title: "Count screen time"
        desc: "The app in focus, every 5 seconds; two minutes without mouse and keyboard don't count"
        SSwitch {
            checked: ScreenTime.enabled
            onToggled: v => Settings.setScreenTime("enabled", v)
        }
    }
    SCard {
        icon: Icons.trash
        title: "Forget the history"
        desc: "Delete all screen time records"
        SButton {
            text: "Forget"
            danger: true
            onClicked: ScreenTime.clear()
        }
    }
}
