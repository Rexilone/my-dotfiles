import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.settings

// Принтеры и сканеры: CUPS + SANE (вкладка в Настройки → Peripherals)
ColumnLayout {
    id: page

    property bool active: false   // опрашивать, пока вкладка открыта

    Layout.fillWidth: true
    spacing: 6

    property var printers: []      // [{ name, state, device, isDefault }]
    property var jobs: []          // [{ id, printer, user, size }]
    property var scanners: []      // [{ device, name }]
    property bool hasSane: false
    property bool hasSimpleScan: false
    property bool loading: true

    function refresh() {
        loading = true;
        scan.running = true;
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 4000
        running: page.active
        repeat: true
        onTriggered: if (!scan.running) scan.running = true
    }

    Process {
        id: scan
        command: ["sh", "-c", `
            echo '@default'; lpstat -d 2>/dev/null
            echo '@printers'; LANG=C lpstat -p 2>/dev/null
            echo '@devices'; LANG=C lpstat -v 2>/dev/null
            echo '@jobs'; LANG=C lpstat -o 2>/dev/null
            echo '@sane'; command -v scanimage >/dev/null && echo yes
            echo '@simplescan'; command -v simple-scan >/dev/null && echo yes
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const sec = {};
                let cur = "";
                for (const l of text.split("\n")) {
                    if (l.startsWith("@")) { cur = l.slice(1); sec[cur] = []; }
                    else if (cur && l.trim()) sec[cur].push(l);
                }
                const def = ((sec.default ?? [])[0] ?? "").split(": ")[1]?.trim() ?? "";
                const devices = {};
                for (const l of sec.devices ?? []) {
                    const m = l.match(/^device for (\S+): (.+)$/);
                    if (m) devices[m[1]] = m[2];
                }
                page.printers = (sec.printers ?? []).map(l => {
                    const m = l.match(/^printer (\S+) (?:is )?(idle|now printing|disabled)?/);
                    return m ? { name: m[1], state: m[2] ?? "unknown", device: devices[m[1]] ?? "", isDefault: m[1] === def } : null;
                }).filter(x => x);
                page.jobs = (sec.jobs ?? []).map(l => {
                    const m = l.match(/^(\S+)-(\d+)\s+(\S+)\s+(\d+)/);
                    return m ? { id: `${m[1]}-${m[2]}`, printer: m[1], user: m[3], size: m[4] } : null;
                }).filter(x => x);
                page.hasSane = (sec.sane ?? []).length > 0;
                page.hasSimpleScan = (sec.simplescan ?? []).length > 0;
                page.loading = false;
                if (page.hasSane && !scannerScan.running && page.scanners.length === 0) scannerScan.running = true;
            }
        }
    }

    Process {
        id: scannerScan
        command: ["sh", "-c", "scanimage -f '%d|%v %m%n' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: page.scanners = text.split("\n").filter(l => l.includes("|")).map(l => {
                const [device, name] = l.split("|");
                return { device, name };
            })
        }
    }

    function run(cmd) {
        Quickshell.execDetached(cmd);
        refreshLater.restart();
    }

    Timer {
        id: refreshLater
        interval: 1200
        onTriggered: page.refresh()
    }

    // ── принтеры
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        SSection {
            Layout.fillWidth: true
            text: I18n.tr("Printers")
        }
        SButton {
            Layout.topMargin: 12
            text: I18n.tr("Add a printer")
            icon: "+"
            primary: true
            onClicked: page.run(["system-config-printer"])
        }
    }

    SCard {
        visible: !page.loading && page.printers.length === 0
        icon: String.fromCodePoint(0xF042A)
        title: "No printers yet"
        desc: "Connect a printer by USB or network and press «Add a printer»"
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: page.printers

            SCard {
                id: pr
                required property var modelData

                icon: String.fromCodePoint(0xF042A)
                title: modelData.name + (modelData.isDefault ? "   ·   default" : "")
                desc: `${modelData.state}   ·   ${modelData.device}`

                SButton {
                    visible: !pr.modelData.isDefault
                    text: I18n.tr("Set default")
                    onClicked: page.run(["lpoptions", "-d", pr.modelData.name])
                }
                SButton {
                    text: I18n.tr("Test page")
                    onClicked: page.run(["lp", "-d", pr.modelData.name, "/usr/share/cups/data/testprint"])
                }
                SButton {
                    icon: Icons.trash
                    danger: true
                    onClicked: page.run(["pkexec", "lpadmin", "-x", pr.modelData.name])
                }
            }
        }
    }

    // ── очередь
    SSection {
        visible: page.jobs.length > 0
        text: I18n.tr("Print queue")
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: page.jobs

            SCard {
                id: job
                required property var modelData
                icon: String.fromCodePoint(0xF0B2B)
                title: `Job ${modelData.id}`
                desc: `${modelData.printer} · ${modelData.user} · ${Math.round(modelData.size / 1024)} KB`

                SButton {
                    text: I18n.tr("Cancel")
                    danger: true
                    onClicked: page.run(["cancel", job.modelData.id])
                }
            }
        }
    }

    // ── сканеры
    SSection { text: I18n.tr("Scanners") }

    SCard {
        visible: !page.hasSane
        icon: String.fromCodePoint(0xF06AB)
        title: "Scanner support is not installed"
        desc: "Installs SANE drivers and the Document Scanner app (needs your password)"

        SButton {
            text: I18n.tr("Install")
            primary: true
            onClicked: page.run(["pkexec", "pacman", "-S", "--needed", "--noconfirm", "sane", "simple-scan"])
        }
    }

    SCard {
        visible: page.hasSane && page.scanners.length === 0
        icon: String.fromCodePoint(0xF06AB)
        title: scannerScan.running ? "Looking for scanners…" : "No scanners found"
        desc: "Make sure the scanner is on and connected"

        SButton {
            text: I18n.tr("Search again")
            enabled: !scannerScan.running
            onClicked: scannerScan.running = true
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: page.scanners

            SCard {
                id: sc
                required property var modelData
                icon: String.fromCodePoint(0xF06AB)
                title: modelData.name
                desc: modelData.device

                SButton {
                    text: I18n.tr("Scan")
                    primary: true
                    onClicked: page.run(page.hasSimpleScan ? ["simple-scan"] : ["sh", "-c", `scanimage -d '${sc.modelData.device.replace(/'/g, "")}' --format=png -o "$HOME/Документы/scan-$(date +%F_%H-%M-%S).png"`])
                }
            }
        }
    }

    SCard {
        Layout.topMargin: 10
        icon: String.fromCodePoint(0xF059F)
        title: "CUPS web interface"
        desc: "Advanced printer options at localhost:631"
        clickable: true
        onClicked: Qt.openUrlExternally("http://localhost:631")
    }
}
