import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.services

// меню под баром: отдельная карточка с тенью; клик мимо или Esc закрывают его
PanelWindow {
    id: root

    property bool open: false
    property real anchorX: 0  // центр карточки по X
    // имя слоя для правил niri (например, скрыть меню телефона с демонстрации экрана)
    property string layerName: "quickshell-popup"
    default property alias content: body.data
    signal dismissed

    property bool shown: false
    visible: shown

    onOpenChanged: {
        if (open) {
            hideTimer.stop();
            shown = true;
        } else {
            hideTimer.restart();
        }
    }

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    color: "transparent"

    // размытие только под карточкой, а не под всем прозрачным окном
    BackgroundEffect.blurRegion: Theme.blurOn ? cardRegion : null
    Region {
        id: cardRegion
        item: card
        radius: card.radius
    }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: root.layerName
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Timer {
        id: hideTimer
        interval: Theme.animSlow
        onTriggered: root.shown = false
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.dismissed()
    }

    Item {
        id: holder

        x: Math.max(10, Math.min(root.anchorX - width / 2, root.width - width - 10))
        y: 8
        width: card.width
        height: card.height

        RectangularShadow {
            anchors.fill: card
            radius: card.radius
            blur: 32
            offset.y: 10
            color: "#70000000"
            opacity: card.opacity
            y: card.y
        }

        Rectangle {
            id: card

            width: body.implicitWidth + 2 * Theme.popupPadding
            height: body.implicitHeight + 2 * Theme.popupPadding
            radius: 18
            color: Theme.panel
            border.width: 1
            border.color: Theme.surfaceHi2

            y: root.open ? 0 : -12
            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.97
            transformOrigin: Item.Top

            Behavior on y { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }
            Behavior on scale { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            // не пропускаем клики к фону
            MouseArea { anchors.fill: parent }

            Item {
                id: body
                x: Theme.popupPadding
                y: Theme.popupPadding
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
                focus: true
                Keys.onEscapePressed: root.dismissed()
            }
        }
    }
}
