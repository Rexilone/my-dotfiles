import QtQuick
import QtQuick.Layouts
import qs.services

// погода: сейчас + 3 дня
ColumnLayout {
    spacing: 10
    width: 300

    Text {
        visible: !Weather.configured
        text: I18n.tr("Set your city in the clock menu → Weather")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    RowLayout {
        visible: Weather.configured
        spacing: 14

        Text {
            text: Weather.current ? Weather.info(Weather.current.code, Weather.current.isDay).icon : ""
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 48
        }

        ColumnLayout {
            spacing: 0

            Text {
                text: Weather.current ? `${Weather.current.temp}°` : "—"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 38
                font.bold: true
            }
            Text {
                text: `${Weather.city}  ·  ${Weather.current ? Weather.info(Weather.current.code, Weather.current.isDay).text : ""}`
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    RowLayout {
        visible: Weather.configured && Weather.daily.length > 1
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: Weather.daily.slice(1, 4)

            Rectangle {
                id: d
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 66
                radius: 12
                color: Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.7)

                Column {
                    anchors.centerIn: parent
                    spacing: 3

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.locale(I18n.locale).toString(d.modelData.date, "ddd")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: `${Weather.info(d.modelData.code, true).icon} ${d.modelData.max}°`
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                }
            }
        }
    }
}
