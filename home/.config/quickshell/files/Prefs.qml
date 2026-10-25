import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// параметры проводника (Ctrl+, или главное меню), как в Nautilus: общие, миниатюры, быстрый просмотр,
// флешки и диски, проводник по умолчанию. Хранятся в Settings.files
Dialog {
    id: pf

    required property var br
    readonly property var f: br.cfg
    property string defaultApp: ""
    readonly property bool isDefault: defaultApp === "rexilone-files.desktop"

    title: I18n.tr("Preferences")
    onClosed: br.showPrefs = false
    onVisibleChanged: if (visible) query.running = true

    Process {
        id: query
        command: ["xdg-mime", "query", "default", "inode/directory"]
        stdout: StdioCollector { onStreamFinished: pf.defaultApp = text.trim() }
    }
    Process {
        id: setDefault
        command: ["xdg-mime", "default", "rexilone-files.desktop", "inode/directory"]
        onExited: query.running = true
    }

    readonly property string thumbMode: !(f.thumbs ?? true) ? "never" : (f.remoteThumbs ?? false) ? "all" : "local"
    readonly property var thumbModes: [
        { value: "all", label: I18n.tr("All Files") },
        { value: "local", label: I18n.tr("On This Computer Only") },
        { value: "never", label: I18n.tr("Never") },
    ]
    function setThumbs(v) {
        Settings.setFiles("thumbs", v !== "never");
        Settings.setFiles("remoteThumbs", v === "all");
    }

    PrefGroup {
        title: I18n.tr("General")
        PrefRow {
            sep: false
            title: I18n.tr("Sort Folders Before Files")
            switchable: true
            checked: pf.f.dirsFirst ?? true
            onToggled: v => Settings.setFiles("dirsFirst", v)
        }
        PrefRow {
            title: I18n.tr("Show Hidden Files")
            subtitle: "Ctrl+H"
            switchable: true
            checked: pf.f.hidden ?? false
            onToggled: v => Settings.setFiles("hidden", v)
        }
        PrefRow {
            title: I18n.tr("Open Items With a Single Click")
            subtitle: I18n.tr("Otherwise — with a double click")
            switchable: true
            checked: pf.f.singleClick ?? false
            onToggled: v => Settings.setFiles("singleClick", v)
        }
        PrefRow {
            title: I18n.tr("Sidebar")
            subtitle: "F9"
            switchable: true
            checked: pf.f.sidebar ?? true
            onToggled: v => Settings.setFiles("sidebar", v)
        }
    }

    PrefGroup {
        title: I18n.tr("Performance")
        PrefRow {
            id: thumbRow
            sep: false
            title: I18n.tr("Show Thumbnails")
            subtitle: I18n.tr("Pictures, video frames and the first page of PDFs. On the phone they are downloaded over Wi-Fi — slower")
            FButton {
                id: thumbBtn
                flat: false
                text: (pf.thumbModes.find(m => m.value === pf.thumbMode) ?? pf.thumbModes[1]).label + "  ▾"
                onClicked: {
                    const p = thumbBtn.mapToItem(pf.br, thumbBtn.width, thumbBtn.height + 4);
                    pf.br.popupMenu(p.x, p.y, pf.thumbModes.map(m => ({ text: m.label, check: m.value === pf.thumbMode, act: () => pf.setThumbs(m.value) })), true);
                }
            }
        }
    }

    PrefGroup {
        title: I18n.tr("Quick Preview")
        PrefRow {
            sep: false
            title: I18n.tr("Play video and music in the preview")
            subtitle: I18n.tr("Space on a file")
            switchable: true
            checked: pf.f.previewPlay ?? true
            onToggled: v => Settings.setFiles("previewPlay", v)
        }
        PrefRow {
            visible: pf.f.previewPlay ?? true
            title: I18n.tr("Start without sound")
            switchable: true
            checked: pf.f.previewMuted ?? false
            onToggled: v => Settings.setFiles("previewMuted", v)
        }
        PrefRow {
            visible: pf.f.previewPlay ?? true
            title: I18n.tr("Loop")
            switchable: true
            checked: pf.f.previewLoop ?? true
            onToggled: v => Settings.setFiles("previewLoop", v)
        }
    }

    PrefGroup {
        title: I18n.tr("Flash Drives and Disks")
        PrefRow {
            sep: false
            title: I18n.tr("Connect flash drives by themselves")
            subtitle: I18n.tr("As soon as one is plugged in")
            switchable: true
            checked: pf.f.automount ?? true
            onToggled: v => Settings.setFiles("automount", v)
        }
        PrefRow {
            title: I18n.tr("Notify about flash drives")
            subtitle: I18n.tr("With an «Open» button")
            switchable: true
            checked: pf.f.driveNotify ?? true
            onToggled: v => Settings.setFiles("driveNotify", v)
        }
    }

    PrefGroup {
        title: I18n.tr("Default File Manager")
        PrefRow {
            sep: false
            title: I18n.tr("Open folders from other apps here")
            subtitle: pf.isDefault ? I18n.tr("Folders from other apps open here")
                : `${I18n.tr("Now")}: ${pf.defaultApp.replace(/\.desktop$/, "") || "—"}`
            FButton {
                visible: !pf.isDefault
                suggested: true
                text: I18n.tr("Make default")
                onClicked: setDefault.running = true
            }
            Text {
                visible: pf.isDefault
                text: String.fromCodePoint(0xF012C)
                color: Theme.accent
                font.family: FStyle.glyphs
                font.pixelSize: FStyle.icon + 4
            }
        }
    }
}
