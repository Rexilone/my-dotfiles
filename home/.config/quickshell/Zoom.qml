import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// Лупа (как «Масштаб» в KDE): Super+Shift+колесо вверх — приблизить, вниз — отдалить.
// Увеличенная область следует за мышью. В niri нет своего увеличения экрана, а живой
// снимок экрана захватил бы и саму лупу (бесконечное зеркало) — поэтому лупа показывает
// снимок экрана на момент приближения. Отдалить до конца, Esc или клик — выйти.
//
// На каждый монитор — своё окно и свой снимок, они создаются один раз и не удаляются:
// удаление снимка (в том числе смена монитора у одного общего) роняло Quickshell.
// Новый снимок — captureFrame(), пока лупа спрятана; показываем её, когда снимок пришёл.
Scope {
    id: ctl

    property real zoom: 1                 // цель
    readonly property real step: 1.25     // за щелчок колеса
    readonly property real maxZoom: 16
    property bool active: false           // лупа на экране
    property bool opening: false          // снимаем экран, лупа ещё спрятана
    property string screenName: ""        // на каком мониторе лупа
    property real pendingZoom: 0

    signal capture(string name)

    function zoomIn() {
        closeLater.stop();
        if (!active) {
            if (opening) return;
            zoom = 1;
            pendingZoom = step;
            opening = true;
            screenName = Settings.activeScreen()?.name ?? "";
            capture(screenName);          // снять экран, пока лупа спрятана
            showLater.restart();
            return;
        }
        zoom = Math.min(maxZoom, zoom * step);
    }
    function zoomOut() {
        if (!active) return;
        zoom = Math.max(1, zoom / step);
        if (zoom <= 1.01) reset();
    }
    function reset() {
        zoom = 1;
        pendingZoom = 0;
        closeLater.restart();
    }

    // снимок приходит за кадр-два — потом показываем и приближаем
    Timer {
        id: showLater
        interval: 120
        onTriggered: {
            ctl.opening = false;
            ctl.active = true;
            ctl.zoom = ctl.pendingZoom || ctl.step;
            ctl.pendingZoom = 0;
        }
    }

    // закрываем не сразу: анимация вернётся к 1, а прокрутка туда-обратно не дёргает окно
    Timer {
        id: closeLater
        interval: 450
        onTriggered: if (ctl.zoom <= 1.01) ctl.active = false
    }

    IpcHandler {
        target: "zoom"
        function zoomIn(): void { ctl.zoomIn(); }
        function zoomOut(): void { ctl.zoomOut(); }
        function reset(): void { ctl.reset(); }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            readonly property bool mine: ctl.active && ctl.screenName === modelData.name

            screen: modelData
            visible: mine
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-zoom"
            WlrLayershell.keyboardFocus: mine ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Connections {
                target: ctl
                function onCapture(name) { if (name === win.modelData.name) shot.captureFrame(); }
            }

            // плавный масштаб
            property real z: 1
            Behavior on z { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Binding { target: win; property: "z"; value: ctl.zoom; when: win.mine }

            // где мышь (окно на весь экран — позицию знаем); пока не двигали — центр
            property real mx: width / 2
            property real my: height / 2

            Item {
                anchors.fill: parent
                opacity: win.mine && shot.hasContent ? 1 : 0
                clip: true
                focus: true

                Keys.onEscapePressed: ctl.reset()

                // снимок этого монитора, увеличенный: точка под мышью у края экрана
                // показывает край (пропорционально, как в KDE)
                ScreencopyView {
                    id: shot
                    captureSource: win.modelData
                    live: false
                    paintCursor: false
                    width: win.width * win.z
                    height: win.height * win.z
                    x: win.mx * (1 - win.z)
                    y: win.my * (1 - win.z)
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.AllButtons
                    onPositionChanged: mouse => { win.mx = mouse.x; win.my = mouse.y; }
                    onClicked: ctl.reset()
                    onWheel: wheel => wheel.angleDelta.y > 0 ? ctl.zoomIn() : ctl.zoomOut()
                }

                // подпись: во сколько раз и как выйти
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 14
                    implicitWidth: hint.implicitWidth + 28
                    implicitHeight: 30
                    radius: 15
                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.8)
                    opacity: win.z > 1.05 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Text {
                        id: hint
                        anchors.centerIn: parent
                        text: `${String.fromCodePoint(0xF0349)}  ${Math.round(ctl.zoom * 100)}%   ·   ${I18n.tr("snapshot")}   ·   Super+Shift+${I18n.tr("wheel")}   ·   Esc`
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }
        }
    }
}
