import QtQuick
import QtQuick.Layouts
import qs.services

// заметки выбранного дня; со временем — это напоминание (придёт уведомлением)
ColumnLayout {
    id: root

    required property date date

    readonly property var items: Notes.notes ? Notes.list(date) : []
    readonly property bool isToday: date.toDateString() === new Date().toDateString()

    function submit() {
        if (!noteInput.text.trim()) return;
        Notes.add(root.date, noteInput.text, timeInput.text);
        noteInput.text = "";
        timeInput.text = "";
        noteInput.forceActiveFocus();
    }

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            text: Qt.locale(I18n.locale).toString(root.date, "dddd, d MMMM")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
        }

        Rectangle {
            visible: root.isToday
            implicitWidth: todayText.implicitWidth + 12
            implicitHeight: 18
            radius: 6
            color: Theme.surfaceHi2

            Text {
                id: todayText
                anchors.centerIn: parent
                text: I18n.tr("today")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }

    // список
    Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 150
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: parent.width
            spacing: 6

            Text {
                visible: root.items.length === 0
                width: parent.width
                topPadding: 40
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("No notes\nadd one below")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }

            Repeater {
                model: root.items

                Rectangle {
                    id: note
                    required property var modelData
                    readonly property bool done: modelData.time && modelData.notified

                    width: list.width
                    height: noteRow.implicitHeight + 16
                    radius: 10
                    color: noteArea.containsMouse ? Theme.surfaceHi2 : Theme.surfaceHi

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    MouseArea {
                        id: noteArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    RowLayout {
                        id: noteRow
                        x: 10
                        y: 8
                        width: parent.width - 20
                        spacing: 8

                        // время напоминания
                        Rectangle {
                            visible: note.modelData.time !== ""
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: timeRow.implicitWidth + 12
                            implicitHeight: 20
                            radius: 6
                            color: note.done ? Theme.surfaceHi2 : Theme.fg

                            Row {
                                id: timeRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: String.fromCodePoint(0xF009A)
                                    color: note.done ? Theme.dim : Theme.bg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 3
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: note.modelData.time
                                    color: note.done ? Theme.dim : Theme.bg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 2
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: note.modelData.text
                            wrapMode: Text.Wrap
                            color: note.done ? Theme.dim : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }

                        Text {
                            Layout.alignment: Qt.AlignTop
                            text: Icons.close
                            opacity: noteArea.containsMouse || delArea.containsMouse ? 1 : 0
                            color: delArea.containsMouse ? Theme.urgent : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize

                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                            MouseArea {
                                id: delArea
                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Notes.remove(root.date, note.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // ввод: текст + необязательное время
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 40
        radius: 10
        color: Theme.surfaceHi
        border.width: noteInput.activeFocus || timeInput.activeFocus ? 1 : 0
        border.color: Theme.line

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 6
            spacing: 8

            TextInput {
                id: noteInput
                Layout.fillWidth: true
                color: Theme.fg
                selectionColor: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                clip: true

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !noteInput.text && !noteInput.activeFocus
                    text: I18n.tr("Add a note…")
                    color: Theme.dim
                    font: noteInput.font
                }

                Keys.onReturnPressed: root.submit()
                Keys.onEnterPressed: root.submit()
                Keys.onTabPressed: timeInput.forceActiveFocus()
            }

            // время напоминания
            Rectangle {
                implicitWidth: 78
                implicitHeight: 28
                radius: 7
                color: timeInput.activeFocus || timeInput.text ? Theme.surfaceHi2 : "transparent"

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: String.fromCodePoint(0xF009A)
                        color: timeInput.text ? Theme.fg : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextInput {
                        id: timeInput
                        width: 42
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        maximumLength: 5
                        validator: RegularExpressionValidator { regularExpression: /^[0-2]?\d:?[0-5]?\d?$/ }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: !timeInput.text
                            text: I18n.tr("time")
                            color: Theme.dim
                            font: timeInput.font
                        }

                        Keys.onReturnPressed: root.submit()
                        Keys.onEnterPressed: root.submit()
                        Keys.onBacktabPressed: noteInput.forceActiveFocus()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: timeInput.forceActiveFocus()
                }
            }

            // добавить
            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: 7
                color: addArea.containsMouse ? Theme.fgHover : Theme.fg
                opacity: noteInput.text.trim() ? 1 : 0.3

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.bg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 3
                    font.bold: true
                }

                MouseArea {
                    id: addArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.submit()
                }
            }
        }
    }
}
