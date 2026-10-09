import QtQuick
import Quickshell
import Quickshell.Io

// фоновая часть (удали "service" из plugin.json, если не нужна)
Scope {
    property var plugin

    IpcHandler {
        target: "__ID__"
        function run(): void { plugin.notify("__NAME__", "IPC works"); }
    }
}
