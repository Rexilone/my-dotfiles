import QtQuick
import QtQuick.Layouts
import qs.services

// текущая погода + прогноз на 4 дня
Item {
    id: root

    implicitWidth: 560
    implicitHeight: Weather.configured ? layout.implicitHeight : 90

    Column {
        anchors.centerIn: parent
        visible: !Weather.configured
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String.fromCodePoint(0xF0595)
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 30
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("Find your city below")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
    }

    RowLayout {
        id: layout
        anchors.fill: parent
        visible: Weather.configured
        spacing: 20

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            // место + статус
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: `${String.fromCodePoint(0xF034E)} ${Weather.city}` + (Weather.region ? `  ·  ${Weather.region}` : "")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }

            RowLayout {
                spacing: 14

                Text {
                    text: Weather.current ? Weather.info(Weather.current.code, Weather.current.isDay).icon : ""
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 52
                }

                ColumnLayout {
                    spacing: 0

                    Text {
                        text: Weather.current ? `${Weather.current.temp}°` : "—"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 40
                        font.bold: true
                    }
                    Text {
                        text: Weather.current ? Weather.info(Weather.current.code, Weather.current.isDay).text : ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                }
            }

            Text {
                visible: !!Weather.current
                text: Weather.current
                    ? `feels ${Weather.current.feels}°    ${String.fromCodePoint(0xF058E)} ${Weather.current.humidity}%    ${String.fromCodePoint(0xF059D)} ${Weather.current.wind} m/s`
                    : ""
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }

            Text {
                text: Weather.loading ? "updating…"
                    : Weather.error ? `offline · showing data from ${Weather.ago()}`
                    : Weather.updatedAt ? `updated ${Weather.ago()}` : ""
                color: Weather.error ? Theme.warn : Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
        }

        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: 6

            Repeater {
                model: Weather.daily.slice(1, 5)

                Rectangle {
                    id: dayCard
                    required property var modelData
                    width: 60
                    height: 104
                    radius: 12
                    color: Theme.surfaceHi

                    Column {
                        anchors.centerIn: parent
                        spacing: 7

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.locale(I18n.locale).toString(dayCard.modelData.date, "ddd")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Weather.info(dayCard.modelData.code, true).icon
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 22
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: `${dayCard.modelData.max}°`
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: `${dayCard.modelData.min}°`
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }
            }
        }
    }
}
