import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules

// виджеты рабочего стола: слой под окнами на каждом мониторе
// редактирование (Настройки → Виджеты или qs ipc call widgets edit): поверх всего, перетаскивание, «Готово» — сохранить
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: layer

        required property ShellScreen modelData
        screen: modelData

        readonly property var defs: [
            { id: "clock", name: "Clock" },
            { id: "perf", name: "Performance" },
            { id: "weather", name: "Weather" },
            { id: "media", name: "Media" },
            { id: "calendar", name: "Calendar" },
            { id: "notes", name: "Today's notes" },
            { id: "quote", name: "Quote of the day" },
        ]
        // плюс виджеты телефона — по экземпляру на каждый
        readonly property var allDefs: defs.concat(Settings.phoneWidgetIds.map(id => {
            const c = Settings.widgets[id];
            const dev = Rexlink.devFor(c.device);
            return { id, name: `${dev?.name ?? "Phone"} · ${c.variant ?? "full"}` };
        }))
        readonly property var mine: allDefs.filter(d => {
            const c = Settings.widgets[d.id];
            return c && c.enabled && (c.screen === modelData.name || (!Quickshell.screens.some(s => s.name === c.screen) && modelData.name === Settings.primary));
        })

        visible: mine.length > 0
        color: "transparent"
        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.layer: WidgetState.editing ? WlrLayer.Overlay : WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell-widgets"
        WlrLayershell.keyboardFocus: WidgetState.editing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // ── режим редактирования: затемнение и сетка
        Rectangle {
            anchors.fill: parent
            visible: WidgetState.editing
            color: Qt.rgba(0, 0, 0, 0.45)

            Canvas {
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.strokeStyle = "rgba(255,255,255,0.05)";
                    ctx.lineWidth = 1;
                    for (let x = 0; x < width; x += 40) { ctx.beginPath(); ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, height); ctx.stroke(); }
                    for (let y = 0; y < height; y += 40) { ctx.beginPath(); ctx.moveTo(0, y + 0.5); ctx.lineTo(width, y + 0.5); ctx.stroke(); }
                }
            }
        }

        // панель «Готово»
        Rectangle {
            visible: WidgetState.editing
            anchors.horizontalCenter: parent.horizontalCenter
            y: 48
            z: 50
            width: toolbar.implicitWidth + 32
            height: 52
            radius: 16
            color: Theme.surface
            border.width: 1
            border.color: Theme.line

            RowLayout {
                id: toolbar
                anchors.centerIn: parent
                spacing: 14

                Text {
                    text: `${String.fromCodePoint(0xF0B92)}  ${I18n.tr("Drag widgets to move them")} · ${layer.modelData.name}`
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }

                Rectangle {
                    implicitWidth: doneText.implicitWidth + 26
                    implicitHeight: 34
                    radius: 10
                    color: doneArea.containsMouse ? Theme.fgHover : Theme.accent

                    Text {
                        id: doneText
                        anchors.centerIn: parent
                        text: I18n.tr("Done")
                        color: Theme.bg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    MouseArea {
                        id: doneArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WidgetState.editing = false
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            focus: WidgetState.editing
            Keys.onEscapePressed: WidgetState.editing = false
        }

        // область экрана: размеры окна слоя берём отсюда
        Item {
            id: area
            anchors.fill: parent
        }

        // ── сами виджеты
        Repeater {
            model: layer.mine

            Item {
                id: w

                required property var modelData
                readonly property var cfg: Settings.widgets[modelData.id] ?? {}
                readonly property real k: cfg.size ?? 1

                width: card.implicitWidth * k
                height: card.implicitHeight * k
                z: drag.drag.active ? 20 : 1

                function bindPos() {
                    x = Qt.binding(() => Math.max(0, Math.min(area.width - w.width, w.cfg.x ?? 80)));
                    y = Qt.binding(() => Math.max(0, Math.min(area.height - w.height, w.cfg.y ?? 80)));
                }
                Component.onCompleted: bindPos()

                DeskCard {
                    id: card
                    scale: w.k
                    transformOrigin: Item.TopLeft
                    background: w.cfg.background ?? true

                    Loader {
                        sourceComponent: w.modelData.id.startsWith("phone-") ? phoneC : ({
                            clock: clockC, perf: perfC, weather: weatherC, media: mediaC,
                            calendar: calendarC, notes: notesC, quote: quoteC,
                        })[w.modelData.id]
                        onLoaded: if (w.modelData.id.startsWith("phone-")) {
                            item.device = Qt.binding(() => w.cfg.device ?? "");
                            item.variant = Qt.binding(() => w.cfg.variant ?? "full");
                        }
                    }
                }

                // рамка и подпись в режиме редактирования
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -6
                    visible: WidgetState.editing
                    radius: 22
                    color: drag.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"
                    border.width: 2
                    border.color: drag.drag.active ? Theme.accent : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)

                    Rectangle {
                        x: 12
                        y: -12
                        width: tag.implicitWidth + 16
                        height: 22
                        radius: 7
                        color: Theme.accent

                        Text {
                            id: tag
                            anchors.centerIn: parent
                            text: I18n.tr(w.modelData.name)
                            color: Theme.bg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                            font.bold: true
                        }
                    }
                }

                MouseArea {
                    id: drag
                    anchors.fill: parent
                    enabled: WidgetState.editing
                    hoverEnabled: true
                    cursorShape: drag.drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    drag.target: w
                    drag.minimumX: 0
                    drag.minimumY: 0
                    drag.maximumX: area.width - w.width
                    drag.maximumY: area.height - w.height
                    onReleased: {
                        // примагничивание к сетке 20 px
                        const sx = Math.round(w.x / 20) * 20, sy = Math.round(w.y / 20) * 20;
                        const all = JSON.parse(JSON.stringify(Settings.widgets));
                        all[w.modelData.id] = Object.assign({}, all[w.modelData.id], { x: sx, y: sy });
                        Settings.widgets = all;
                        w.bindPos();
                    }
                }
            }
        }

        Component { id: clockC; DeskClock { cfg: Settings.widgets.clock ?? {} } }
        Component { id: perfC; PerfWidget { width: 460; active: true } }
        Component { id: weatherC; DeskWeather {} }
        Component { id: mediaC; MediaWidget { width: 400; artSize: 96; active: true } }
        Component { id: calendarC; CalendarView { active: true } }
        Component { id: notesC; DeskNotes {} }
        Component { id: quoteC; DeskQuote {} }
        Component { id: phoneC; DeskPhone {} }
    }
}
