import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// Время и язык: часовой пояс, синхронизация, формат, первый день недели, язык системы
Page {
    id: page

    title: "Time & language"
    subtitle: "Time zone, clock format and system language"

    property var zones: []
    property string zone: ""
    property bool ntp: true
    property string locale: ""
    property var locales: []
    property bool busy: false

    readonly property bool is12h: /h:mm AP/.test(Settings.clockFormat)

    readonly property var knownLocales: [
        { value: "en_US.UTF-8", label: "English (United States)" },
        { value: "en_GB.UTF-8", label: "English (United Kingdom)" },
        { value: "ru_RU.UTF-8", label: "Русский" },
        { value: "uk_UA.UTF-8", label: "Українська" },
        { value: "be_BY.UTF-8", label: "Беларуская" },
        { value: "kk_KZ.UTF-8", label: "Қазақ" },
        { value: "de_DE.UTF-8", label: "Deutsch" },
        { value: "fr_FR.UTF-8", label: "Français" },
        { value: "es_ES.UTF-8", label: "Español" },
        { value: "pl_PL.UTF-8", label: "Polski" },
        { value: "ja_JP.UTF-8", label: "日本語" },
    ]

    function labelOf(l) {
        return knownLocales.find(k => k.value.toLowerCase() === l.toLowerCase().replace("utf8", "UTF-8").replace("utf-8", "UTF-8"))?.label ?? l;
    }

    function refresh() {
        info.running = true;
    }

    Component.onCompleted: {
        refresh();
        zoneList.running = true;
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Process {
        id: info
        command: ["sh", "-c", "timedatectl show -p Timezone -p NTP; echo '@@'; localectl status | sed -n 's/.*LANG=//p'; echo '@@'; localectl list-locales"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [td, loc, list] = text.split("@@");
                page.zone = (td.match(/Timezone=(.*)/) ?? [])[1] ?? "";
                page.ntp = /NTP=yes/.test(td);
                page.locale = loc.trim();
                page.locales = list.split("\n").map(x => x.trim()).filter(x => x && x !== "C.UTF-8");
                page.busy = false;
            }
        }
    }

    Process {
        id: zoneList
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector {
            onStreamFinished: page.zones = text.split("\n").filter(x => x)
        }
    }

    Process {
        id: action
        onExited: page.refresh()
    }

    function run(cmd) {
        busy = true;
        action.command = cmd;
        action.running = true;
    }

    // ── большие часы
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 120
        radius: 12
        color: Theme.surface

        ColumnLayout {
            anchors.left: parent.left
            anchors.leftMargin: 26
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: Qt.locale(I18n.ru ? "ru_RU" : "en_US").toString(clock.date, page.is12h ? "h:mm:ss AP" : "HH:mm:ss")
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 40
                font.bold: true
            }
            Text {
                text: `${Qt.locale(I18n.ru ? "ru_RU" : "en_US").toString(clock.date, "dddd, d MMMM yyyy")}   ·   ${page.zone}`
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    SSection { text: I18n.tr("Date & time") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF1450)  // earth-clock? fallback glyph
            title: "Time zone"

            SDropdown {
                minWidth: 260
                enabled: !page.busy
                options: page.zones.map(z => ({ value: z, label: z.replace(/_/g, " ") }))
                current: page.zone
                onPicked: v => page.run(["timedatectl", "set-timezone", v])
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF06B0)
            title: "Set time automatically"
            desc: "Synchronize with internet time servers (NTP)"

            SSwitch {
                checked: page.ntp
                enabled: !page.busy
                onToggled: v => page.run(["timedatectl", "set-ntp", v ? "true" : "false"])
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0954)
            title: "Time format"
            desc: "Used by the bar clock"

            SChoice {
                options: [{ value: false, label: "24-hour" }, { value: true, label: "12-hour" }]
                current: page.is12h
                onPicked: v => {
                    Settings.clockFormat = v
                        ? Settings.clockFormat.replace(/HH:mm(:ss)?/, m => m.includes("ss") ? "h:mm:ss AP" : "h:mm AP")
                        : Settings.clockFormat.replace(/h:mm(:ss)? AP/, m => m.includes("ss") ? "HH:mm:ss" : "HH:mm");
                }
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF00ED)
            title: "First day of week"
            desc: "In the calendar"

            SChoice {
                options: [{ value: true, label: "Monday" }, { value: false, label: "Sunday" }]
                current: Settings.weekStartsMonday
                onPicked: v => Settings.weekStartsMonday = v
            }
        }
    }

    SSection { text: I18n.tr("Language") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        // язык самих Настроек — меняется сразу
        SCard {
            icon: String.fromCodePoint(0xF05CA)  // translate
            title: "Interface language"
            desc: "Bar, menus, widgets and settings — the whole shell"

            SChoice {
                options: [{ value: "en", label: "English" }, { value: "ru", label: "Русский" }]
                current: Settings.language || "en"
                onPicked: v => Settings.language = v
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF05CA)  // translate
            title: "System language"
            desc: "Language of apps and system messages. Takes effect after you log in again."

            SDropdown {
                minWidth: 240
                enabled: !page.busy
                options: page.locales.map(l => ({ value: l, label: page.labelOf(l) }))
                current: page.locale
                onPicked: v => page.run(["localectl", "set-locale", `LANG=${v}`])
            }
        }

        SCard {
            icon: "+"
            title: "Add a language"
            desc: "Generates the language on this computer (needs your password)"

            SDropdown {
                minWidth: 240
                enabled: !page.busy
                options: [{ value: "", label: "Choose…" }].concat(page.knownLocales.filter(k =>
                    !page.locales.some(l => l.toLowerCase().replace("utf8", "utf-8") === k.value.toLowerCase())))
                current: ""
                onPicked: v => {
                    if (!v) return;
                    page.run(["pkexec", "sh", "-c", 'sed -i "s/^#\\($1 UTF-8\\)/\\1/" /etc/locale.gen && locale-gen', "sh", v]);
                }
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF030C)
            title: "Keyboard layouts"
            desc: (Settings.input.layouts ?? []).join(", ")
            clickable: true
            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "settings", "page", "keyboard"])
        }
    }
}
