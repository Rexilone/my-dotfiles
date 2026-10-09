pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// обновления pacman (checkupdates из pacman-contrib); проверка раз в 30 минут, только если модуль включён
Singleton {
    id: root

    property bool installed: false
    property int count: 0
    property var list: []
    property bool checking: false
    readonly property bool wanted: Settings.moduleOn("updates", false)

    function refresh() {
        if (!installed) return;
        checking = true;
        run.running = true;
    }

    function upgrade() {
        Quickshell.execDetached(["foot", "-T", "System update", "sh", "-c",
            "sudo pacman -Syu; echo; read -p 'Done. Press Enter to close…' _"]);
        after.restart();
    }

    function install() {
        Quickshell.execDetached(["pkexec", "pacman", "-S", "--needed", "--noconfirm", "pacman-contrib"]);
        after.restart();
    }

    Process {
        id: has
        running: true
        command: ["sh", "-c", "command -v checkupdates"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.installed = text.trim() !== "";
                if (root.installed && root.wanted) root.refresh();
            }
        }
    }

    Process {
        id: run
        command: ["checkupdates"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.list = text.split("\n").filter(l => l.trim());
                root.count = root.list.length;
                root.checking = false;
            }
        }
        onExited: root.checking = false
    }

    Timer {
        interval: 30 * 60 * 1000
        running: root.wanted && root.installed
        repeat: true
        onTriggered: root.refresh()
    }

    // после установки/обновления проверить заново
    Timer {
        id: after
        interval: 20000
        onTriggered: has.running = true
    }

    onWantedChanged: if (wanted) has.running = true
}
