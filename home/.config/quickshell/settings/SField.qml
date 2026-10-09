import QtQuick
import QtQuick.Layouts
import qs.services

// поле ввода: иконка, подсказка, Enter — accepted; multiline — Shift+Enter переносит строку
Rectangle {
    id: field

    property alias text: input.text
    property string placeholder: ""
    property string icon: ""
    property bool multiline: false
    readonly property alias input: input
    signal accepted

    function focusInput() { input.forceActiveFocus(); }

    Layout.fillWidth: true
    implicitWidth: 220
    implicitHeight: multiline ? Math.min(140, Math.max(38, input.contentHeight + 20)) : 38
    radius: 9
    color: Theme.surfaceHi
    border.width: 1
    border.color: input.activeFocus ? Theme.accent : Theme.surfaceHi2

    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        Text {
            visible: field.icon !== ""
            Layout.alignment: field.multiline ? Qt.AlignTop : Qt.AlignVCenter
            Layout.topMargin: field.multiline ? 10 : 0
            text: field.icon
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.iconSize - 1
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: input.contentHeight + (field.multiline ? 20 : 0)
            clip: true
            interactive: field.multiline && contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            TextEdit {
                id: input
                width: flick.width
                y: field.multiline ? 10 : (flick.height - contentHeight) / 2
                wrapMode: field.multiline ? TextEdit.Wrap : TextEdit.NoWrap
                color: Theme.fg
                selectionColor: Theme.accent
                selectedTextColor: Theme.bg
                selectByMouse: true
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                onCursorRectangleChanged: {
                    if (cursorRectangle.y < flick.contentY) flick.contentY = cursorRectangle.y;
                    else if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height)
                        flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height + 10;
                }
                Keys.onReturnPressed: event => {
                    if (field.multiline && (event.modifiers & Qt.ShiftModifier)) {
                        event.accepted = false;
                        return;
                    }
                    field.accepted();
                }
                Keys.onEnterPressed: field.accepted()

                Text {
                    visible: !input.text && !input.preeditText
                    text: I18n.tr(field.placeholder)
                    color: Theme.dim
                    elide: Text.ElideRight
                    width: parent.width
                    font: input.font
                }
            }
        }
    }
}
