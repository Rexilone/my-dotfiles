import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Экран входа Rexilone Shell: greetd → niri → этот Quickshell.
// На главном мониторе — карточка входа, на остальных — обои и бар.
ShellRoot {
    id: shell

    readonly property string mainName: {
        const names = Quickshell.screens.map(s => s.name);
        if (G.t.primary && names.includes(G.t.primary)) return G.t.primary;
        const area = s => s.width * s.height;
        return Quickshell.screens.slice().sort((a, b) => area(b) - area(a))[0]?.name ?? "";
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property bool main: modelData.name === shell.mainName

            screen: modelData
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "black"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "rexilone-greeter"
            WlrLayershell.keyboardFocus: main ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Monitor {
                anchors.fill: parent
                main: win.main
            }
        }
    }
}
