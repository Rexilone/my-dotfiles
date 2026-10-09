import QtQuick
import Quickshell
import Quickshell.Io

// фоновая часть: работает, пока плагин включён
// попробуй: qs ipc call hello greet
Scope {
    property var plugin

    IpcHandler {
        target: "hello"

        function greet(): void {
            plugin.notify("Hello World", plugin.get("greeting", "Hi!"));
        }
    }
}
