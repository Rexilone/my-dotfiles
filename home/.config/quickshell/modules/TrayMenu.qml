import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services

// меню приложения из трея (dbusmenu); подменю раскрываются внутри
ColumnLayout {
    id: root

    property var menu: null
    property int depth: 0
    property string title: ""
    signal close

    width: 300 - depth * 12
    spacing: 0

    MenuHeader {
        visible: root.depth === 0 && root.title !== ""
        Layout.bottomMargin: 6
        icon: String.fromCodePoint(0xF0DCA)
        title: root.title
        subtitle: "App menu"
    }

    QsMenuOpener {
        id: opener
        menu: root.menu
    }

    Repeater {
        model: opener.children

        ColumnLayout {
            id: entry

            required property QsMenuEntry modelData
            property bool expanded: false

            Layout.fillWidth: true
            spacing: 0

            Rectangle {
                visible: entry.modelData.isSeparator
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                implicitHeight: 1
                color: Theme.faint
            }

            Rectangle {
                visible: !entry.modelData.isSeparator
                Layout.fillWidth: true
                implicitHeight: 28
                radius: 6
                color: area.containsMouse && entry.modelData.enabled ? Theme.faint : "transparent"

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        visible: entry.modelData.buttonType !== QsMenuButtonType.None
                        readonly property bool radio: entry.modelData.buttonType === QsMenuButtonType.RadioButton
                        readonly property bool checked: entry.modelData.checkState === Qt.Checked
                        text: radio ? (checked ? Icons.radioOn : Icons.radioOff)
                                    : (checked ? Icons.checkOn : Icons.checkOff)
                        color: checked ? Theme.fg : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }

                    IconImage {
                        visible: entry.modelData.icon !== ""
                        source: entry.modelData.icon
                        implicitSize: Theme.iconSize
                    }

                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr(entry.modelData.text.replace(/_(?!_)/g, "").replace(/__/g, "_"))
                        elide: Text.ElideRight
                        color: entry.modelData.enabled ? Theme.fg : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }

                    Text {
                        visible: entry.modelData.hasChildren
                        text: entry.expanded ? "⌄" : "›"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: entry.modelData.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (entry.modelData.hasChildren) {
                            entry.expanded = !entry.expanded;
                        } else {
                            entry.modelData.triggered();
                            root.close();
                        }
                    }
                }
            }

            Loader {
                active: entry.expanded
                visible: active
                Layout.fillWidth: true
                Layout.leftMargin: 12
                source: "TrayMenu.qml"
                onLoaded: {
                    item.menu = entry.modelData;
                    item.depth = root.depth + 1;
                    item.close.connect(root.close);
                }
            }
        }
    }
}
