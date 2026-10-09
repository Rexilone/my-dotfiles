import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.services

// карточка уведомления: иконка, приложение · время, заголовок, текст, действия
Rectangle {
    id: root

    required property Notification notif
    property bool bordered: false
    signal closeRequested
    readonly property bool containsMouse: area.containsMouse

    readonly property var defaultAction: notif?.actions.find(a => a.identifier === "default") ?? null
    readonly property var buttons: notif?.actions.filter(a => a.identifier !== "default") ?? []

    implicitWidth: 360
    implicitHeight: content.implicitHeight + 24
    radius: Theme.radius
    color: area.containsMouse ? Theme.surfaceHi : Theme.panel
    border.width: bordered ? 1 : 0
    border.color: notif?.urgency === NotificationUrgency.Critical ? Theme.urgent : Theme.faint

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton && root.defaultAction) root.defaultAction.invoke();
            root.closeRequested();
        }
    }

    RowLayout {
        id: content
        x: 12
        y: 12
        width: parent.width - 24
        spacing: 12

        IconImage {
            Layout.alignment: Qt.AlignTop
            readonly property string path: root.notif ? Notifs.iconFor(root.notif) : ""
            visible: path !== ""
            source: path
            implicitSize: 36
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: I18n.tr([root.notif?.appName, root.notif ? Notifs.timeAgo(root.notif) : ""].filter(s => s).join(" · "))
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }

                BarText {
                    text: Icons.close
                    font.pixelSize: Theme.fontSize
                    active: false
                    onClicked: root.closeRequested()
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.notif?.summary ?? ""
                visible: text !== ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                text: root.notif?.body ?? ""
                visible: text !== ""
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: 5
                elide: Text.ElideRight
                color: Theme.fg
                opacity: 0.8
                linkColor: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.buttons.length > 0
                spacing: 6

                Repeater {
                    model: root.buttons

                    Rectangle {
                        required property NotificationAction modelData

                        width: label.implicitWidth + 20
                        height: 24
                        radius: 6
                        color: btn.containsMouse ? Theme.faint : Theme.surfaceHi

                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: parent.modelData.text
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }

                        MouseArea {
                            id: btn
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.modelData.invoke()
                        }
                    }
                }
            }
        }
    }
}
