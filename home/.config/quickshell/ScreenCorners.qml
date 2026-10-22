import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.services

// скруглённые углы экрана (как в AngelOS): чёрные уголки поверх всего, клики проходят насквозь
Variants {
    model: Settings.screenCorners.enabled ? Quickshell.screens : []

    Scope {
        id: scr
        required property ShellScreen modelData
        readonly property int r: Settings.screenCorners.radius ?? 18

        Variants {
            model: [[true, true], [true, false], [false, true], [false, false]]   // [сверху, слева]

            PanelWindow {
                id: corner
                required property var modelData
                readonly property bool top: modelData[0]
                readonly property bool left: modelData[1]

                screen: scr.modelData
                anchors.top: top
                anchors.bottom: !top
                anchors.left: left
                anchors.right: !left
                implicitWidth: scr.r
                implicitHeight: scr.r
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                mask: Region {}
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-corners"

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    // уголок: квадрат минус четверть круга с центром во внутренней вершине
                    transform: Scale {
                        origin.x: scr.r / 2
                        origin.y: scr.r / 2
                        xScale: corner.left ? 1 : -1
                        yScale: corner.top ? 1 : -1
                    }

                    ShapePath {
                        fillColor: "black"
                        strokeWidth: -1
                        startX: 0
                        startY: 0
                        PathLine { x: scr.r; y: 0 }
                        PathArc { x: 0; y: scr.r; radiusX: scr.r; radiusY: scr.r; direction: PathArc.Counterclockwise }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
        }
    }
}
