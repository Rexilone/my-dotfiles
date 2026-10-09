import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services

// Персонализация: цветовая схема (в т.ч. под обои), масштаб интерфейса, обои
Page {
    id: page

    title: "Personalization"
    subtitle: tab === "home" ? "Colors, wallpaper, fonts, the bar and desktop widgets" : ""
    crumb: tab === "home" ? "" : (sections.find(t => t.key === tab)?.label ?? "")
    onBack: openTab("home")

    property string tab: "home"

    // подстраницы: карточки на главной странице раздела
    readonly property var sections: [
        { key: "colors", label: "Colors", icon: 0xF03D8, desc: `${Theme.palette.name}   ·   dark, light, Nord, Gruvbox, Rosé, from wallpaper` },
        { key: "wallpaper", label: "Wallpaper", icon: 0xF0E09, desc: Wallpapers.current ? Wallpapers.current.split("/").pop() : "Pick a picture for the desktop" },
        { key: "transparency", label: "Transparency", icon: 0xF05CC, desc: Settings.transparency ? `${I18n.tr("On")}   ·   ${Math.round(Settings.opacity * 100)}%${Settings.blur ? ", " + I18n.tr("blur") : ""}` : "Off" },
        { key: "fonts", label: "Fonts", icon: 0xF06D6, desc: [Settings.font, Settings.monoFont].filter((v, i, a) => v && a.indexOf(v) === i).join("   ·   ") || "Interface and terminal fonts" },
        { key: "size", label: "Text size", icon: 0xF0284, desc: `${Math.round(Settings.uiScale * 100)}%   ·   bar and menus` },
        { key: "bar", label: "Bar", icon: 0xF0570, desc: `${({ flat: "Solid", floating: "Floating", pills: "Pills" })[Settings.barStyle] ?? Settings.barStyle}   ·   clock, modules, tray` },
        { key: "widgets", label: "Widgets", icon: 0xF0B92, desc: `${Object.values(Settings.widgets ?? {}).filter(w => w.enabled).length} ${I18n.ru ? "на рабочем столе" : "on the desktop"}   ·   ${I18n.tr("clock, weather, phone…")}` },
    ]

    function openTab(key) {
        tab = key;
        contentY = 0;
    }

    readonly property var schemeList: ["dark", "light", "nord", "gruvbox", "rose", "wallpaper"]

    property var fonts: []
    property var monoFonts: []

    Component.onCompleted: {
        if (!Wallpapers.items.length) Wallpapers.refresh();
        fontList.running = true;
    }

    // шрифты из fontconfig: все и моноширинные
    Process {
        id: fontList
        command: ["sh", "-c", "fc-list : family | cut -d, -f1 | sort -uf; echo '@mono'; fc-list :spacing=mono family | cut -d, -f1 | sort -uf"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [all, mono] = text.split("@mono");
                const clean = t => (t ?? "").split("\n").map(x => x.trim()).filter(x => x && !x.startsWith("."));
                page.fonts = clean(all);
                page.monoFonts = clean(mono);
            }
        }
    }

    // ═════════════════════════ главная страница раздела
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.tab === "home"
        spacing: 3

        // превью: обои с полоской бара и палитра схемы
        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 14
            implicitHeight: 196
            radius: 12
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 24

                // «монитор»
                Rectangle {
                    Layout.preferredWidth: 160 * 16 / 9
                    Layout.preferredHeight: 160
                    radius: 8
                    color: Theme.bg
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: (Wallpapers.items.find(i => i.path === Wallpapers.current)?.thumb ?? "") !== ""
                            ? "file://" + Wallpapers.items.find(i => i.path === Wallpapers.current).thumb
                            : (Wallpapers.current ? "file://" + Wallpapers.current : "")
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 320
                    }
                    // бар
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Settings.barStyle === "flat" ? 0 : 4
                        height: 10
                        radius: Settings.barStyle === "flat" ? 0 : 5
                        color: Theme.panel
                    }
                    // окно
                    Rectangle {
                        x: parent.width * 0.18
                        y: parent.height * 0.28
                        width: parent.width * 0.5
                        height: parent.height * 0.52
                        radius: 4
                        color: Theme.surface
                        border.width: 1
                        border.color: Theme.surfaceHi2

                        Rectangle {
                            x: 8; y: 10
                            width: parent.width * 0.4; height: 4; radius: 2
                            color: Theme.fg
                        }
                        Rectangle {
                            x: 8; y: 20
                            width: parent.width * 0.6; height: 4; radius: 2
                            color: Theme.dim
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 8
                            width: 30; height: 10; radius: 3
                            color: Theme.accent
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: Theme.palette.name
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 4
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Wallpapers.current ? Wallpapers.current.split("/").pop() : "No wallpaper"
                        elide: Text.ElideMiddle
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Row {
                        Layout.topMargin: 10
                        spacing: 6

                        Repeater {
                            model: [Theme.bg, Theme.surfaceHi2, Theme.dim, Theme.fg, Theme.accent, Theme.warn, Theme.urgent]

                            Rectangle {
                                required property color modelData
                                width: 22
                                height: 22
                                radius: 11
                                color: modelData
                                border.width: 1
                                border.color: Theme.line
                            }
                        }
                    }
                }
            }
        }

        Repeater {
            model: page.sections

            SCard {
                id: nav
                required property var modelData
                icon: String.fromCodePoint(modelData.icon)
                title: modelData.label
                desc: modelData.desc
                clickable: true
                onClicked: page.openTab(nav.modelData.key)
            }
        }
    }

    // ═════════════════════════ оформление
    ColumnLayout {
        Layout.fillWidth: true
        visible: ["colors", "wallpaper", "transparency", "fonts", "size"].includes(page.tab)
        spacing: 6

        Flow {
            Layout.fillWidth: true
            visible: page.tab === "colors"
            spacing: 10

            Repeater {
                model: page.schemeList

                Rectangle {
                    id: sc

                    required property string modelData
                    readonly property bool selected: Settings.scheme === modelData
                    readonly property var p: modelData === "wallpaper"
                        ? (WallColors.palette ?? { bg: "#202020", surface: "#2a2a2a", fg: "#dddddd", dim: "#777777", accent: "#aaaaaa", name: "Wallpaper" })
                        : Theme.schemes[modelData]

                    width: 168
                    height: 128
                    radius: 12
                    color: Theme.surface
                    border.width: selected ? 2 : 1
                    border.color: selected ? Theme.accent : scArea.containsMouse ? Theme.line : Theme.surfaceHi2

                    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                    // мини-превью: фон, «окно», текст, акцент
                    ClippingRectangle {
                        x: 10
                        y: 10
                        width: parent.width - 20
                        height: 80
                        radius: 8
                        color: sc.p.bg

                        Image {
                            visible: sc.modelData === "wallpaper" && !!Wallpapers.current
                            anchors.fill: parent
                            source: Wallpapers.current ? "file://" + Wallpapers.current : ""
                            sourceSize.width: 300
                            fillMode: Image.PreserveAspectCrop
                            opacity: 0.55
                            asynchronous: true
                        }

                        Rectangle {
                            width: parent.width
                            height: 12
                            color: sc.p.bg
                            opacity: 0.95

                            Rectangle {
                                x: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 4
                                radius: 2
                                color: sc.p.accent
                            }
                        }

                        Rectangle {
                            x: 12
                            y: 22
                            width: parent.width - 24
                            height: 48
                            radius: 6
                            color: sc.p.surface

                            Column {
                                x: 8
                                y: 9
                                spacing: 6
                                Rectangle { width: 60; height: 5; radius: 2; color: sc.p.fg }
                                Rectangle { width: 90; height: 4; radius: 2; color: sc.p.dim }
                                Rectangle { width: 36; height: 8; radius: 4; color: sc.p.accent }
                            }
                        }
                    }

                    Text {
                        x: 12
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 11
                        text: sc.modelData === "wallpaper" ? "From wallpaper" : sc.p.name
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: sc.selected
                    }

                    Text {
                        visible: sc.selected
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 11
                        text: String.fromCodePoint(0xF012C)  // check
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.iconSize
                    }

                    MouseArea {
                        id: scArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.scheme = sc.modelData
                    }
                }
            }
        }

        Text {
            Layout.topMargin: 4
            visible: page.tab === "colors" && Settings.scheme === "wallpaper"
            text: I18n.tr("Colors follow the current wallpaper and update when you change it.")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }

        SCard {
            visible: page.tab === "wallpaper"
            icon: String.fromCodePoint(0xF0E09)
            title: Wallpapers.current ? Wallpapers.current.split("/").pop() : "Wallpaper"
            desc: `Folder: ${Wallpapers.dir}`

            SButton {
                text: I18n.tr("Random")
                icon: String.fromCodePoint(0xF049D)
                onClicked: Wallpapers.random()
            }
            SButton {
                text: I18n.tr("Browse…")
                primary: true
                onClicked: Quickshell.execDetached(["qs", "ipc", "call", "wallpaper", "toggle"])
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: page.tab === "transparency"
            spacing: 3

            SCard {
                icon: String.fromCodePoint(0xF0E7A)  // blur
                title: "Transparency effects"
                desc: "See-through bar, menus and settings window"

                SSwitch {
                    checked: Settings.transparency
                    onToggled: v => Settings.transparency = v
                }
            }

            SCard {
                visible: Settings.transparency
                icon: String.fromCodePoint(0xF0AAB)
                title: "Panel opacity"
                desc: "Lower is more transparent"

                SSlider {
                    from: 0.4
                    to: 1
                    step: 0.05
                    value: Settings.opacity
                    display: value * 100
                    suffix: "%"
                    onMoved: v => Settings.opacity = Math.round(v * 100) / 100
                }
            }

            SCard {
                visible: Settings.transparency
                icon: String.fromCodePoint(0xF00B6)
                title: "Blur behind panels"
                desc: "Frosted glass look (niri background blur)"

                SSwitch {
                    checked: Settings.blur
                    onToggled: v => Settings.blur = v
                }
            }

            SCard {
                visible: Settings.transparency
                icon: String.fromCodePoint(0xF018D)
                title: "Terminal opacity"
                desc: "foot — applies to new terminal windows"

                SSlider {
                    from: 0.5
                    to: 1
                    step: 0.05
                    value: Settings.terminalOpacity
                    display: value * 100
                    suffix: "%"
                    onMoved: v => Settings.terminalOpacity = Math.round(v * 100) / 100
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: page.tab === "fonts"
            spacing: 3

            SCard {
                icon: String.fromCodePoint(0xF0281)  // format-font
                title: "Interface font"
                desc: "Bar, menus, notifications and settings"

                SDropdown {
                    minWidth: 260
                    fontPreview: true
                    options: page.fonts.map(f => ({ value: f, label: f }))
                    current: Settings.font
                    onPicked: v => Settings.font = v
                }
            }

            SCard {
                icon: String.fromCodePoint(0xF018D)
                title: "Terminal font"
                desc: "foot, Neovim and yazi — monospace fonts only"

                SDropdown {
                    minWidth: 260
                    fontPreview: true
                    options: page.monoFonts.map(f => ({ value: f, label: f }))
                    current: Settings.monoFont
                    onPicked: v => Settings.monoFont = v
                }
            }

            SCard {
                icon: String.fromCodePoint(0xF03D8)
                title: "Apps font"
                desc: "GTK apps (Files, settings dialogs…)"

                SDropdown {
                    minWidth: 260
                    fontPreview: true
                    options: [{ value: "", label: "System default" }].concat(page.fonts.map(f => ({ value: f, label: f })))
                    current: Settings.appFont
                    onPicked: v => Settings.appFont = v
                }
            }

            Text {
                Layout.topMargin: 4
                text: I18n.tr("Icons need a Nerd Font — if icons turn into boxes, pick a font with «Nerd Font» in the name.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }

        SCard {
            visible: page.tab === "size"
            icon: String.fromCodePoint(0xF0284)  // format-size
            title: "Text size"
            desc: "Scales fonts and icons in the bar and menus"

            SChoice {
                options: [0.9, 1, 1.1, 1.25].map(v => ({ value: v, label: `${Math.round(v * 100)}%` }))
                current: Settings.uiScale
                onPicked: v => Settings.uiScale = v
            }
        }
    }

    // обои: сетка миниатюр по 4 в ряд, клик — поставить
    Flow {
        id: wallGrid
        readonly property real thumbW: Math.floor((width - 3 * spacing) / 4)
        Layout.fillWidth: true
        Layout.topMargin: 10
        visible: page.tab === "wallpaper"
        spacing: 8

        Repeater {
            model: Wallpapers.items

            Rectangle {
                id: wp
                required property var modelData
                readonly property bool current: modelData.path === Wallpapers.current

                width: wallGrid.thumbW
                height: Math.round(wallGrid.thumbW * 9 / 16)
                radius: 8
                color: Theme.surface
                border.width: current ? 2 : 0
                border.color: Theme.accent
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: wp.current ? 3 : 0
                    source: wp.modelData.thumb ? "file://" + wp.modelData.thumb : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 336
                    opacity: wpArea.containsMouse || wp.current ? 1 : 0.85

                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                }

                MouseArea {
                    id: wpArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Wallpapers.apply(wp.modelData.path)
                }
            }
        }
    }

    // ═════════════════════════ бар
    BarPanel {
        visible: page.tab === "bar"
    }

    // ═════════════════════════ виджеты рабочего стола
    WidgetsPanel {
        visible: page.tab === "widgets"
    }
}
