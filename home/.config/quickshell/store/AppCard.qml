import QtQuick
import QtQuick.Layouts
import qs.services
import qs.settings

// карточка приложения в сетке: значок, название, описание, кнопка
Rectangle {
    id: card

    property string pkg: ""
    property string name: Store.displayName(pkg)
    property string summary: Store.byPkg[pkg]?.summary ?? ""
    property bool aur: false
    signal open(string pkg, bool aur)

    implicitHeight: 92
    radius: 12
    color: area.containsMouse ? Theme.surfaceHi : Theme.surface

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.open(card.pkg, card.aur)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 14

        StoreIcon {
            pkg: card.pkg
            size: 52
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: card.name
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                Rectangle {
                    visible: card.aur
                    implicitWidth: aurTag.implicitWidth + 10
                    implicitHeight: 16
                    radius: 5
                    color: Theme.surfaceHi2
                    Text {
                        id: aurTag
                        anchors.centerIn: parent
                        text: "AUR"
                        color: Theme.warn
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 5
                        font.bold: true
                    }
                }
                Text {
                    visible: Store.isInstalled(card.pkg)
                    text: String.fromCodePoint(Store.hasUpdate(card.pkg) ? 0xF06B0 : 0xF012C)
                    color: Store.hasUpdate(card.pkg) ? Theme.warn : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize - 2
                }
            }
            Text {
                Layout.fillWidth: true
                text: card.summary
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }
}
