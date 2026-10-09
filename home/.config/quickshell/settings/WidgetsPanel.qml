import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// Виджеты рабочего стола: что показывать, где, как выглядит
ColumnLayout {
    id: page
    Layout.fillWidth: true
    spacing: 6

    property var fonts: []

    readonly property var defs: [
        { id: "clock", icon: 0xF0954, name: "Clock", desc: "Big time and date" },
        { id: "perf", icon: 0xF061A, name: "Performance", desc: "CPU, GPU and RAM rings" },
        { id: "weather", icon: 0xF0595, name: "Weather", desc: "Now and next 3 days" },
        { id: "media", icon: 0xF075A, name: "Media", desc: "What's playing, with controls" },
        { id: "calendar", icon: 0xF00ED, name: "Calendar", desc: "Month view with notes" },
        { id: "notes", icon: 0xF0D2F, name: "Today's notes", desc: "Notes and reminders for today" },
        { id: "quote", icon: 0xF0757, name: "Quote of the day", desc: "Changes daily, click for next" },
    ]

    Component.onCompleted: fontList.running = true

    Process {
        id: fontList
        command: ["sh", "-c", "fc-list : family | cut -d, -f1 | sort -uf"]
        stdout: StdioCollector {
            onStreamFinished: page.fonts = text.split("\n").map(x => x.trim()).filter(x => x && !x.startsWith("."))
        }
    }

    SCard {
        icon: String.fromCodePoint(0xF0B92)
        title: WidgetState.editing ? "Editing — drag widgets on the desktop" : "Arrange widgets"
        desc: "Widgets float above windows while editing. Press Done to lock them in place."

        SButton {
            text: WidgetState.editing ? "Done" : "Edit layout"
            primary: true
            onClicked: WidgetState.editing = !WidgetState.editing
        }
    }

    Repeater {
        model: page.defs

        ColumnLayout {
            id: wd
            required property var modelData
            readonly property var cfg: Settings.widgets[modelData.id] ?? {}
            readonly property bool on: cfg.enabled ?? false

            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 3

            SCard {
                icon: String.fromCodePoint(wd.modelData.icon)
                title: wd.modelData.name
                desc: wd.modelData.desc

                SSwitch {
                    checked: wd.on
                    onToggled: v => Settings.setWidget(wd.modelData.id, "enabled", v)
                }
            }

            SCard {
                visible: wd.on
                title: "Monitor"

                SDropdown {
                    minWidth: 170
                    options: Quickshell.screens.map(s => ({ value: s.name, label: s.name }))
                    current: wd.cfg.screen ?? Settings.primary
                    onPicked: v => Settings.setWidget(wd.modelData.id, "screen", v)
                }
            }

            SCard {
                visible: wd.on
                title: "Background"
                desc: "Card behind the widget, or just content over the wallpaper"

                SSwitch {
                    checked: wd.cfg.background ?? true
                    onToggled: v => Settings.setWidget(wd.modelData.id, "background", v)
                }
            }

            SCard {
                visible: wd.on
                title: "Size"

                SChoice {
                    options: [0.75, 1, 1.25, 1.5].map(v => ({ value: v, label: { 0.75: "S", 1: "M", 1.25: "L", 1.5: "XL" }[v] }))
                    current: wd.cfg.size ?? 1
                    onPicked: v => Settings.setWidget(wd.modelData.id, "size", v)
                }
            }

            // только часы
            SCard {
                visible: wd.on && wd.modelData.id === "clock"
                title: "Font"

                SDropdown {
                    minWidth: 240
                    fontPreview: true
                    options: [{ value: "", label: "Same as interface" }].concat(page.fonts.map(f => ({ value: f, label: f })))
                    current: wd.cfg.font ?? ""
                    onPicked: v => Settings.setWidget("clock", "font", v)
                }
            }

            SCard {
                visible: wd.on && wd.modelData.id === "clock"
                title: "Format"

                SChoice {
                    options: [
                        { value: "HH:mm", label: "15:00" },
                        { value: "HH:mm:ss", label: "15:00:42" },
                        { value: "h:mm AP", label: "3:00 PM" },
                    ]
                    current: wd.cfg.format ?? "HH:mm"
                    onPicked: v => Settings.setWidget("clock", "format", v)
                }
            }

            SCard {
                visible: wd.on && wd.modelData.id === "clock"
                title: "Show date"

                SSwitch {
                    checked: wd.cfg.showDate ?? true
                    onToggled: v => Settings.setWidget("clock", "showDate", v)
                }
            }
        }
    }

    // ── виджеты телефона (Rexlink): сколько угодно, под любое устройство
    SSection { text: I18n.tr("Phone widgets") }

    readonly property var phoneVariants: [
        { value: "full", label: "Everything" },
        { value: "battery", label: "Battery" },
        { value: "status", label: "Status & signal" },
        { value: "notifications", label: "Notifications" },
        { value: "media", label: "Media" },
        { value: "actions", label: "Quick actions" },
    ]
    readonly property var phoneDevices: [{ value: "", label: "Current device" }]
        .concat(Rexlink.devices.map(d => ({ value: d.id, label: `${d.name}${d.online ? "" : "  (offline)"}` })))

    property string newVariant: "full"
    property string newDevice: ""

    SCard {
        visible: !Rexlink.connected
        icon: String.fromCodePoint(0xF011C)
        title: "Rexlink isn't running"
        desc: "Phone widgets show data from Rexlink — start it in Settings → Phone"
    }

    SCard {
        icon: "+"
        title: "Add a phone widget"
        desc: "One per device and kind — e.g. tablet battery next to phone notifications"

        SDropdown {
            minWidth: 170
            options: page.phoneVariants
            current: page.newVariant
            onPicked: v => page.newVariant = v
        }
        SDropdown {
            minWidth: 170
            options: page.phoneDevices
            current: page.newDevice
            onPicked: v => page.newDevice = v
        }
        SButton {
            text: I18n.tr("Add")
            primary: true
            onClicked: Settings.addPhoneWidget(page.newDevice, page.newVariant)
        }
    }

    Repeater {
        model: Settings.phoneWidgetIds

        ColumnLayout {
            id: pw
            required property string modelData
            readonly property var cfg: Settings.widgets[modelData] ?? {}
            readonly property var dev: Rexlink.devFor(cfg.device)

            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 3

            SCard {
                icon: Rexlink.kindIcon(pw.dev?.kind)
                title: `${(page.phoneVariants.find(v => v.value === pw.cfg.variant) ?? page.phoneVariants[0]).label}  ·  ${pw.cfg.device ? (pw.dev?.name ?? "unknown device") : "current device"}`
                desc: pw.cfg.enabled ? `On ${pw.cfg.screen ?? Settings.primary}` : "Hidden"

                SButton {
                    icon: Icons.trash
                    danger: true
                    onClicked: Settings.removeWidget(pw.modelData)
                }
                SSwitch {
                    checked: pw.cfg.enabled ?? true
                    onToggled: v => Settings.setWidget(pw.modelData, "enabled", v)
                }
            }

            SCard {
                title: "Kind"
                SDropdown {
                    minWidth: 190
                    options: page.phoneVariants
                    current: pw.cfg.variant ?? "full"
                    onPicked: v => Settings.setWidget(pw.modelData, "variant", v)
                }
            }

            SCard {
                title: "Device"
                SDropdown {
                    minWidth: 190
                    options: page.phoneDevices
                    current: pw.cfg.device ?? ""
                    onPicked: v => Settings.setWidget(pw.modelData, "device", v)
                }
            }

            SCard {
                title: "Monitor"
                SDropdown {
                    minWidth: 170
                    options: Quickshell.screens.map(s => ({ value: s.name, label: s.name }))
                    current: pw.cfg.screen ?? Settings.primary
                    onPicked: v => Settings.setWidget(pw.modelData, "screen", v)
                }
            }

            SCard {
                title: "Background"
                SSwitch {
                    checked: pw.cfg.background ?? true
                    onToggled: v => Settings.setWidget(pw.modelData, "background", v)
                }
            }

            SCard {
                title: "Size"
                SChoice {
                    options: [0.75, 1, 1.25, 1.5].map(v => ({ value: v, label: { 0.75: "S", 1: "M", 1.25: "L", 1.5: "XL" }[v] }))
                    current: pw.cfg.size ?? 1
                    onPicked: v => Settings.setWidget(pw.modelData, "size", v)
                }
            }
        }
    }
}
