import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// живые обои-анимация: шейдер в цветах темы на слое фона каждого монитора (services/LiveWallpaper.qml)
Variants {
    model: LiveWallpaper.shader ? Quickshell.screens : []

    PanelWindow {
        id: win

        required property ShellScreen modelData
        screen: modelData

        readonly property bool paused: LiveWallpaper.pausedOn(modelData.name)
        readonly property int fps: LiveWallpaper.cfg.fps ?? 30
        property real time: 0

        color: Theme.bg
        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell-wallpaper"

        // время идёт только без паузы: кадр замирает, видеокарта отдыхает
        Timer {
            running: !win.paused
            interval: Math.round(1000 / Math.max(5, win.fps))
            repeat: true
            onTriggered: win.time += interval / 1000 * (LiveWallpaper.cfg.speed ?? 1)
        }

        ShaderEffect {
            anchors.fill: parent
            readonly property string name: LiveWallpaper.cfg.shader ?? "aurora"
            fragmentShader: Qt.resolvedUrl(`shaders/${name}.frag.qsb`)
            property real time: win.time
            property size res: Qt.size(width, height)
            property color bg: Theme.bg
            property color accent: Theme.accent
            property color surface: Theme.surface
            property color fg: Theme.fg
        }
    }
}
