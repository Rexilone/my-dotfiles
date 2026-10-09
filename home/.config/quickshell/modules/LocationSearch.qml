import QtQuick
import QtQuick.Layouts
import qs.services

// поиск города: результаты с регионом, страной и населением
ColumnLayout {
    id: root

    spacing: 8

    function fmtPop(n) {
        if (!n) return "";
        return n >= 1e6 ? `${(n / 1e6).toFixed(1)}M people` : n >= 1e3 ? `${Math.round(n / 1e3)}k people` : `${n} people`;
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 38
        radius: 10
        color: Theme.surfaceHi
        border.width: input.activeFocus ? 1 : 0
        border.color: Theme.line

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Text {
                text: Icons.search
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.iconSize
            }

            TextInput {
                id: input
                Layout.fillWidth: true
                color: Theme.fg
                selectionColor: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                clip: true

                onTextChanged: debounce.restart()

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !input.text
                    text: I18n.tr(Weather.configured ? "Change city…" : "Search city, e.g. London")
                    color: Theme.dim
                    font: input.font
                }

                Keys.onReturnPressed: if (Weather.results.length) root.pick(Weather.results[0])
                Keys.onEnterPressed: if (Weather.results.length) root.pick(Weather.results[0])
                Keys.onEscapePressed: event => {
                    if (input.text) {
                        input.text = "";
                        event.accepted = true;
                    } else {
                        event.accepted = false;
                    }
                }
            }

            Text {
                visible: Weather.searching
                text: "…"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }
    }

    Timer {
        id: debounce
        interval: 350
        onTriggered: Weather.search(input.text)
    }

    function pick(r) {
        Weather.choose(r);
        input.text = "";
        input.focus = false;
    }

    Text {
        visible: input.text.trim().length >= 2 && !Weather.searching && Weather.results.length === 0
        text: I18n.tr("Nothing found")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
        leftPadding: 4
    }

    Repeater {
        model: input.text.trim().length >= 2 ? Weather.results : []

        Rectangle {
            id: res
            required property var modelData

            Layout.fillWidth: true
            implicitHeight: 44
            radius: 10
            color: resArea.containsMouse ? Theme.surfaceHi2 : "transparent"

            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Text {
                    text: String.fromCodePoint(0xF034E)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: I18n.tr(res.modelData.name)
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: [res.modelData.admin1, res.modelData.country].filter(s => s).join(", ")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                Text {
                    text: root.fmtPop(res.modelData.population)
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }

            MouseArea {
                id: resArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pick(res.modelData)
            }
        }
    }
}
