import QtQuick
import QtQuick.Layouts
import qs.services

// диалог Adwaita поверх окна проводника: затемнение, карточка с заголовком и кнопкой закрытия, прокрутка.
// Содержимое — в content; закрытие — сигнал closed (щелчок мимо, кнопка, Esc обрабатывает Browser)
Item {
    id: dl

    property string title: ""
    property int maxWidth: 620
    default property alias content: body.data
    signal closed

    Rectangle {
        anchors.fill: parent
        color: FStyle.shade
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: dl.closed()
            onWheel: wheel => wheel.accepted = true
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, dl.maxWidth)
        height: Math.min(parent.height - 40, body.implicitHeight + head.height + 28)
        radius: 14
        color: FStyle.card
        border.width: 1
        border.color: FStyle.sep
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        Item {
            id: head
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 52
            Text {
                anchors.centerIn: parent
                text: dl.title
                color: Theme.fg
                font.family: FStyle.ui
                font.pixelSize: FStyle.fs + 1
                font.weight: Font.Bold
            }
            FButton {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                circular: true
                implicitWidth: 26
                implicitHeight: 26
                flat: false
                glyph: 0xF0156
                glyphSize: FStyle.icon - 3
                onClicked: dl.closed()
            }
        }

        Flickable {
            anchors.top: head.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.bottomMargin: 20
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: body
                width: parent.width
                spacing: 22
            }
        }
    }
}
