import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// Файлы: проводник (Super+E) — вид, миниатюры, просмотр видео и музыки, диски и флешки, проводник по умолчанию
Page {
    id: page

    title: "Files"
    subtitle: "The file manager: view, previews, drives"

    readonly property var f: Settings.files ?? {}
    property string defaultApp: ""

    Component.onCompleted: query.running = true
    Process {
        id: query
        command: ["xdg-mime", "query", "default", "inode/directory"]
        stdout: StdioCollector { onStreamFinished: page.defaultApp = text.trim() }
    }
    Process {
        id: setDefault
        onExited: query.running = true
    }

    SCard {
        icon: String.fromCodePoint(0xF024B)
        title: "Open Files"
        desc: "Super+E"
        clickable: true
        onClicked: Quickshell.execDetached(["qs", "ipc", "call", "files", "open", ""])
    }
    SCard {
        icon: String.fromCodePoint(0xF0256)
        title: "Default file manager"
        desc: page.defaultApp === "rexilone-files.desktop" ? "Folders from other apps open here"
            : `${I18n.tr("Now")}: ${page.defaultApp.replace(/\.desktop$/, "") || "—"}`
        SChoice {
            options: [{ value: "rexilone-files.desktop", label: "RexOS" }, { value: "org.gnome.Nautilus.desktop", label: "Nautilus" }]
            current: page.defaultApp
            onPicked: v => {
                setDefault.command = ["xdg-mime", "default", v, "inode/directory"];
                setDefault.running = true;
            }
        }
    }

    SSection { text: I18n.tr("View") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF0570)
            title: "Layout"
            SChoice {
                options: [{ value: "grid", label: "Grid" }, { value: "list", label: "List" }]
                current: page.f.view ?? "grid"
                onPicked: v => Settings.setFiles("view", v)
            }
        }
        SCard {
            icon: String.fromCodePoint(0xF0415)
            title: "Icon size"
            SChoice {
                options: [0.75, 1, 1.25, 1.5, 2].map(v => ({ value: v, label: { 0.75: "S", 1: "M", 1.25: "L", 1.5: "XL", 2: "XXL" }[v] }))
                current: page.f.zoom ?? 1
                onPicked: v => Settings.setFiles("zoom", v)
            }
        }
        SCard {
            icon: String.fromCodePoint(0xF04BA)
            title: "Sort"
            SChoice {
                options: [{ value: "name", label: "Name" }, { value: "time", label: "Date" }, { value: "size", label: "Size" }, { value: "type", label: "Type" }]
                current: page.f.sort ?? "name"
                onPicked: v => Settings.setFiles("sort", v)
            }
        }
        SCard {
            title: "Reverse order"
            SSwitch { checked: page.f.reverse ?? false; onToggled: v => Settings.setFiles("reverse", v) }
        }
        SCard {
            title: "Folders first"
            SSwitch { checked: page.f.dirsFirst ?? true; onToggled: v => Settings.setFiles("dirsFirst", v) }
        }
        SCard {
            title: "Hidden files"
            desc: "Ctrl+H"
            SSwitch { checked: page.f.hidden ?? false; onToggled: v => Settings.setFiles("hidden", v) }
        }
        SCard {
            title: "Sidebar"
            SSwitch { checked: page.f.sidebar ?? true; onToggled: v => Settings.setFiles("sidebar", v) }
        }
    }

    SSection { text: I18n.tr("Previews") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF02E9)
            title: "Thumbnails"
            desc: "Pictures, video frames and the first page of PDFs instead of icons"
            SSwitch { checked: page.f.thumbs ?? true; onToggled: v => Settings.setFiles("thumbs", v) }
        }
        SCard {
            visible: page.f.thumbs ?? true
            icon: String.fromCodePoint(0xF011C)
            title: "Thumbnails on the phone"
            desc: "Downloads every picture over Wi-Fi — slower"
            SSwitch { checked: page.f.remoteThumbs ?? false; onToggled: v => Settings.setFiles("remoteThumbs", v) }
        }
        SCard {
            icon: String.fromCodePoint(0xF040A)
            title: "Play video and music in the preview"
            desc: "Space on a file"
            SSwitch { checked: page.f.previewPlay ?? true; onToggled: v => Settings.setFiles("previewPlay", v) }
        }
        SCard {
            visible: page.f.previewPlay ?? true
            icon: String.fromCodePoint(0xF0581)
            title: "Start without sound"
            SSwitch { checked: page.f.previewMuted ?? false; onToggled: v => Settings.setFiles("previewMuted", v) }
        }
        SCard {
            visible: page.f.previewPlay ?? true
            icon: String.fromCodePoint(0xF0456)
            title: "Loop"
            SSwitch { checked: page.f.previewLoop ?? true; onToggled: v => Settings.setFiles("previewLoop", v) }
        }
    }

    SSection { text: I18n.tr("Drives") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF129E)
            title: "Connect flash drives by themselves"
            desc: "As soon as one is plugged in"
            SSwitch { checked: page.f.automount ?? true; onToggled: v => Settings.setFiles("automount", v) }
        }
        SCard {
            icon: String.fromCodePoint(0xF009A)
            title: "Notify about flash drives"
            desc: "With an «Open» button"
            SSwitch { checked: page.f.driveNotify ?? true; onToggled: v => Settings.setFiles("driveNotify", v) }
        }

        Repeater {
            model: Drives.drives
            SCard {
                id: dc
                required property var modelData
                icon: String.fromCodePoint(modelData.removable ? 0xF129E : 0xF02CA)
                title: modelData.name
                desc: `${modelData.dev}   ·   ${modelData.fstype}   ·   ${modelData.sizeText}` + (modelData.mount ? `   ·   ${modelData.mount}` : "")
                SButton {
                    text: I18n.tr(dc.modelData.mount ? "Disconnect" : "Connect")
                    onClicked: dc.modelData.mount ? Drives.unmount(dc.modelData.dev) : Drives.mount(dc.modelData.dev, false)
                }
                SButton {
                    visible: dc.modelData.removable && !!dc.modelData.mount
                    text: I18n.tr("Eject")
                    onClicked: Drives.eject(dc.modelData)
                }
            }
        }
    }
}
