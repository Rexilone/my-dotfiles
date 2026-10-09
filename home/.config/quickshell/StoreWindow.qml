import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.settings
import qs.store

// Магазин приложений: репозитории Arch и AUR. Открывается из меню приложений
// (~/.local/share/applications/rexilone-store.desktop) или `qs ipc call store open`.
// Окно создаётся при открытии и уничтожается при закрытии, как Настройки.
Scope {
    id: ctl

    property bool open: false
    property string page: "home"         // home | search | installed | updates | <категория>
    property string detail: ""           // открытое приложение (пакет)
    property bool detailAur: false
    property string pendingQuery: ""

    function show(p) {
        if (p) page = p;
        open = true;
    }
    function openApp(pkg, aur) {
        detailAur = !!aur;
        detail = pkg;
        open = true;
    }

    onOpenChanged: if (open) {
        if (!Store.catalog.length) Store.loadCatalog();
        Store.refreshInstalled();
        if (Date.now() - Store.lastUpdateCheck > 10 * 60 * 1000) Store.checkUpdates();
    }

    IpcHandler {
        target: "store"

        function open(): void { ctl.show(""); }
        function toggle(): void { ctl.open = !ctl.open; }
        // qs ipc call store search gimp
        function search(q: string): void { ctl.pendingQuery = q; ctl.detail = ""; ctl.show("search"); }
        // qs ipc call store app obs-studio
        function app(pkg: string): void { ctl.openApp(pkg, false); }
        function updates(): void { ctl.detail = ""; ctl.show("updates"); }
    }

    LazyLoader {
        active: ctl.open

        FloatingWindow {
            id: win

            title: "Store"  // на заголовок завязано правило окна в niri — не переводить
            visible: true
            implicitWidth: 1160
            implicitHeight: 780
            minimumSize: Qt.size(880, 580)
            color: Theme.panel

            onVisibleChanged: if (!visible) ctl.open = false

            BackgroundEffect.blurRegion: Theme.blurOn ? blurReg : null
            Region {
                id: blurReg
                item: rootItem
            }

            readonly property var nav: [
                { group: "", items: [{ key: "home", label: "Discover", icon: 0xF0D3B }] },
                { group: "Categories", items: Store.categories.map(c => ({ key: c.key, label: c.label, icon: c.icon })) },
                { group: "Library", items: [
                    { key: "installed", label: "Installed", icon: 0xF0C52 },
                    { key: "updates", label: "Updates", icon: 0xF06B0, badge: Store.updates.length },
                ] },
            ]

            Item {
                id: rootItem
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: {
                    if (ctl.detail) ctl.detail = "";
                    else win.visible = false;
                }
                Keys.onPressed: event => {
                    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_F || event.key === Qt.Key_L)) {
                        searchField.focusInput();
                        event.accepted = true;
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // ── боковая панель
                    Item {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 250

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            anchors.topMargin: 20
                            spacing: 0

                            RowLayout {
                                Layout.leftMargin: 6
                                Layout.bottomMargin: 18
                                spacing: 12

                                Rectangle {
                                    implicitWidth: 46
                                    implicitHeight: 46
                                    radius: 14
                                    color: Theme.accent
                                    Text {
                                        anchors.centerIn: parent
                                        text: String.fromCodePoint(0xF0110)
                                        color: Theme.bg
                                        font.family: Theme.font
                                        font.pixelSize: 24
                                    }
                                }
                                ColumnLayout {
                                    spacing: 2
                                    Text {
                                        text: I18n.tr("Store")
                                        color: Theme.fg
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize + 4
                                        font.bold: true
                                    }
                                    Text {
                                        text: "pacman · AUR"
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 2
                                    }
                                }
                            }

                            Flickable {
                                id: navFlick
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                contentHeight: navCol.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                ColumnLayout {
                                    id: navCol
                                    width: navFlick.width
                                    spacing: 2

                                    Repeater {
                                        model: win.nav

                                        ColumnLayout {
                                            id: grp
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 2

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

                                                Rectangle {
                                                    id: item
                                                    required property var modelData
                                                    readonly property bool selected: ctl.page === modelData.key && !ctl.detail

                                                    Layout.fillWidth: true
                                                    implicitHeight: 38
                                                    radius: 10
                                                    color: selected ? Theme.surface : itemArea.containsMouse ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.6) : "transparent"

                                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                                    Rectangle {
                                                        visible: item.selected
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 3
                                                        height: 18
                                                        radius: 2
                                                        color: Theme.accent
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 16
                                                        anchors.rightMargin: 10
                                                        spacing: 14

                                                        Text {
                                                            Layout.preferredWidth: 20
                                                            horizontalAlignment: Text.AlignHCenter
                                                            text: String.fromCodePoint(item.modelData.icon)
                                                            color: item.selected ? Theme.accent : Theme.muted
                                                            font.family: Theme.font
                                                            font.pixelSize: Theme.iconSize + 1
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: I18n.tr(item.modelData.label)
                                                            elide: Text.ElideRight
                                                            color: item.selected || itemArea.containsMouse ? Theme.fg : Theme.muted
                                                            font.family: Theme.font
                                                            font.pixelSize: Theme.fontSize - 1
                                                            font.bold: item.selected
                                                        }
                                                        Rectangle {
                                                            visible: (item.modelData.badge ?? 0) > 0
                                                            implicitWidth: Math.max(20, badgeText.implicitWidth + 10)
                                                            implicitHeight: 18
                                                            radius: 9
                                                            color: Theme.accent
                                                            Text {
                                                                id: badgeText
                                                                anchors.centerIn: parent
                                                                text: item.modelData.badge ?? ""
                                                                color: Theme.bg
                                                                font.family: Theme.font
                                                                font.pixelSize: Theme.fontSize - 4
                                                                font.bold: true
                                                            }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: itemArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            ctl.detail = "";
                                                            ctl.page = item.modelData.key;
                                                            if (item.modelData.key !== "search") searchField.text = "";
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── содержимое
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

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // поиск — всегда сверху
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 36
                                Layout.rightMargin: 36
                                Layout.topMargin: 22
                                Layout.bottomMargin: 4
                                visible: !ctl.detail
                                spacing: 10

                                SField {
                                    id: searchField
                                    implicitHeight: 42
                                    icon: Icons.search
                                    placeholder: I18n.tr("Search apps and packages — repositories and AUR")
                                    onTextChanged: {
                                        Store.search(text);
                                        if (text.trim()) ctl.page = "search";
                                        else if (ctl.page === "search") ctl.page = "home";
                                    }
                                    onAccepted: Store.search(text)
                                    input.Keys.onEscapePressed: event => {
                                        if (text) { text = ""; event.accepted = true; }
                                        else event.accepted = false;
                                    }
                                    Component.onCompleted: {
                                        if (ctl.pendingQuery) {
                                            text = ctl.pendingQuery;
                                            ctl.pendingQuery = "";
                                        }
                                        focusInput();
                                    }
                                    Connections {
                                        target: ctl
                                        function onPendingQueryChanged() {
                                            if (ctl.pendingQuery) {
                                                searchField.text = ctl.pendingQuery;
                                                ctl.pendingQuery = "";
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                // страницы
                                Loader {
                                    anchors.fill: parent
                                    visible: !ctl.detail
                                    sourceComponent: ctl.page === "home" ? homePage
                                        : ctl.page === "search" ? searchPage
                                        : ctl.page === "installed" ? installedPage
                                        : ctl.page === "updates" ? updatesPage
                                        : categoryPage
                                }

                                // приложение
                                AppDetail {
                                    anchors.fill: parent
                                    visible: !!ctl.detail
                                    pkg: ctl.detail
                                    aur: ctl.detailAur
                                    onBack: ctl.detail = ""
                                }
                            }

                            JobBar {
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            // ═════════════════════════ страницы
            component Scroll: Flickable {
                default property alias content: body.data
                contentHeight: body.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: body
                    x: 36
                    y: 14
                    width: parent.width - 72
                    spacing: 10
                }
            }

            component Header: RowLayout {
                property string text
                property string action: ""
                signal acted
                Layout.fillWidth: true
                Layout.topMargin: 14
                Text {
                    Layout.fillWidth: true
                    text: parent.text
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 3
                    font.bold: true
                }
                Text {
                    visible: parent.action !== ""
                    text: parent.action + "  ›"
                    color: actArea.containsMouse ? Theme.fg : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    MouseArea {
                        id: actArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: parent.parent.acted()
                    }
                }
            }

            component Grid: GridLayout {
                property var pkgs: []          // [имя] или [{ name, desc, aur }]
                property bool aur: false
                Layout.fillWidth: true
                columns: Math.max(1, Math.floor(width / 260))
                columnSpacing: 10
                rowSpacing: 10
                Repeater {
                    model: parent.pkgs
                    AppCard {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        pkg: typeof modelData === "string" ? modelData : modelData.name
                        summary: typeof modelData === "string" ? (Store.byPkg[pkg]?.summary ?? "") : I18n.tr(modelData.desc ?? "")
                        aur: typeof modelData !== "string" && !!modelData.aur
                        onOpen: (p, a) => ctl.openApp(p, a)
                    }
                }
            }

            component Empty: ColumnLayout {
                property string icon
                property string text
                property string hint: ""
                Layout.fillWidth: true
                Layout.topMargin: 40
                spacing: 8
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: parent.icon
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 44
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: parent.text
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 520
                    visible: parent.hint !== ""
                    text: parent.hint
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            // ── главная
            Component {
                id: homePage
                Scroll {
                    // нет каталога appstream — только поиск по пакетам
                    SCard {
                        visible: !Store.appstream
                        icon: String.fromCodePoint(0xF0026)
                        title: "App catalog is not installed"
                        desc: "archlinux-appstream-data gives names, icons, categories and screenshots. Search works without it"
                        SButton {
                            text: "Install"
                            primary: true
                            onClicked: Store.install("archlinux-appstream-data", false)
                        }
                    }

                    Header { text: I18n.tr("Editors' picks") }
                    Grid { pkgs: Store.picks.filter(p => Store.byPkg[p]) }

                    Header { text: I18n.tr("Popular in AUR") }
                    Grid { pkgs: Store.aurPicks.map(a => ({ name: a.name, desc: a.desc, aur: true })) }

                    Repeater {
                        model: Store.categories
                        ColumnLayout {
                            id: catBlock
                            required property var modelData
                            readonly property var list: Store.inCategory(modelData.key)
                            Layout.fillWidth: true
                            visible: list.length > 0
                            spacing: 10

                            Header {
                                text: I18n.tr(catBlock.modelData.label)
                                action: `${I18n.tr("All")} ${catBlock.list.length}`
                                onActed: ctl.page = catBlock.modelData.key
                            }
                            Grid {
                                // сначала подборки, потом приложения со скриншотами
                                pkgs: catBlock.list.slice().sort((a, b) =>
                                    (Store.picks.includes(b.pkg) - Store.picks.includes(a.pkg))
                                    || ((b.screenshots.length > 0) - (a.screenshots.length > 0))
                                    || (b.description.length > 200) - (a.description.length > 200)).slice(0, 6).map(a => a.pkg)
                            }
                        }
                    }

                    Text {
                        visible: Store.catalogLoading
                        text: I18n.tr("Loading…")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }

            // ── категория
            Component {
                id: categoryPage
                Scroll {
                    id: catPg
                    readonly property var cat: Store.categories.find(c => c.key === ctl.page) ?? ({})
                    property string sort: "popular"
                    readonly property var list: {
                        const l = Store.inCategory(ctl.page).slice();
                        if (sort === "name") return l;
                        return l.sort((a, b) => (Store.picks.includes(b.pkg) - Store.picks.includes(a.pkg))
                            || ((b.screenshots.length > 0) - (a.screenshots.length > 0)) || a.name.localeCompare(b.name));
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr(catPg.cat.label ?? "")
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 13
                            font.bold: true
                        }
                        SChoice {
                            options: [{ value: "popular", label: "Featured" }, { value: "name", label: "A–Z" }]
                            current: catPg.sort
                            onPicked: v => catPg.sort = v
                        }
                    }
                    Text {
                        text: `${catPg.list.length} ${I18n.plural(catPg.list.length, "app", "apps", "приложение", "приложения", "приложений")}`
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Grid { pkgs: catPg.list.map(a => a.pkg) }
                }
            }

            // ── поиск
            Component {
                id: searchPage
                Scroll {
                    id: srch
                    readonly property var appsFound: Store.searchCatalog(Store.query)
                    readonly property var appPkgs: appsFound.map(a => a.pkg)
                    readonly property var pkgsFound: Store.repoResults.filter(p => !appPkgs.includes(p.name)).slice(0, 40)

                    Header {
                        visible: srch.appsFound.length > 0
                        text: I18n.tr("Apps")
                    }
                    Grid { pkgs: srch.appPkgs.slice(0, 24) }

                    Header {
                        visible: srch.pkgsFound.length > 0
                        text: I18n.tr("Packages")
                    }
                    Repeater {
                        model: srch.pkgsFound
                        PkgRow {
                            required property var modelData
                            pkg: modelData.name
                            title: modelData.name
                            subtitle: modelData.desc
                            badge: modelData.repo
                            meta: modelData.version
                            onOpen: (p, a) => ctl.openApp(p, a)
                        }
                    }

                    Header {
                        visible: Store.aurResults.length > 0 || Store.aurError
                        text: "AUR"
                    }
                    Text {
                        visible: Store.aurError
                        text: I18n.tr("AUR is not reachable — check the connection")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Repeater {
                        model: Store.aurResults.slice(0, 40)
                        PkgRow {
                            required property var modelData
                            pkg: modelData.name
                            title: modelData.name
                            subtitle: modelData.desc
                            badge: "aur"
                            aur: true
                            meta: `${String.fromCodePoint(0xF04CE)} ${modelData.votes}   ${modelData.version}`
                            onOpen: (p, a) => ctl.openApp(p, true)
                        }
                    }

                    Text {
                        visible: Store.searching
                        Layout.topMargin: 10
                        text: I18n.tr("Searching repositories and AUR…")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Empty {
                        visible: !Store.searching && Store.query.trim().length >= 2 && srch.appsFound.length === 0
                            && srch.pkgsFound.length === 0 && Store.aurResults.length === 0
                        icon: Icons.search
                        text: I18n.tr("Nothing found")
                        hint: I18n.tr("Try another name or a shorter word")
                    }
                }
            }

            // ── установленное
            Component {
                id: installedPage
                Scroll {
                    id: inst
                    property string mode: "apps"
                    property string filter: ""
                    readonly property var list: Store.packages.filter(p => (inst.mode === "all" || p.app || Store.byPkg[p.name])
                        && (!inst.filter || `${p.name} ${Store.displayName(p.name)} ${p.desc}`.toLowerCase().includes(inst.filter)))
                        .sort((a, b) => Store.displayName(a.name).localeCompare(Store.displayName(b.name)))

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        spacing: 10
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Installed")
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 13
                            font.bold: true
                        }
                        SChoice {
                            options: [{ value: "apps", label: "Apps" }, { value: "all", label: "All packages" }]
                            current: inst.mode
                            onPicked: v => inst.mode = v
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text {
                            Layout.fillWidth: true
                            text: `${inst.list.length} ${I18n.plural(inst.list.length, "item", "items", "шт.", "шт.", "шт.")}   ·   ${Store.foreign.length} ${I18n.tr("from AUR")}`
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }
                        SField {
                            Layout.fillWidth: false
                            implicitWidth: 260
                            icon: Icons.search
                            placeholder: I18n.tr("Filter")
                            onTextChanged: inst.filter = text.trim().toLowerCase()
                        }
                    }

                    Repeater {
                        model: inst.list
                        PkgRow {
                            id: instRow
                            required property var modelData
                            pkg: modelData.name
                            subtitle: [modelData.name !== Store.displayName(modelData.name) ? modelData.name : "", Store.byPkg[modelData.name]?.summary || modelData.desc].filter(x => x).join("   ·   ")
                            badge: modelData.aur ? "aur" : ""
                            aur: modelData.aur
                            meta: [modelData.version, modelData.size].filter(x => x).join("   ·   ")
                            showAction: Store.canLaunch(modelData.name) || !!Store.busyWith(modelData.name)
                            onOpen: (p, a) => ctl.openApp(p, a)

                            SButton {
                                visible: !Store.busyWith(instRow.modelData.name)
                                icon: Icons.trash
                                danger: true
                                onClicked: Store.remove(instRow.modelData.name)
                            }
                        }
                    }
                }
            }

            // ── обновления
            Component {
                id: updatesPage
                Scroll {
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        spacing: 10
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Updates")
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 13
                            font.bold: true
                        }
                        SButton {
                            text: Store.checkingUpdates ? "Checking…" : "Check"
                            icon: String.fromCodePoint(0xF0450)
                            enabled: !Store.checkingUpdates
                            onClicked: Store.checkUpdates()
                        }
                        SButton {
                            visible: Store.updates.length > 0
                            text: Store.busyWith("") === "upgrade" || Store.jobs.some(j => j.kind === "upgrade" && (j.state === "running" || j.state === "queued")) ? "Updating…" : "Update all"
                            icon: String.fromCodePoint(0xF06B0)
                            primary: true
                            enabled: !Store.jobs.some(j => j.kind === "upgrade" && (j.state === "running" || j.state === "queued"))
                            onClicked: Store.upgradeAll()
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Store.updates.length
                            ? `${Store.updates.length} ${I18n.plural(Store.updates.length, "update", "updates", "обновление", "обновления", "обновлений")}   ·   ${I18n.tr("Arch updates the whole system at once — single packages aren't updated separately")}`
                            : ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }

                    SCard {
                        visible: !Store.hasCheckupdates
                        icon: String.fromCodePoint(0xF0026)
                        title: "Checking updates needs pacman-contrib"
                        desc: "It counts updates without touching the system"
                        SButton {
                            text: "Install"
                            primary: true
                            onClicked: Store.install("pacman-contrib", false)
                        }
                    }

                    Repeater {
                        model: Store.updates
                        PkgRow {
                            required property var modelData
                            pkg: modelData.name
                            subtitle: `${modelData.from}  →  ${modelData.to}`
                            badge: modelData.repo === "aur" ? "aur" : ""
                            aur: modelData.repo === "aur"
                            showAction: false
                            onOpen: (p, a) => ctl.openApp(p, a)
                        }
                    }

                    Empty {
                        visible: Store.updates.length === 0 && !Store.checkingUpdates && Store.hasCheckupdates
                        icon: String.fromCodePoint(0xF05E0)
                        text: I18n.tr("Everything is up to date")
                        hint: Store.lastUpdateCheck ? `${I18n.tr("Checked")} ${Qt.formatTime(new Date(Store.lastUpdateCheck), "HH:mm")}` : ""
                    }
                }
            }
        }
    }
}
