import QtQuick
import QtQuick.Effects
import qs.services

// один монитор: обои, бар сверху, на главном — карточка входа
Item {
    id: root

    property bool main: false
    property bool ready: false
    Component.onCompleted: ready = true

    // обои (подготовлены под тему: размытые или как есть)
    Rectangle {
        anchors.fill: parent
        color: G.bg
    }
    Image {
        id: wall
        anchors.fill: parent
        source: G.background
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 500 } }
    }
    // лёгкое затемнение — карточке и бару нужен контраст на любых обоях
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.30) }
            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, root.main ? 0.18 : 0.30) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.40) }
        }
    }

    TopBar {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        main: root.main
    }

    LoginCard {
        visible: root.main
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -parent.height * 0.03
    }

    // подсказка внизу
    Text {
        visible: root.main
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        text: G.users.length > 1 ? G.tr("Enter — sign in   ·   ↑ ↓ — user", "Enter — войти   ·   ↑ ↓ — пользователь")
                                 : G.tr("Enter — sign in", "Enter — войти")
        color: Qt.rgba(1, 1, 1, 0.45)
        font.family: G.font
        font.pixelSize: G.fontSize - 2
    }

    // появление из чёрного и уход в чёрный при входе
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: !root.ready || G.leaving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.InOutQuad } }
    }
}
