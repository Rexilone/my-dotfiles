import QtQuick
import QtQuick.Layouts
import qs.services

// комбинации клавиш проводника (Ctrl+? или главное меню)
Dialog {
    id: sc

    required property var br

    title: I18n.tr("Keyboard Shortcuts")
    maxWidth: 760
    onClosed: br.showShortcuts = false

    readonly property var groups: [
        ["Windows", [["Ctrl+N", "New Window"], ["Ctrl+W", "Close Window"], ["Ctrl+Q", "Close All Windows"], ["Ctrl+,", "Preferences"]]],
        ["Navigation", [["Alt+←", "Back"], ["Alt+→", "Forward"], ["Alt+↑   Backspace", "Parent Folder"], ["Alt+Home", "Home Folder"],
                        ["Ctrl+L", "Enter Location"], ["Ctrl+F", "Search"], ["Ctrl+D", "Bookmark This Location"]]],
        ["View", [["Ctrl+1", "Grid View"], ["Ctrl+2", "List View"], ["Ctrl++   Ctrl+−   Ctrl+0", "Zoom In, Out, Reset"],
                  ["Ctrl+H", "Show Hidden Files"], ["F9", "Sidebar"], ["F5", "Reload"]]],
        ["Files", [["Space", "Preview"], ["Enter", "Open"], ["F2", "Rename"], ["Ctrl+C   Ctrl+X   Ctrl+V", "Copy, Cut, Paste"],
                   ["Ctrl+A", "Select All"], ["Ctrl+Shift+N", "New Folder"], ["Delete", "Move to Trash"],
                   ["Shift+Delete", "Delete Permanently"], ["Ctrl+I   Alt+Enter", "Properties"]]],
    ]

    GridLayout {
        Layout.fillWidth: true
        columns: width > 620 ? 2 : 1
        columnSpacing: 20
        rowSpacing: 22

        Repeater {
            model: sc.groups
            PrefGroup {
                id: grp
                required property var modelData
                Layout.alignment: Qt.AlignTop
                title: I18n.tr(modelData[0])
                Repeater {
                    model: grp.modelData[1]
                    Item {
                        id: line
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 42
                        Rectangle {
                            visible: line.index > 0
                            width: parent.width
                            height: 1
                            color: FStyle.sep
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr(line.modelData[1])
                            color: Theme.fg
                            font.family: FStyle.ui
                            font.pixelSize: FStyle.fs
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: line.modelData[0]
                            color: Theme.dim
                            font.family: FStyle.ui
                            font.pixelSize: FStyle.fsSmall
                        }
                    }
                }
            }
        }
    }
}
