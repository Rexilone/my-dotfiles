import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services

// Периферия: все устройства и их настройки — клавиатура, мышь, тачпад, графический планшет,
// геймпады, принтеры и сканеры. Настройки ввода пишутся в niri (NiriSettings)
Page {
    id: page

    title: "Peripherals"
    subtitle: tab === "home" ? "Keyboard, mouse, graphics tablet, gamepads, printers and scanners" : ""
    crumb: tab === "home" ? "" : (tabs.find(t => t.key === tab)?.label ?? "")
    onBack: openTab("home")

    property string tab: "home"

    readonly property var inp: Settings.input
    readonly property var mouse: inp.mouse ?? {}
    readonly property var touchpad: inp.touchpad ?? {}
    readonly property var tablet: inp.tablet ?? {}

    // список устройств опрашиваем, только пока страница на экране
    readonly property bool watching: visible
    onWatchingChanged: Devices.need(watching)
    Component.onCompleted: if (watching) Devices.need(true)
    Component.onDestruction: if (watching) Devices.need(false)

    // подстраницы: карточки на главной странице раздела
    readonly property var tabs: [
        { key: "keyboard", label: "Keyboard", icon: 0xF030C,
          desc: (Settings.input.layouts ?? []).map(l => l.toUpperCase()).join(" · ") + "   ·   typing, layout switching" },
        { key: "mouse", label: "Mouse", icon: 0xF037D,
          desc: Devices.mice.length ? Devices.mice.map(d => d.name).join(", ") : "Pointer speed, buttons, scrolling" },
        { key: "touchpad", label: "Touchpad", icon: 0xF0741, hidden: Devices.touchpads.length === 0,
          desc: "Taps, scrolling, right click" },
        { key: "tablet", label: "Graphics tablet", icon: 0xF03EB,
          desc: Devices.tablets.length ? Devices.tablets[0].name : "Not connected   ·   screen, orientation" },
        { key: "gamepad", label: "Gamepads", icon: 0xF0EB5,
          desc: Devices.gamepads.length ? Devices.gamepads.map(d => d.name).join(", ") : "None connected   ·   test buttons and sticks" },
        { key: "printers", label: "Printers & scanners", icon: 0xF042A,
          desc: "Add a printer, print a test page, scan documents" },
    ]

    function openTab(key) {
        tab = key;
        contentY = 0;
    }

    readonly property var known: [
        { value: "us", label: "English (US)" }, { value: "ru", label: "Russian" }, { value: "ua", label: "Ukrainian" },
        { value: "by", label: "Belarusian" }, { value: "kz", label: "Kazakh" }, { value: "de", label: "German" },
        { value: "fr", label: "French" }, { value: "es", label: "Spanish" }, { value: "it", label: "Italian" },
        { value: "pl", label: "Polish" }, { value: "cz", label: "Czech" }, { value: "tr", label: "Turkish" },
        { value: "gb", label: "English (UK)" }, { value: "jp", label: "Japanese" }, { value: "ge", label: "Georgian" },
    ]

    function labelOf(code) {
        return known.find(k => k.value === code)?.label ?? code;
    }

    function deviceDesc(d) {
        const parts = [Devices.busLabel(d)];
        if (d.battery !== null && d.battery !== undefined) parts.push(`battery ${d.battery}%`);
        return parts.join("   ·   ");
    }

    // карточка устройства
    component DeviceCard: SCard {
        required property var device
        icon: Devices.kindIcon(device.kind)
        title: device.name
        desc: page.deviceDesc(device)
    }

    // ═════════════════════════ главная страница раздела
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.tab === "home"
        spacing: 3

        // подключённые устройства — плитки, как в Windows 11 (по 4 в ряд на всю ширину)
        Flow {
            id: tiles
            readonly property real tileW: Math.floor((width - 3 * spacing) / 4)
            Layout.fillWidth: true
            Layout.bottomMargin: 14
            spacing: 8

            Repeater {
                model: Devices.list

                Rectangle {
                    id: tile
                    required property var modelData
                    width: tiles.tileW
                    height: 112
                    radius: 10
                    color: tileArea.containsMouse ? Theme.surfaceHi : Theme.surface

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        x: 16
                        y: 16
                        text: Devices.kindIcon(tile.modelData.kind)
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.iconSize + 9
                    }
                    // заряд беспроводных
                    Text {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        visible: tile.modelData.battery !== null && tile.modelData.battery !== undefined
                        text: `${tile.modelData.battery}%`
                        color: (tile.modelData.battery ?? 100) <= 15 ? Theme.urgent : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Column {
                        x: 16
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        width: parent.width - 32
                        spacing: 2

                        Text {
                            width: parent.width
                            text: I18n.tr(tile.modelData.name)
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            width: parent.width
                            text: I18n.tr(Devices.busLabel(tile.modelData))
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }

                    MouseArea {
                        id: tileArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.openTab(tile.modelData.kind)
                    }
                }
            }

            // добавить устройство — через Bluetooth
            Rectangle {
                width: tiles.tileW
                height: 112
                radius: 10
                color: "transparent"
                border.width: 1
                border.color: addArea.containsMouse ? Theme.line : Theme.surfaceHi2

                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "+"
                        color: addArea.containsMouse ? Theme.fg : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.iconSize + 9
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr("Add device")
                        color: addArea.containsMouse ? Theme.fg : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                MouseArea {
                    id: addArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Ui.openSettings("bluetooth")
                }
            }
        }

        // разделы
        Repeater {
            model: page.tabs.filter(t => !t.hidden)

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

    // ═════════════════════════ клавиатура
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.tab === "keyboard"
        spacing: 3

        Repeater {
            model: Devices.keyboards
            DeviceCard { required property var modelData; device: modelData }
        }

        SSection { text: I18n.tr("Layouts") }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: layCol.implicitHeight + 28
            radius: 10
            color: Theme.surface

            ColumnLayout {
                id: layCol
                x: 18
                y: 14
                width: parent.width - 36
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        Layout.preferredWidth: 22
                        horizontalAlignment: Text.AlignHCenter
                        text: String.fromCodePoint(0xF030C)
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.iconSize + 3
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: I18n.tr("Layouts")
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            text: I18n.tr("Order matters: the first one is the default")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                    SDropdown {
                        minWidth: 170
                        options: [{ value: "", label: "+ Add layout" }].concat(page.known.filter(k => !(page.inp.layouts ?? []).includes(k.value)))
                        current: ""
                        onPicked: v => {
                            if (v) Settings.setInput("layouts", (page.inp.layouts ?? []).concat([v]));
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: 38
                    spacing: 6

                    Repeater {
                        model: page.inp.layouts ?? []

                        Rectangle {
                            id: chip
                            required property string modelData
                            required property int index

                            width: chipRow.implicitWidth + 20
                            height: 30
                            radius: 8
                            color: Theme.surfaceHi

                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: chip.modelData.toUpperCase()
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 2
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: page.labelOf(chip.modelData)
                                    color: Theme.muted
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 2
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    visible: (page.inp.layouts ?? []).length > 1
                                    text: Icons.close
                                    color: rmArea.containsMouse ? Theme.urgent : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 2
                                    anchors.verticalCenter: parent.verticalCenter

                                    MouseArea {
                                        id: rmArea
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Settings.setInput("layouts", page.inp.layouts.filter((_, i) => i !== chip.index))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0CB6)
            title: "Switch layout with"

            SDropdown {
                minWidth: 190
                options: [
                    { value: "grp:caps_toggle", label: "Caps Lock" },
                    { value: "grp:alt_shift_toggle", label: "Alt + Shift" },
                    { value: "grp:ctrl_shift_toggle", label: "Ctrl + Shift" },
                    { value: "grp:win_space_toggle", label: "Super + Space" },
                    { value: "grp:alt_space_toggle", label: "Alt + Space" },
                ]
                current: page.inp.switchKey
                onPicked: v => Settings.setInput("switchKey", v)
            }
        }

        SSection { text: I18n.tr("Typing") }

        SCard {
            icon: String.fromCodePoint(0xF051B)
            title: "Repeat delay"
            desc: "How long to hold a key before it repeats"

            SSlider {
                from: 150
                to: 1000
                step: 10
                value: page.inp.repeatDelay ?? 600
                suffix: " ms"
                onMoved: v => Settings.setInput("repeatDelay", Math.round(v))
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF04C5)
            title: "Repeat rate"
            desc: "Characters per second while holding a key"

            SSlider {
                from: 10
                to: 60
                step: 1
                value: page.inp.repeatRate ?? 25
                suffix: "/s"
                onMoved: v => Settings.setInput("repeatRate", Math.round(v))
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF03A0)
            title: "Num Lock on startup"

            SSwitch {
                checked: page.inp.numlock ?? true
                onToggled: v => Settings.setInput("numlock", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0313)
            title: "Keyboard shortcuts"
            desc: "Change or add your own key bindings"
            clickable: true
            onClicked: Ui.openSettings("keyboard shortcuts")
        }
    }

    // ═════════════════════════ мышь
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.tab === "mouse"
        spacing: 3

        Repeater {
            model: Devices.mice
            DeviceCard { required property var modelData; device: modelData }
        }

        SSection { text: I18n.tr("Pointer") }

        SCard {
            icon: String.fromCodePoint(0xF037D)
            title: "Pointer speed"

            SSlider {
                from: -1
                to: 1
                step: 0.05
                value: page.mouse.accelSpeed ?? 0
                display: value * 100
                suffix: "%"
                onMoved: v => Settings.setMouse("accelSpeed", Math.round(v * 100) / 100)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0E2E)
            title: "Acceleration"
            desc: "Flat is best for games — speed doesn't depend on how fast you move"

            SChoice {
                options: [{ value: "adaptive", label: "Adaptive" }, { value: "flat", label: "Flat" }]
                current: page.mouse.accelProfile ?? "adaptive"
                onPicked: v => Settings.setMouse("accelProfile", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0A9D)
            title: "Left-handed"
            desc: "Swap left and right buttons"

            SSwitch {
                checked: page.mouse.leftHanded ?? false
                onToggled: v => Settings.setMouse("leftHanded", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0C3E)
            title: "Focus follows mouse"
            desc: "Focus windows by hovering them"

            SSwitch {
                checked: page.inp.focusFollowsMouse ?? true
                onToggled: v => Settings.setInput("focusFollowsMouse", v)
            }
        }

        SSection { text: I18n.tr("Scrolling and buttons") }

        SCard {
            icon: String.fromCodePoint(0xF0E8A)
            title: "Natural scrolling"
            desc: "Content moves in the direction of the wheel"

            SSwitch {
                checked: page.mouse.naturalScroll ?? false
                onToggled: v => Settings.setMouse("naturalScroll", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0D27)
            title: "Scroll speed"
            desc: "How far one wheel step scrolls"

            SSlider {
                from: 0.2
                to: 3
                step: 0.1
                value: page.mouse.scrollFactor ?? 1
                display: value * 100
                suffix: "%"
                onMoved: v => Settings.setMouse("scrollFactor", Math.round(v * 10) / 10)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF037D)
            title: "Middle click with both buttons"
            desc: "Pressing left and right together acts as a middle click"

            SSwitch {
                checked: page.mouse.middleEmulation ?? false
                onToggled: v => Settings.setMouse("middleEmulation", v)
            }
        }
    }

    // ═════════════════════════ тачпад (вкладка есть, только если он подключён)
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.tab === "touchpad"
        spacing: 3

        Repeater {
            model: Devices.touchpads
            DeviceCard { required property var modelData; device: modelData }
        }

        SCard {
            icon: String.fromCodePoint(0xF0741)
            title: "Touchpad"
            desc: "Turn it off completely"

            SSwitch {
                checked: !(page.touchpad.off ?? false)
                onToggled: v => Settings.setInputIn("touchpad", "off", !v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0741)
            title: "Tap to click"

            SSwitch {
                checked: page.touchpad.tap ?? true
                onToggled: v => Settings.setInputIn("touchpad", "tap", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0E8A)
            title: "Natural scrolling"

            SSwitch {
                checked: page.touchpad.naturalScroll ?? true
                onToggled: v => Settings.setInputIn("touchpad", "naturalScroll", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF030C)
            title: "Disable while typing"

            SSwitch {
                checked: page.touchpad.dwt ?? true
                onToggled: v => Settings.setInputIn("touchpad", "dwt", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF037D)
            title: "Disable when a mouse is connected"

            SSwitch {
                checked: page.touchpad.disabledOnExternalMouse ?? false
                onToggled: v => Settings.setInputIn("touchpad", "disabledOnExternalMouse", v)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF037D)
            title: "Pointer speed"

            SSlider {
                from: -1
                to: 1
                step: 0.05
                value: page.touchpad.accelSpeed ?? 0
                display: value * 100
                suffix: "%"
                onMoved: v => Settings.setInputIn("touchpad", "accelSpeed", Math.round(v * 100) / 100)
            }
        }

        SCard {
            icon: String.fromCodePoint(0xF0741)
            title: "Right click"
            desc: "Bottom-right corner, or press with two fingers"

            SChoice {
                options: [{ value: "button-areas", label: "Corner" }, { value: "clickfinger", label: "Two fingers" }]
                current: page.touchpad.clickMethod ?? "button-areas"
                onPicked: v => Settings.setInputIn("touchpad", "clickMethod", v)
            }
        }
    }

    // ═════════════════════════ графический планшет
    ColumnLayout {
        id: tabletTab
        Layout.fillWidth: true
        visible: page.tab === "tablet"
        spacing: 3

        readonly property var dev: Devices.tablets[0] ?? null
        readonly property var outputs: Object.keys(NiriSettings.live)
        // планшет-экран: поворот на 90/270 и пропорции доступны только ему (матрица libinput)
        readonly property bool direct: dev ? !!dev.direct : !!page.tablet.direct

        // запомнить размер и тип планшета: нужны для конфига, даже если планшет отключат
        function set(key, value) {
            if (dev) {
                if (dev.widthMm) {
                    Settings.setInputIn("tablet", "widthMm", dev.widthMm);
                    Settings.setInputIn("tablet", "heightMm", dev.heightMm);
                }
                Settings.setInputIn("tablet", "direct", !!dev.direct);
            }
            Settings.setInputIn("tablet", key, value);
        }

        // какая часть планшета используется (как в NiriSettings.tabletMatrix), доли 0..1
        readonly property var area: {
            const tb = page.tablet;
            const w = dev?.widthMm ?? tb.widthMm ?? 0, h = dev?.heightMm ?? tb.heightMm ?? 0;
            if (!tabletTab.direct || !tb.keepAspect || !w || !h) return { x: 0, y: 0, w: 1, h: 1 };
            const rot = Number(tb.rotation ?? 0);
            const side = rot === 90 || rot === 270;
            const ta = side ? h / w : w / h;
            const oa = NiriSettings.outputAspect(tb.mapTo);
            if (!oa) return { x: 0, y: 0, w: 1, h: 1 };
            // в координатах планшета (до поворота)
            let fw = 1, fh = 1;
            if (ta > oa) { if (side) fh = oa / ta; else fw = oa / ta; }
            else { if (side) fw = ta / oa; else fh = ta / oa; }
            return { x: (1 - fw) / 2, y: (1 - fh) / 2, w: fw, h: fh };
        }

        // ── OpenTabletDriver: область, экран, поворот
        ColumnLayout {
            id: otdBox
            Layout.fillWidth: true
            visible: Tablet.active
            spacing: 3

            Component.onCompleted: Tablet.refresh()

            // область в мм, пока тянут мышью — локально, в драйвер — по отпусканию
            property real aw: Tablet.area?.Width ?? Tablet.maxW
            property real ah: Tablet.area?.Height ?? Tablet.maxH
            property real ax: Tablet.area?.X ?? Tablet.maxW / 2
            property real ay: Tablet.area?.Y ?? Tablet.maxH / 2
            property bool dragging: false
            readonly property bool lock: !!Tablet.profile?.AbsoluteModeSettings?.LockAspectRatio

            Connections {
                target: Tablet
                function onAreaChanged() {
                    if (otdBox.dragging || !Tablet.area) return;
                    otdBox.aw = Tablet.area.Width; otdBox.ah = Tablet.area.Height;
                    otdBox.ax = Tablet.area.X; otdBox.ay = Tablet.area.Y;
                }
            }

            function commit() {
                dragging = false;
                Tablet.setArea(aw, ah, ax, ay);
            }

            // схема планшета с рабочей областью
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: padArea.height + 92
                radius: 10
                color: Theme.surface

                Text {
                    x: 18
                    y: 14
                    text: Tablet.tabletName
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    y: 16
                    text: `OpenTabletDriver   ·   ${I18n.tr(Tablet.running ? "running" : "not running")}`
                    color: Tablet.running ? Theme.dim : Theme.urgent
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }

                // корпус планшета
                Rectangle {
                    id: padArea
                    readonly property real k: width / Tablet.maxW     // пикселей на мм
                    y: 46
                    width: Math.min(parent.width - 36, 300 * Tablet.maxW / Tablet.maxH)
                    x: (parent.width - width) / 2
                    height: Math.round(width * Tablet.maxH / Tablet.maxW)
                    radius: 10
                    color: Theme.surfaceHi
                    border.width: 1
                    border.color: Theme.line

                    // сетка 1 см
                    Repeater {
                        model: Math.floor(Tablet.maxW / 10)
                        Rectangle {
                            required property int index
                            x: (index + 1) * 10 * padArea.k
                            width: 1
                            height: padArea.height
                            color: Theme.surfaceHi2
                            visible: x < padArea.width - 2
                        }
                    }

                    // рабочая область (поворачивается вокруг центра, как в OTD)
                    Rectangle {
                        id: areaRect
                        width: otdBox.aw * padArea.k
                        height: otdBox.ah * padArea.k
                        x: otdBox.ax * padArea.k - width / 2
                        y: otdBox.ay * padArea.k - height / 2
                        rotation: Number(Tablet.area?.Rotation ?? 0)
                        radius: 6
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, moveArea.containsMouse || otdBox.dragging ? 0.2 : 0.12)
                        border.width: 2
                        border.color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: `↑ ${Tablet.screen || I18n.tr("all screens")}`
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                        }

                        // перетащить
                        MouseArea {
                            id: moveArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property point start
                            property real sx
                            property real sy
                            onPressed: mouse => {
                                start = mapToItem(padArea, mouse.x, mouse.y);
                                sx = otdBox.ax; sy = otdBox.ay;
                                otdBox.dragging = true;
                            }
                            onPositionChanged: mouse => {
                                if (!pressed) return;
                                const p = mapToItem(padArea, mouse.x, mouse.y);
                                otdBox.ax = Math.max(otdBox.aw / 2, Math.min(Tablet.maxW - otdBox.aw / 2, sx + (p.x - start.x) / padArea.k));
                                otdBox.ay = Math.max(otdBox.ah / 2, Math.min(Tablet.maxH - otdBox.ah / 2, sy + (p.y - start.y) / padArea.k));
                            }
                            onReleased: otdBox.commit()
                        }

                        // потянуть за угол — размер (от центра, симметрично)
                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: -6
                            width: 14
                            height: 14
                            radius: 7
                            color: Theme.accent
                            border.width: 2
                            border.color: Theme.surfaceHi

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.SizeFDiagCursor
                                onPressed: otdBox.dragging = true
                                onPositionChanged: mouse => {
                                    if (!pressed) return;
                                    const p = mapToItem(padArea, mouse.x, mouse.y);
                                    let w = Math.abs(p.x / padArea.k - otdBox.ax) * 2;
                                    let h = Math.abs(p.y / padArea.k - otdBox.ay) * 2;
                                    if (otdBox.lock) h = w / Tablet.displayAspect();
                                    w = Math.max(10, Math.min(w, 2 * Math.min(otdBox.ax, Tablet.maxW - otdBox.ax)));
                                    h = Math.max(10, Math.min(h, 2 * Math.min(otdBox.ay, Tablet.maxH - otdBox.ay)));
                                    if (otdBox.lock) w = Math.min(w, h * Tablet.displayAspect());
                                    otdBox.aw = w;
                                    otdBox.ah = h;
                                }
                                onReleased: otdBox.commit()
                            }
                        }
                    }
                }

                // размеры и готовые области
                RowLayout {
                    x: 18
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    width: parent.width - 36
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: `${otdBox.aw.toFixed(1)} × ${otdBox.ah.toFixed(1)} ${I18n.ru ? "мм" : "mm"}   ·   ${I18n.tr("of")} ${Tablet.maxW} × ${Tablet.maxH}`
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }

                    Repeater {
                        model: [{ f: 1, l: "Full" }, { f: 0.75, l: "3/4" }, { f: 0.5, l: "1/2" }, { f: 1 / 3, l: "1/3" }]

                        SButton {
                            required property var modelData
                            text: modelData.l
                            onClicked: Tablet.preset(modelData.f)
                        }
                    }
                }
            }

            SSection { text: I18n.tr("Mapping") }

            SCard {
                icon: String.fromCodePoint(0xF0379)
                title: "Screen"
                desc: "Which monitor the tablet draws on"

                SDropdown {
                    minWidth: 220
                    options: [{ value: "", label: "All monitors" }].concat(Tablet.displays.filter(d => d.index > 0).map(d => ({ value: d.name, label: `${d.name}  ·  ${d.w}×${d.h}` })))
                    current: Tablet.screen
                    onPicked: v => Tablet.setScreen(v)
                }
            }

            SCard {
                icon: String.fromCodePoint(0xF0A9D)
                title: "Orientation"
                desc: "Left-handed turns the tablet upside down; 90° for a portrait monitor"

                SChoice {
                    options: [
                        { value: 0, label: "Normal" },
                        { value: 180, label: "Left-handed" },
                        { value: 90, label: "90°" },
                        { value: 270, label: "270°" },
                    ]
                    current: Number(Tablet.area?.Rotation ?? 0)
                    onPicked: v => Tablet.setRotation(v)
                }
            }

            SCard {
                icon: String.fromCodePoint(0xF0E2E)
                title: "Keep proportions"
                desc: "Area follows the screen's shape, so a circle on the tablet is a circle on the screen"

                SSwitch {
                    checked: otdBox.lock
                    onToggled: v => {
                        Tablet.setLock(v);
                        if (v) {
                            // подогнать текущую область под пропорции экрана
                            const a = Tablet.displayAspect();
                            let w = otdBox.aw, h = otdBox.ah;
                            if (w / h > a) w = h * a; else h = w / a;
                            Tablet.setArea(w, h, otdBox.ax, otdBox.ay);
                        }
                    }
                }
            }

            SCard {
                icon: String.fromCodePoint(0xF03EB)
                title: "OpenTabletDriver"
                desc: "Pen buttons, pressure curve and filters — in the driver's own app"

                SButton {
                    text: "Open"
                    onClicked: Quickshell.execDetached(["otd-gui"])
                }
            }
        }

        // ── без OpenTabletDriver: то, что умеет niri
        ColumnLayout {
            Layout.fillWidth: true
            visible: !Tablet.active
            spacing: 3

            SCard {
                visible: !tabletTab.dev
                icon: String.fromCodePoint(0xF03EB)
                title: "No graphics tablet connected"
                desc: "Wacom, Huion, XP-Pen and other tablets work out of the box. Settings below apply when one is connected"
            }

            // планшет и используемая область
            Rectangle {
                Layout.fillWidth: true
                visible: !!tabletTab.dev
                implicitHeight: 200
                radius: 10
                color: Theme.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 24

                    Item {
                        Layout.preferredWidth: 220
                        Layout.fillHeight: true

                        // корпус планшета
                        Rectangle {
                            id: pad
                            readonly property real ratio: (tabletTab.dev?.widthMm ?? 16) / (tabletTab.dev?.heightMm ?? 10)
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height * ratio)
                            height: width / ratio
                            radius: 10
                            color: Theme.surfaceHi
                            border.width: 1
                            border.color: Theme.line

                            // используемая область
                            Rectangle {
                                x: 8 + (pad.width - 16) * tabletTab.area.x
                                y: 8 + (pad.height - 16) * tabletTab.area.y
                                width: (pad.width - 16) * tabletTab.area.w
                                height: (pad.height - 16) * tabletTab.area.h
                                radius: 4
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                                border.width: 1.5
                                border.color: Theme.accent

                                Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
                                Behavior on y { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
                                Behavior on width { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
                                Behavior on height { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }

                                // «верх» экрана с учётом поворота
                                Text {
                                    anchors.centerIn: parent
                                    rotation: -Number(page.tablet.rotation ?? 0)
                                    text: "↑ " + (page.tablet.mapTo || "all screens")
                                    color: Theme.accent
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 3
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: tabletTab.dev?.name ?? ""
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 1
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: [tabletTab.dev?.model, Devices.busLabel(tabletTab.dev ?? {})].filter(x => x).join("   ·   ")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            Layout.topMargin: 8
                            Layout.fillWidth: true
                            visible: !!tabletTab.dev?.widthMm
                            text: {
                                const d = tabletTab.dev, a = tabletTab.area;
                                if (!d?.widthMm) return "";
                                const full = `${Math.round(d.widthMm)} × ${Math.round(d.heightMm)} mm`;
                                if (a.w === 1 && a.h === 1) return `Active area: ${full} (whole tablet)`;
                                return `Active area: ${Math.round(d.widthMm * a.w)} × ${Math.round(d.heightMm * a.h)} mm of ${full}`;
                            }
                            wrapMode: Text.Wrap
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Pen buttons: lower — right click, upper — middle click")
                            wrapMode: Text.Wrap
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }
            }

            SSection { text: I18n.tr("Mapping") }

            SCard {
                icon: String.fromCodePoint(0xF0379)
                title: "Screen"
                desc: "Which monitor the tablet draws on"

                SDropdown {
                    minWidth: 200
                    options: [{ value: "", label: "All monitors" }].concat(tabletTab.outputs.map(n => {
                        const o = NiriSettings.live[n];
                        return { value: n, label: `${n}  ·  ${o?.model ?? ""}` };
                    }))
                    current: page.tablet.mapTo ?? ""
                    onPicked: v => tabletTab.set("mapTo", v)
                }
            }

            SCard {
                icon: String.fromCodePoint(0xF0A9D)
                title: "Orientation"
                desc: tabletTab.direct ? "Left-handed turns the tablet upside down; 90° for a portrait monitor"
                                       : "Left-handed turns the tablet upside down"

                SChoice {
                    options: tabletTab.direct ? [
                        { value: 0, label: "Normal" },
                        { value: 180, label: "Left-handed" },
                        { value: 90, label: "90°" },
                        { value: 270, label: "270°" },
                    ] : [
                        { value: 0, label: "Normal" },
                        { value: 180, label: "Left-handed" },
                    ]
                    // 90/270 у обычного планшета не работают — показываем как «Normal»
                    current: {
                        const r = Number(page.tablet.rotation ?? 0);
                        return tabletTab.direct || r === 180 ? r : 0;
                    }
                    onPicked: v => tabletTab.set("rotation", v)
                }
            }

            SCard {
                visible: tabletTab.direct
                icon: String.fromCodePoint(0xF0E2E)
                title: "Keep proportions"
                desc: "Use part of the tablet so a circle on it is a circle on the screen"

                SSwitch {
                    checked: page.tablet.keepAspect ?? false
                    onToggled: v => tabletTab.set("keepAspect", v)
                }
            }

            // почему нет 90°/270° и пропорций
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                visible: !!tabletTab.dev && !tabletTab.direct
                text: I18n.tr("Rotation by 90° and keeping proportions work only for pen displays: niri passes them to libinput, which ignores them for regular tablets.")
                wrapMode: Text.Wrap
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }

            SCard {
                icon: String.fromCodePoint(0xF03EB)
                title: "Tablet"
                desc: "Turn the pen input off completely"

                SSwitch {
                    checked: !(page.tablet.off ?? false)
                    onToggled: v => tabletTab.set("off", !v)
                }
            }
        }
        }

    // ═════════════════════════ геймпады
    ColumnLayout {
        id: padTab
        Layout.fillWidth: true
        visible: page.tab === "gamepad"
        spacing: 3

        property string testing: ""     // js-узел, который сейчас проверяем
        property var state: ({ axes: [], buttons: [] })

        function stop() {
            testing = "";
            state = { axes: [], buttons: [] };
        }

        // ушли со вкладки или геймпад отключили — перестаём читать
        Connections {
            target: page
            function onTabChanged() { if (page.tab !== "gamepad") padTab.stop(); }
            function onVisibleChanged() { if (!page.visible) padTab.stop(); }
        }
        Connections {
            target: Devices
            function onGamepadsChanged() {
                if (padTab.testing && !Devices.gamepads.some(g => g.js.includes(padTab.testing))) padTab.stop();
            }
        }

        Process {
            running: padTab.testing !== ""
            command: ["python3", Quickshell.shellPath("scripts/gamepad-test.py"), padTab.testing]
            stdout: SplitParser {
                onRead: line => {
                    try { padTab.state = JSON.parse(line); } catch (e) {}
                }
            }
            onRunningChanged: if (!running && padTab.testing) padTab.stop()
        }

        SCard {
            visible: Devices.gamepads.length === 0
            icon: String.fromCodePoint(0xF0EB5)
            title: "No gamepads connected"
            desc: "Plug in by USB or pair over Bluetooth (hold the pairing button on the controller)"

            SButton {
                text: I18n.tr("Bluetooth")
                onClicked: Ui.openSettings("bluetooth")
            }
        }

        Repeater {
            model: Devices.gamepads

            DeviceCard {
                id: gp
                required property var modelData
                device: modelData
                readonly property string node: modelData.js[0] ?? ""

                SButton {
                    visible: gp.node !== ""
                    text: padTab.testing === gp.node ? "Stop" : "Test"
                    primary: padTab.testing !== gp.node
                    onClicked: padTab.testing === gp.node ? padTab.stop() : (padTab.testing = gp.node)
                }
            }
        }

        // проверка: кнопки загораются, стики и курки — полосы
        Rectangle {
            Layout.fillWidth: true
            visible: padTab.testing !== ""
            implicitHeight: testCol.implicitHeight + 32
            radius: 10
            color: Theme.surface

            ColumnLayout {
                id: testCol
                x: 18
                y: 16
                width: parent.width - 36
                spacing: 14

                Text {
                    text: I18n.tr("Press buttons and move the sticks")
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: padTab.state.buttons

                        Rectangle {
                            required property int modelData
                            required property int index
                            width: 34
                            height: 34
                            radius: 17
                            color: modelData ? Theme.accent : Theme.surfaceHi
                            border.width: 1
                            border.color: Theme.surfaceHi2

                            Behavior on color { ColorAnimation { duration: 60 } }

                            Text {
                                anchors.centerIn: parent
                                text: parent.index
                                color: parent.modelData ? Theme.bg : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: true
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 8

                    Repeater {
                        model: padTab.state.axes

                        RowLayout {
                            required property real modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                Layout.preferredWidth: 48
                                text: `Axis ${index}`
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 2
                            }
                            // полоса от центра: -1 … 1
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 8
                                radius: 4
                                color: Theme.surfaceHi2

                                Rectangle {
                                    readonly property real v: Math.max(-1, Math.min(1, parent.parent.modelData))
                                    x: v < 0 ? parent.width / 2 * (1 + v) : parent.width / 2
                                    width: parent.width / 2 * Math.abs(v)
                                    height: parent.height
                                    radius: 4
                                    color: Theme.accent
                                }
                                Rectangle {
                                    x: parent.width / 2 - 1
                                    width: 2
                                    height: parent.height
                                    color: Theme.line
                                }
                            }
                        }
                    }
                }
            }
        }

        SCard {
            Layout.topMargin: 8
            icon: String.fromCodePoint(0xF04D3)
            title: "Games in Steam"
            desc: "Button layouts per game are set in Steam → Settings → Controller"
        }
    }

    // ═════════════════════════ принтеры и сканеры
    PrintersPanel {
        visible: page.tab === "printers"
        active: page.visible && page.tab === "printers"
    }
}
