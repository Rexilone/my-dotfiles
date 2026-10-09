import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.settings

// окно настроек: qs ipc call settings toggle (Super+I)
// окно создаётся при открытии и уничтожается при закрытии:
// закрытое средствами niri окно Quickshell повторно показать не может
Scope {
    id: ctl

    property bool open: false
    property int current: 0
    property string pendingTab: ""   // вкладка, которую открыть…
    property int pendingPage: -1     // …на этой странице

    readonly property var pages: Ui.settingsPages

    function show(i) {
        // скрытая страница-ссылка: открыть её вкладку на другой странице
        const p = pages[i];
        if (p && p.go !== undefined) {
            pendingPage = p.go;
            pendingTab = p.tab ?? "";
            i = p.go;
        }
        if (i !== undefined) current = i;
        open = true;
    }

    IpcHandler {
        target: "settings"

        function toggle(): void { ctl.open = !ctl.open; }
        function open(): void { ctl.show(); }
        function hide(): void { ctl.open = false; }
        // qs ipc call settings scheme light   (dark | light | nord | gruvbox | rose | wallpaper)
        function scheme(name: string): void {
            if (Theme.schemes[name] || name === "wallpaper") Settings.scheme = name;
        }
        // qs ipc call settings page display
        function page(name: string): void {
            const n = name.toLowerCase();
            // старые имена страниц
            const alias = { keyboard: "peripherals", mouse: "peripherals", input: "peripherals" }[n] ?? n;
            const i = ctl.pages.findIndex(p => p.name.toLowerCase().startsWith(alias) && (!p.dev || Settings.developerMode));
            ctl.show(i >= 0 ? i : 0);
        }
    }

    LazyLoader {
        active: ctl.open

        FloatingWindow {
            id: win

            property string query: ""

        readonly property var visibleIdx: {
            const q = query.trim().toLowerCase();
            return ctl.pages.map((p, i) => i).filter(i => (!ctl.pages[i].dev || Settings.developerMode) && !ctl.pages[i].hidden && (!q || `${ctl.pages[i].name} ${I18n.tr(ctl.pages[i].name)} ${ctl.pages[i].keys}`.toLowerCase().includes(q)));
        }

            title: "Settings"  // на заголовок завязано правило окна в niri — не переводить
            visible: true
            implicitWidth: 1100
            implicitHeight: 760
            minimumSize: Qt.size(860, 560)
            color: Theme.panel

            // закрыли (Esc, крестик, Super+Q) — уничтожаем окно
            onVisibleChanged: if (!visible) ctl.open = false

        BackgroundEffect.blurRegion: Theme.blurOn ? blurReg : null
        Region {
            id: blurReg
            item: rootItem
        }

        Item {
            id: rootItem
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: win.visible = false
            Keys.onPressed: event => {
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
                    search.forceActiveFocus();
                    event.accepted = true;
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ── боковая панель
                Item {
                    id: sidebar
                    Layout.fillHeight: true
                    Layout.preferredWidth: 280

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        anchors.topMargin: 20
                        spacing: 0

                        // кто за компьютером
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            Layout.bottomMargin: 18
                            spacing: 12

                            Rectangle {
                                implicitWidth: 46
                                implicitHeight: 46
                                radius: 23
                                color: Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: (Quickshell.env("USER") ?? "?").charAt(0).toUpperCase()
                                    color: Theme.bg
                                    font.family: Theme.font
                                    font.pixelSize: 20
                                    font.bold: true
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: Quickshell.env("USER") ?? ""
                                    elide: Text.ElideRight
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize + 2
                                    font.bold: true
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: hostFile.text().trim() || I18n.tr("Local account")
                                    elide: Text.ElideRight
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 2
                                }
                            }

                            FileView {
                                id: hostFile
                                path: "/etc/hostname"
                                printErrors: false
                            }
                        }

                        // поиск настроек
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 14
                            implicitHeight: 38
                            radius: 10
                            color: Theme.surface
                            border.width: 1
                            border.color: search.activeFocus ? Theme.line : "transparent"

                            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Text {
                                    text: Icons.search
                                    color: search.activeFocus ? Theme.fg : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.iconSize - 1
                                }

                                TextInput {
                                    id: search
                                    Layout.fillWidth: true
                                    color: Theme.fg
                                    selectionColor: Theme.line
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 1
                                    clip: true
                                    onTextChanged: {
                                        win.query = text;
                                        if (win.visibleIdx.length && !win.visibleIdx.includes(ctl.current)) ctl.current = win.visibleIdx[0];
                                    }
                                    Keys.onReturnPressed: if (win.visibleIdx.length) ctl.current = win.visibleIdx[0]
                                    Keys.onEscapePressed: event => {
                                        if (text) { text = ""; event.accepted = true; }
                                        else event.accepted = false;
                                    }

                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        visible: !search.text
                                        text: I18n.tr("Find a setting")
                                        color: Theme.dim
                                        font: search.font
                                    }
                                }

                                Text {
                                    visible: !search.activeFocus && !search.text
                                    text: "Ctrl F"
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 3
                                }
                            }
                        }

                        // разделы по группам, с прокруткой
                        Flickable {
                            id: navFlick
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: navCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Item {
                                width: navFlick.width
                                height: navCol.implicitHeight

                                // выбранный пункт: плашка и полоска акцента ездят за выбором
                                Rectangle {
                                    id: selPill
                                    property Item target: null
                                    visible: !!target && target.visible
                                    x: 0
                                    y: target ? target.y + target.parent.y : 0
                                    width: parent.width
                                    height: 38
                                    radius: 10
                                    color: Theme.surface

                                    Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                                    Rectangle {
                                        x: 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 3
                                        height: 18
                                        radius: 2
                                        color: Theme.accent
                                    }
                                }

                                ColumnLayout {
                                    id: navCol
                                    width: parent.width
                                    spacing: 0

                                    Repeater {
                                        model: Ui.settingsNav

                                        ColumnLayout {
                                            id: grp
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 2
                                            visible: modelData.items.some(i => win.visibleIdx.includes(i))

                                            Text {
                                                visible: grp.modelData.group !== ""
                                                Layout.leftMargin: 14
                                                Layout.topMargin: 14
                                                Layout.bottomMargin: 4
                                                text: I18n.tr(grp.modelData.group)
                                                color: Theme.dim
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontSize - 3
                                                font.bold: true
                                            }

                                            Repeater {
                                                model: grp.modelData.items

                                                Item {
                                                    id: nav
                                                    required property int modelData
                                                    readonly property var pg: ctl.pages[modelData]
                                                    readonly property bool selected: ctl.current === modelData

                                                    visible: win.visibleIdx.includes(modelData)
                                                    Layout.fillWidth: true
                                                    implicitHeight: 38

                                                    onSelectedChanged: if (selected) selPill.target = nav
                                                    Component.onCompleted: if (selected) selPill.target = nav

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: 10
                                                        color: Theme.surface
                                                        opacity: navArea.containsMouse && !nav.selected ? 0.6 : 0

                                                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 16
                                                        anchors.rightMargin: 10
                                                        spacing: 14

                                                        Text {
                                                            Layout.preferredWidth: 20
                                                            horizontalAlignment: Text.AlignHCenter
                                                            text: String.fromCodePoint(nav.pg.icon2)
                                                            color: nav.selected ? Theme.accent : Theme.muted
                                                            font.family: Theme.font
                                                            font.pixelSize: Theme.iconSize + 1

                                                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: I18n.tr(nav.pg.name)
                                                            elide: Text.ElideRight
                                                            color: nav.selected || navArea.containsMouse ? Theme.fg : Theme.muted
                                                            font.family: Theme.font
                                                            font.pixelSize: Theme.fontSize - 1
                                                            font.bold: nav.selected

                                                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: navArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: ctl.current = nav.modelData
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        visible: win.visibleIdx.length === 0
                                        Layout.leftMargin: 14
                                        Layout.topMargin: 10
                                        text: I18n.tr("Nothing found")
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 1
                                    }
                                }
                            }
                        }

                    }
                }

                // ── страницы: на скруглённой панели чуть светлее фона
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 10
                    Layout.rightMargin: 10
                    Layout.bottomMargin: 10
                    radius: 16
                    color: Qt.tint(Theme.panel, Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5))
                    border.width: 1
                    border.color: Theme.surfaceHi
                    clip: true

                    component PageSlot: Loader {
                        id: slot
                        required property int index
                        anchors.fill: parent
                        active: false
                        visible: opacity > 0
                        opacity: ctl.current === index ? 1 : 0
                        y: ctl.current === index ? 0 : 14

                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        // страницу создаём при первом открытии и держим дальше
                        Connections {
                            target: ctl
                            function onCurrentChanged() { if (ctl.current === slot.index) slot.active = true; }
                        }
                        Component.onCompleted: if (ctl.current === index) active = true
                    }

                    PageSlot {
                        index: 0
                        sourceComponent: SystemPage {
                            aboutIndex: 16
                            onOpenPage: i => ctl.current = i
                        }
                    }
                    PageSlot { index: 1; sourceComponent: DisplayPage {} }
                    PageSlot { index: 2; sourceComponent: SoundPage {} }
                    PageSlot { index: 3; sourceComponent: NetworkPage {} }
                    PageSlot { index: 4; sourceComponent: BluetoothPage {} }
                    PageSlot { index: 5; sourceComponent: PhonePage {} }
                    PageSlot {
                        index: 7
                        sourceComponent: PersonalizationPage {
                            id: perso
                            function takeTab() {
                                if (ctl.pendingTab && ctl.pendingPage === 7) {
                                    perso.openTab(ctl.pendingTab);
                                    ctl.pendingTab = "";
                                    ctl.pendingPage = -1;
                                }
                            }
                            Component.onCompleted: takeTab()
                            Connections {
                                target: ctl
                                function onPendingTabChanged() { perso.takeTab(); }
                            }
                        }
                    }
                    PageSlot {
                        index: 10
                        sourceComponent: PeripheralsPage {
                            id: periph
                            function takeTab() {
                                if (ctl.pendingTab && ctl.pendingPage === 10) {
                                    periph.openTab(ctl.pendingTab);
                                    ctl.pendingTab = "";
                                    ctl.pendingPage = -1;
                                }
                            }
                            Component.onCompleted: takeTab()
                            Connections {
                                target: ctl
                                function onPendingTabChanged() { periph.takeTab(); }
                            }
                        }
                    }
                    PageSlot { index: 11; sourceComponent: BindsPage {} }
                    PageSlot { index: 12; sourceComponent: AutostartPage {} }
                    PageSlot { index: 13; sourceComponent: TimePage {} }
                    PageSlot { index: 14; sourceComponent: PowerPage {} }
                    PageSlot { index: 15; sourceComponent: NotificationsPage {} }
                    PageSlot { index: 16; sourceComponent: AboutPage {} }
                    PageSlot { index: 17; sourceComponent: PluginsPage {} }
                    PageSlot { index: 18; sourceComponent: UpdatesPage {} }
                }
            }
        }
        }
    }
}
