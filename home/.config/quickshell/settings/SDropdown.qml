import QtQuick
import QtQuick.Controls
import qs.services

// выпадающий список: [{ value, label }]
Rectangle {
    id: dd

    property var options: []
    property var current
    property int minWidth: 180
    property bool searchable: options.length > 12
    property bool fontPreview: false      // показать название шрифтом, который оно обозначает
    signal picked(var value)

    property string filter: ""

    // куда открывать список: вниз, а если внизу мало места — вверх; высота — по свободному месту
    property bool openUp: false
    property real maxListHeight: 320

    function openList() {
        dd.filter = "";
        dd.place();
        popup.open();
    }

    function place() {
        const win = dd.Window.window;
        if (!win) return;
        const pos = dd.mapToItem(null, 0, 0);
        const below = win.height - pos.y - dd.height - 16;
        const above = pos.y - 16;
        const extra = dd.searchable ? 44 : 8;
        const want = Math.min(320, dd.options.length * 32) + extra;
        dd.openUp = below < want && above > below;
        dd.maxListHeight = Math.max(96, Math.min(320, (dd.openUp ? above : below) - extra));
    }
    readonly property var shown: {
        const q = filter.trim().toLowerCase();
        return q ? options.filter(o => (String(o.label) + " " + I18n.tr(String(o.label))).toLowerCase().includes(q)) : options;
    }

    readonly property var selectedOption: options.find(o => JSON.stringify(o.value) === JSON.stringify(current)) ?? null

    implicitWidth: Math.max(minWidth, label.implicitWidth + 50)
    implicitHeight: 34
    radius: 8
    color: area.containsMouse || popup.visible ? Theme.surfaceHi2 : Theme.surfaceHi
    border.width: 1
    border.color: popup.visible ? Theme.line : Theme.surfaceHi2

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Text {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 42
        elide: Text.ElideRight
        text: I18n.tr(dd.selectedOption?.label ?? "—")
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: String.fromCodePoint(0xF0140)  // chevron-down
        rotation: popup.visible ? 180 : 0
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.iconSize

        Behavior on rotation { NumberAnimation { duration: Theme.animSlow } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (popup.visible) {
                popup.close();
            } else {
                dd.filter = "";
                dd.place();
                popup.open();
                if (dd.searchable) filterInput.forceActiveFocus();
            }
        }
    }

    Popup {
        id: popup

        y: dd.openUp ? -height - 4 : dd.height + 4
        // страховка: список никогда не выходит за края окна
        margins: 8
        width: Math.max(dd.width, dd.fontPreview ? 300 : 200)
        padding: 4

        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 } }

        background: Rectangle {
            radius: 10
            color: Theme.surface
            border.width: 1
            border.color: Theme.line
        }

        contentItem: Column {
            spacing: 4

            // поиск по длинному списку
            Rectangle {
                visible: dd.searchable
                width: parent.width
                height: 32
                radius: 7
                color: Theme.surfaceHi

                TextInput {
                    id: filterInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    clip: true
                    onTextChanged: dd.filter = text
                    Keys.onReturnPressed: if (dd.shown.length) { dd.picked(dd.shown[0].value); popup.close(); }
                    Keys.onEscapePressed: popup.close()

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !filterInput.text
                        text: I18n.ru ? `Поиск: ${dd.options.length}…` : `Search ${dd.options.length} items…`
                        color: Theme.dim
                        font: filterInput.font
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                implicitHeight: Math.min(contentHeight, dd.maxListHeight)
                height: implicitHeight
                clip: true
                model: dd.shown
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true

                delegate: Rectangle {
                    id: item
                    required property var modelData
                    readonly property bool selected: JSON.stringify(modelData.value) === JSON.stringify(dd.current)

                    width: ListView.view.width
                    height: 32
                    radius: 7
                    color: itemArea.containsMouse ? Theme.surfaceHi2 : "transparent"

                    Rectangle {
                        visible: item.selected
                        x: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 14
                        radius: 2
                        color: Theme.accent
                    }

                    Text {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 20
                        elide: Text.ElideRight
                        text: I18n.tr(item.modelData.label)
                        color: item.selected ? Theme.fg : Theme.muted
                        font.family: dd.fontPreview && item.modelData.value ? item.modelData.value : Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: item.selected
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dd.picked(item.modelData.value);
                            popup.close();
                        }
                    }
                }
            }
        }
    }
}
