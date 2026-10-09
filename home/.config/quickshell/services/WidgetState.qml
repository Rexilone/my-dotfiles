pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// режим редактирования виджетов рабочего стола
Singleton {
    id: root

    property bool editing: false

    IpcHandler {
        target: "widgets"

        // qs ipc call widgets edit
        function edit(): void { root.editing = !root.editing; }
    }
}
