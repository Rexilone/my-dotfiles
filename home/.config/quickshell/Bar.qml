import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import qs.services
import qs.modules

PanelWindow {
    id: bar

    required property ShellScreen modelData
    screen: modelData

    // открытый попап: "", "calendar", "output", "input", "tray", "network", "notifications", "control"
    property string popup: ""
    property real popupX: 0
    property var trayItem: null

    // стиль: flat — сплошной, floating — плавающий со скруглением, pills — группы на плашках
    readonly property string style: Settings.barStyle
    readonly property int gap: style === "flat" ? 0 : 6

    Connections {
        target: Ui
        function onCloseMenus() { bar.popup = ""; }
    }

    // меню приложения из трея (из бара или из сетки трея)
    function openTrayMenu(item, icon) {
        if (popup === "tray" && trayItem === item) {
            popup = "";
        } else {
            trayItem = item;
            popup = "";
            toggle("tray", icon);
        }
    }

    function toggle(name, item) {
        if (popup === name) {
            popup = "";
        } else {
            popupX = item.mapToItem(null, item.width / 2, 0).x;
            popup = name;
        }
    }

    // открыть окно часов на нужной вкладке (0 календарь, 1 плеер, 2 погода, 3 система)
    function openDash(tab) {
        if (popup === "calendar" && dash.current === tab) {
            popup = "";
            return;
        }
        dash.current = tab;
        popupX = clock.mapToItem(null, clock.width / 2, 0).x;
        popup = "calendar";
    }

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight + gap
    color: "transparent"

    // размытие под баром: под фоном или под каждой плашкой
    BackgroundEffect.blurRegion: Theme.blurOn ? blurReg : null
    Region {
        id: blurReg
        item: bar.style === "pills" ? null : barBg
        radius: barBg.radius
        Region { item: bar.style === "pills" && gLaunch.visible ? gLaunch : null; radius: gLaunch.height / 2 }
        Region { item: bar.style === "pills" && gWs.visible ? gWs : null; radius: gWs.height / 2 }
        Region { item: bar.style === "pills" && gWin.visible ? gWin : null; radius: gWin.height / 2 }
        Region { item: bar.style === "pills" && gMedia.visible ? gMedia : null; radius: gMedia.height / 2 }
        Region { item: bar.style === "pills" && gClock.visible ? gClock : null; radius: gClock.height / 2 }
        Region { item: bar.style === "pills" && gInd.visible ? gInd : null; radius: gInd.height / 2 }
        Region { item: bar.style === "pills" && gTray.visible ? gTray : null; radius: gTray.height / 2 }
        Region { item: bar.style === "pills" && gPlug.visible ? gPlug : null; radius: gPlug.height / 2 }
        Region { item: bar.style === "pills" && gStatus.visible ? gStatus : null; radius: gStatus.height / 2 }
    }

    // фон бара
    Rectangle {
        id: barBg
        anchors.fill: parent
        anchors.topMargin: bar.gap
        anchors.leftMargin: bar.style === "floating" ? 10 : 0
        anchors.rightMargin: bar.style === "floating" ? 10 : 0
        visible: bar.style !== "pills"
        radius: bar.style === "floating" ? 14 : 0
        color: Theme.panel
        border.width: bar.style === "floating" ? 1 : 0
        border.color: Theme.surfaceHi2
    }

    Item {
        id: inner
        anchors.fill: parent
        anchors.topMargin: bar.gap
        anchors.leftMargin: bar.style === "floating" ? 10 : bar.style === "pills" ? 8 : 0
        anchors.rightMargin: bar.style === "floating" ? 10 : bar.style === "pills" ? 8 : 0

        // ── слева
        Row {
            anchors.left: parent.left
            anchors.leftMargin: bar.style === "pills" ? 0 : Theme.padding
            height: parent.height
            spacing: 10

            // меню приложений (Super+D) — кнопка в самом начале бара
            BarGroup {
                id: gLaunch
                visible: Settings.moduleOn("launcher", true)
                BarText {
                    id: launchBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xF08C7)  // логотип Arch
                    font.pixelSize: Theme.iconSize + 2
                    onClicked: Quickshell.execDetached(["qs", "ipc", "call", "launcher", "toggle"])
                }
            }

            BarGroup {
                id: gWs
                Workspaces {
                    anchors.verticalCenter: parent.verticalCenter
                    output: bar.modelData.name
                }
            }

            BarGroup {
                id: gWin
                visible: Settings.moduleOn("window", false) && !!Niri.focusedWindow
                ActiveWindow {
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ── по центру
        Row {
            anchors.centerIn: parent
            height: parent.height
            spacing: 10

            BarGroup {
                id: gMedia
                visible: Settings.moduleOn("media", false) && !!media.player && !!media.player.trackTitle
                BarMedia {
                    id: media
                    anchors.verticalCenter: parent.verticalCenter
                    onOpenPlayer: bar.openDash(1)
                }
            }

            BarGroup {
                id: gClock
                spacing: 14

                Clock {
                    id: clock
                    anchors.verticalCenter: parent.verticalCenter
                    active: bar.popup !== "calendar"
                    onClicked: bar.openDash(0)
                }

                BarWeather {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Settings.moduleOn("weather", false) && Weather.configured && !!Weather.current
                    onOpenWeather: bar.openDash(2)
                }
            }
        }

        // ── справа
        Row {
            anchors.right: parent.right
            anchors.rightMargin: bar.style === "pills" ? 0 : Theme.padding
            height: parent.height
            spacing: 10

            BarGroup {
                id: gInd
                // группа индикаторов: видна, только если в ней что-то есть
                visible: Power.caffeine || NightLight.on || Recorder.recording || Recorder.countdown > 0 || Recorder.replayActive
                    || (Settings.moduleOn("castHidden", true) && CastHide.apps.length > 0)
                    || Settings.moduleOn("stats", false)
                    || (Settings.moduleOn("updates", false) && (!Updates.installed || Updates.count > 0 || Updates.checking))

                // есть приложения, скрытые с демонстрации (Super+G); ярче — если скрыто активное окно
                BarText {
                    id: castIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Settings.moduleOn("castHidden", true) && CastHide.apps.length > 0
                    text: String.fromCodePoint(0xF0209)
                    color: CastHide.focusedHidden ? Theme.warn : Theme.dim
                    active: bar.popup === "cast"
                    onClicked: bar.toggle("cast", castIcon)
                }
                // «Не засыпать» включён
                BarText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Power.caffeine
                    text: String.fromCodePoint(0xF0176)
                    color: Theme.warn
                    onClicked: Power.caffeine = false
                }
                BarText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: NightLight.on
                    text: String.fromCodePoint(0xF0335)
                    color: Theme.warn
                    onClicked: NightLight.toggle()
                }
                RecordIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    onOpenMenu: Quickshell.execDetached(["qs", "ipc", "call", "recorder", "toggle"])
                }
                BarStats {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Settings.moduleOn("stats", false)
                    onOpenSystem: bar.openDash(3)
                }
                UpdatesModule {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Settings.moduleOn("updates", false) && (!Updates.installed || Updates.count > 0 || Updates.checking)
                }
            }

            // модули плагинов (bar в plugin.json)
            BarGroup {
                id: gPlug
                visible: Plugins.barPlugins.length > 0

                Repeater {
                    model: Plugins.barPlugins

                    Loader {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        source: Plugins.url(modelData, modelData.bar)
                        onLoaded: {
                            if ("plugin" in item) item.plugin = Plugins.api(modelData);
                            if ("screen" in item) item.screen = bar.screen;
                        }
                    }
                }
            }

            BarGroup {
                id: gTray
                visible: Settings.module("tray")
                // «в меню»: в баре только закреплённые значки, остальные — в сетке по кнопке
                Tray {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: items.length > 0
                    items: Settings.trayMode === "menu"
                        ? SystemTray.items.values.filter(i => Settings.trayIsPinned(i.id))
                        : SystemTray.items.values
                    onMenuRequested: (item, icon) => bar.openTrayMenu(item, icon)
                }
                BarText {
                    id: trayButton
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Settings.trayMode === "menu"
                    text: String.fromCodePoint(0xF003B)
                    active: bar.popup === "trayBox"
                    font.pixelSize: Theme.iconSize
                    onClicked: bar.toggle("trayBox", trayButton)
                }
            }

            BarGroup {
                id: gStatus
                PhoneModule {
                    id: phone
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Settings.moduleOn("phone", true) && Rexlink.connected && (Rexlink.online || Settings.moduleOn("phoneOffline", false))
                    onOpenMenu: bar.toggle("phone", phone)
                }
                KeyboardLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Settings.module("keyboard") && Niri.layouts.length > 0
                }
                Volume {
                    id: output
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Settings.module("volume")
                    onOpenMixer: bar.toggle("output", output)
                }
                Volume {
                    id: input
                    anchors.verticalCenter: parent.verticalCenter
                    input: true
                    visible: Settings.module("mic")
                    onOpenMixer: bar.toggle("input", input)
                }
                Network {
                    id: network
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Settings.module("network")
                    onOpenInfo: bar.toggle("network", network)
                }
                Notifications {
                    id: notifications
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Settings.module("notifications")
                    active: bar.popup === "notifications" || count > 0 && !Notifs.dnd
                    onOpenCenter: bar.toggle("notifications", notifications)
                }
                // центр управления
                BarText {
                    id: ccButton
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Settings.moduleOn("control", true)
                    text: String.fromCodePoint(0xF062E)  // tune
                    active: bar.popup === "control"
                    font.pixelSize: Theme.iconSize
                    onClicked: bar.toggle("control", ccButton)
                }
            }
        }
    }

    Popup {
        screen: bar.screen
        open: bar.popup === "trayBox"
        anchorX: bar.popupX
        onDismissed: bar.popup = ""

        TrayBox {
            onActivated: bar.popup = ""
            onMenuRequested: (item, tile) => bar.openTrayMenu(item, tile)
        }
    }

    Popup {
        screen: bar.screen
        open: bar.popup === "cast"
        anchorX: bar.popupX
        onDismissed: bar.popup = ""

        CastHideMenu {}
    }

    Popup {
        screen: bar.screen
        layerName: "quickshell-popup-phone"
        open: bar.popup === "phone"
        anchorX: bar.popupX
        onDismissed: bar.popup = ""

        PhoneMenu { active: bar.popup === "phone" }
    }

    Popup {
        screen: bar.screen
        open: bar.popup === "control"
        anchorX: bar.popupX
        onDismissed: bar.popup = ""

        ControlCenter { active: bar.popup === "control" }
    }

    Popup {
        screen: bar.screen
        open: bar.popup === "calendar"
        anchorX: bar.popupX
        onDismissed: bar.popup = ""

        Dashboard {
            id: dash
            active: bar.popup === "calendar"
            onOpenSettings: {
                bar.popup = "";
                Quickshell.execDetached(["qs", "ipc", "call", "settings", "open"]);
            }
        }
    }

    Popup {
        screen: bar.screen
        open: bar.popup === "output"
        anchorX: bar.popupX
        onDismissed: bar.popup = ""

        Mixer {
            header: true
            meters: bar.popup === "output"
        }
    }

    Popup {
        screen: bar.screen
        open: bar.popup === "input"
        anchorX: bar.popupX
        onDismissed: bar.popup = ""

        Mixer {
            header: true
            input: true
            meters: bar.popup === "input"
        }
    }

    Popup {
        screen: bar.screen
        open: bar.popup === "tray"
        anchorX: bar.popupX
        onDismissed: bar.popup = ""

        TrayMenu {
            menu: bar.trayItem?.menu ?? null
            title: bar.trayItem?.tooltipTitle || bar.trayItem?.title || bar.trayItem?.id || ""
            onClose: bar.popup = ""
        }
    }

    Popup {
        screen: bar.screen
        open: bar.popup === "network"
        anchorX: bar.popupX
        onDismissed: bar.popup = ""

        NetworkInfo { active: bar.popup === "network" }
    }

    Popup {
        screen: bar.screen
        open: bar.popup === "notifications"
        anchorX: bar.popupX
        onDismissed: bar.popup = ""

        NotificationCenter {}
    }

    // этот бар — главный: на нём всплывающие уведомления (чтобы не дублировались на двух мониторах)
    readonly property bool isMain: modelData.name === (Settings.barOn.includes(Settings.primary) ? Settings.primary : Settings.barOn[0])

    // всплывающие уведомления прячем, пока открыт список.
    // Уведомления телефона (Rexlink) — отдельным слоем под остальными: его можно скрыть
    // с демонстрации экрана (Настройки → Телефон)
    NotificationPopups {
        id: popupsMain
        screen: bar.screen
        allowed: bar.isMain && bar.popup !== "notifications"
    }
    NotificationPopups {
        screen: bar.screen
        phone: true
        topOffset: popupsMain.visible ? popupsMain.implicitHeight + 8 : 0
        allowed: bar.isMain && bar.popup !== "notifications"
    }
}
