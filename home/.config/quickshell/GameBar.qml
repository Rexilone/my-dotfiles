import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.services
import qs.modules

// игровая панель (Super+G) поверх игры, как Xbox Game Bar: производительность, музыка, звук программ,
// сообщения с ПК и телефона, снимок экрана, клип последних секунд, запись, микрофон, «Не беспокоить».
// Своё окно на верхнем слое (поверх полноэкранных окон); Esc, щелчок мимо или Super+G — закрыть
Scope {
    id: gb

    property bool open: false
    property bool shown: false     // окно живёт, пока доигрывает анимация закрытия
    property Item view: null       // содержимое открытого окна (для снимков панели в тестах)
    onOpenChanged: {
        if (open) {
            closeT.stop();
            shown = true;
        } else closeT.restart();
    }
    Timer {
        id: closeT
        interval: 220
        onTriggered: gb.shown = false
    }

    function close() { open = false; }
    // действие после закрытия: снимок и запись без самой панели
    function after(fn, ms) {
        open = false;
        laterT.fn = fn;
        laterT.interval = ms ?? 350;
        laterT.restart();
    }
    Timer {
        id: laterT
        property var fn: null
        onTriggered: fn?.()
    }

    IpcHandler {
        target: "gamebar"
        // qs ipc call gamebar toggle
        function toggle(): void { gb.open = !gb.open; }
        function hide(): void { gb.open = false; }
    }

    LazyLoader {
        active: gb.shown

        PanelWindow {
            id: win

            screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) ?? Quickshell.screens[0]
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-gamebar"
            WlrLayershell.keyboardFocus: gb.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            readonly property var game: GameMode.game ?? Niri.focusedWindow
            readonly property string sysId: `gamebar-${Math.random()}`
            Component.onCompleted: {
                SysStats.need(sysId, true);
                gb.view = root;
            }
            Component.onDestruction: {
                SysStats.need(sysId, false);
                gb.view = null;
            }

            // история нагрузки для графиков (последние 60 замеров)
            property var hist: ({ cpu: [], gpu: [], ram: [] })
            Connections {
                target: SysStats
                function onCpuChanged() {
                    const push = (a, v) => a.concat([v]).slice(-60);
                    win.hist = {
                        cpu: push(win.hist.cpu, SysStats.cpu),
                        gpu: push(win.hist.gpu, SysStats.gpu),
                        ram: push(win.hist.ram, SysStats.ramTotal ? SysStats.ramUsed / SysStats.ramTotal : 0),
                    };
                }
            }

            // затемнение
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.5)
                opacity: gb.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: gb.close()
                }
            }

            Item {
                id: root
                anchors.fill: parent
                focus: true
                opacity: gb.open ? 1 : 0
                scale: gb.open ? 1 : 0.98
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Keys.onEscapePressed: gb.close()

                // ── общие кусочки
                component Card: Rectangle {
                    id: card
                    default property alias body: inner.data
                    property string title: ""
                    property int glyph: 0
                    radius: 22
                    color: Theme.panel
                    border.width: 1
                    border.color: Theme.surfaceHi2
                    implicitHeight: head.implicitHeight + inner.implicitHeight + 54
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }
                    RowLayout {
                        id: head
                        x: 20
                        y: 18
                        spacing: 10
                        Text {
                            text: card.glyph ? String.fromCodePoint(card.glyph) : ""
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize + 1
                        }
                        Text {
                            text: card.title
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 1
                            font.bold: true
                        }
                    }
                    ColumnLayout {
                        id: inner
                        x: 20
                        anchors.top: head.bottom
                        anchors.topMargin: 14
                        width: card.width - 40
                        spacing: 14
                    }
                }
                component BarBtn: Rectangle {
                    id: bb
                    property int glyph
                    property string tip
                    property bool on: false
                    property color tint: Theme.accent
                    signal clicked
                    implicitWidth: 46
                    implicitHeight: 46
                    radius: 23
                    color: on ? tint : bbArea.pressed ? Theme.surfaceHi2 : bbArea.containsMouse ? Theme.surfaceHi : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(bb.glyph)
                        color: bb.on ? Theme.bg : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.iconSize + 4
                    }
                    Rectangle {
                        visible: bbArea.containsMouse && bb.tip !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 10
                        width: tipText.implicitWidth + 18
                        height: 28
                        radius: 8
                        color: Theme.surfaceHi2
                        z: 10
                        Text {
                            id: tipText
                            anchors.centerIn: parent
                            text: bb.tip
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                    MouseArea {
                        id: bbArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Sounds.click(); bb.clicked(); }
                    }
                }
                // показатель с графиком
                component Stat: ColumnLayout {
                    id: st
                    property string label
                    property string value
                    property string sub
                    property var points: []
                    property color tint: Theme.accent
                    Layout.fillWidth: true
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: st.label
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            text: st.sub
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            text: st.value
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 4
                            font.bold: true
                        }
                    }
                    Canvas {
                        id: graph
                        Layout.fillWidth: true
                        implicitHeight: 38
                        onWidthChanged: requestPaint()
                        Connections {
                            target: st
                            function onPointsChanged() { graph.requestPaint(); }
                        }
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const p = st.points, n = 60;
                            if (p.length < 2) return;
                            const x = i => width * (i + n - p.length) / (n - 1);
                            const y = v => height - 2 - (height - 4) * Math.max(0, Math.min(1, v));
                            ctx.beginPath();
                            ctx.moveTo(x(0), height);
                            for (let i = 0; i < p.length; i++) ctx.lineTo(x(i), y(p[i]));
                            ctx.lineTo(x(p.length - 1), height);
                            ctx.closePath();
                            ctx.fillStyle = Qt.rgba(st.tint.r, st.tint.g, st.tint.b, 0.18);
                            ctx.fill();
                            ctx.beginPath();
                            for (let i = 0; i < p.length; i++) i ? ctx.lineTo(x(i), y(p[i])) : ctx.moveTo(x(i), y(p[i]));
                            ctx.strokeStyle = st.tint;
                            ctx.lineWidth = 2;
                            ctx.stroke();
                        }
                    }
                }

                // ══════════ верхняя панель: игра, время, действия
                Rectangle {
                    id: top
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: gb.open ? 28 : 8
                    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    width: topRow.implicitWidth + 28
                    height: 66
                    radius: 33
                    color: Theme.panel
                    border.width: 1
                    border.color: Theme.surfaceHi2
                    MouseArea { anchors.fill: parent }

                    RowLayout {
                        id: topRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            Layout.leftMargin: 8
                            text: String.fromCodePoint(0xF0297)
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize + 6
                        }
                        ColumnLayout {
                            Layout.rightMargin: 10
                            spacing: 0
                            Text {
                                Layout.maximumWidth: 260
                                text: win.game?.title || I18n.tr("Game bar")
                                elide: Text.ElideRight
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }
                            Text {
                                text: Qt.locale(I18n.locale).toString(clock.date, "HH:mm") + (GameMode.active ? `   ·   ${I18n.tr("game mode")}` : "")
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 2
                            }
                            SystemClock {
                                id: clock
                                precision: SystemClock.Minutes
                            }
                        }
                        Rectangle { implicitWidth: 1; implicitHeight: 30; color: Theme.surfaceHi2 }

                        BarBtn {
                            glyph: 0xF0E51
                            tip: I18n.tr("Screenshot")
                            onClicked: gb.after(() => {
                                Sounds.play("shutter");
                                Quickshell.execDetached(["niri", "msg", "action", "screenshot-screen"]);
                            })
                        }
                        BarBtn {
                            glyph: 0xF0FCE
                            tip: Recorder.replayActive ? `${I18n.tr("Save the last")} ${Recorder.replaySeconds} ${I18n.ru ? "с" : "s"}` : I18n.tr("Turn on clip recording")
                            on: Recorder.replayActive
                            onClicked: {
                                if (Recorder.replayActive) {
                                    Recorder.saveReplay();
                                    Sounds.play("record");
                                } else Recorder.toggleReplay();
                            }
                        }
                        BarBtn {
                            glyph: Recorder.recording ? 0xF04DB : 0xF044B
                            tip: I18n.tr(Recorder.recording ? "Stop recording" : "Record the screen")
                            on: Recorder.recording
                            tint: Theme.urgent
                            onClicked: Recorder.recording ? Recorder.stop() : gb.after(() => Recorder.start(), 300)
                        }
                        Rectangle { implicitWidth: 1; implicitHeight: 30; color: Theme.surfaceHi2 }
                        BarBtn {
                            readonly property var mic: Pipewire.defaultAudioSource
                            glyph: mic?.audio?.muted ? 0xF036D : 0xF036C
                            tip: I18n.tr(mic?.audio?.muted ? "Microphone is off" : "Microphone is on")
                            on: !!mic?.audio?.muted
                            tint: Theme.urgent
                            onClicked: if (mic?.audio) mic.audio.muted = !mic.audio.muted
                        }
                        BarBtn {
                            glyph: Notifs.dnd ? 0xF009B : 0xF009A
                            tip: I18n.tr("Do not disturb")
                            on: Notifs.dnd
                            onClicked: Notifs.toggleDnd()
                        }
                        BarBtn {
                            visible: Overlay.installed
                            glyph: 0xF04C5
                            tip: I18n.tr(Overlay.enabled ? "FPS in the game (MangoHud)" : "FPS: turn on the overlay in Settings → Games")
                            on: Overlay.enabled && (Settings.overlay?.visible ?? true)
                            onClicked: {
                                if (Overlay.enabled) Settings.setOverlay("visible", !(Settings.overlay?.visible ?? true));
                                else { gb.close(); Ui.openSettings("games"); }
                            }
                        }
                        Rectangle { implicitWidth: 1; implicitHeight: 30; color: Theme.surfaceHi2 }
                        BarBtn {
                            glyph: 0xF0156
                            tip: "Esc"
                            onClicked: gb.close()
                        }
                    }
                }

                // ══════════ слева: производительность
                Card {
                    x: gb.open ? 32 : 12
                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    y: 120
                    width: 340
                    title: I18n.tr("Performance")
                    glyph: 0xF04C5

                    Stat {
                        label: "CPU"
                        value: `${Math.round(SysStats.cpu * 100)}%`
                        sub: SysStats.cpuTemp ? `${Math.round(SysStats.cpuTemp)}°C` : ""
                        points: win.hist.cpu
                    }
                    Stat {
                        label: "GPU"
                        value: `${Math.round(SysStats.gpu * 100)}%`
                        sub: [SysStats.gpuTemp ? `${Math.round(SysStats.gpuTemp)}°C` : "",
                              SysStats.vramTotal ? `${(SysStats.vramUsed / 1073741824).toFixed(1)}/${Math.round(SysStats.vramTotal / 1073741824)} GB` : ""].filter(x => x).join("  ·  ")
                        points: win.hist.gpu
                        tint: Qt.hsla(0.58, 0.6, Theme.isLight ? 0.45 : 0.68, 1)
                    }
                    Stat {
                        label: "RAM"
                        value: `${SysStats.gb(SysStats.ramUsed)} GB`
                        sub: SysStats.ramTotal ? `/ ${SysStats.gb(SysStats.ramTotal)}` : ""
                        points: win.hist.ram
                        tint: Qt.hsla(0.38, 0.55, Theme.isLight ? 0.45 : 0.65, 1)
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !Overlay.enabled
                        wrapMode: Text.Wrap
                        text: I18n.tr("FPS is shown inside the game by MangoHud: Settings → Games")
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }

                // ══════════ слева снизу: музыка
                Card {
                    visible: !!Media.current
                    x: gb.open ? 32 : 12
                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 32
                    width: 440
                    title: I18n.tr("Music")
                    glyph: 0xF075A

                    MediaWidget {
                        Layout.fillWidth: true
                        artSize: 84
                        active: gb.open
                    }
                }

                // ══════════ справа: звук
                Card {
                    id: soundCard
                    anchors.right: parent.right
                    anchors.rightMargin: gb.open ? 32 : 12
                    Behavior on anchors.rightMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    y: 120
                    width: 380
                    title: I18n.tr("Sound")
                    glyph: 0xF057E

                    Mixer {
                        Layout.fillWidth: true
                        meters: gb.open
                    }
                }

                // ══════════ справа снизу: сообщения с ПК и телефона
                Card {
                    id: chat
                    anchors.right: parent.right
                    anchors.rightMargin: gb.open ? 32 : 12
                    Behavior on anchors.rightMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    anchors.top: soundCard.bottom
                    anchors.topMargin: 16
                    width: 380
                    title: I18n.tr("Messages")
                    glyph: 0xF0369

                    // последние уведомления: компьютер и телефон вместе, новые сверху
                    readonly property var items: Notifs.list.slice(-6).reverse().map(n => ({ pc: true, n, app: n.appName, title: n.summary, body: n.body, icon: Notifs.iconFor(n) }))
                        .concat((Rexlink.notifs ?? []).slice(0, 6).map(p => ({ pc: false, p, app: p.app ?? "", title: p.title ?? "", body: p.text ?? "", icon: "" })))
                        .slice(0, 6)

                    Text {
                        visible: chat.items.length === 0
                        text: I18n.tr("No new messages")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Repeater {
                        model: chat.items
                        Rectangle {
                            id: msg
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: msgCol.implicitHeight + 22
                            radius: 14
                            color: Theme.surface
                            RowLayout {
                                id: msgRow
                                x: 12
                                y: 11
                                width: parent.width - 24
                                spacing: 12
                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    radius: 10
                                    color: Theme.surfaceHi
                                    IconImage {
                                        anchors.centerIn: parent
                                        visible: msg.modelData.icon !== ""
                                        implicitSize: 22
                                        source: msg.modelData.icon
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: msg.modelData.icon === ""
                                        text: String.fromCodePoint(msg.modelData.pc ? 0xF009A : 0xF011C)
                                        color: Theme.accent
                                        font.family: Theme.font
                                        font.pixelSize: Theme.iconSize
                                    }
                                }
                                ColumnLayout {
                                    id: msgCol
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        Layout.fillWidth: true
                                        text: msg.modelData.app + (msg.modelData.pc ? "" : `   ·   ${I18n.tr("phone")}`)
                                        elide: Text.ElideRight
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 3
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: msg.modelData.title
                                        elide: Text.ElideRight
                                        color: Theme.fg
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 1
                                        font.bold: true
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: msg.modelData.body.replace(/<[^>]+>/g, "")
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        color: Theme.muted
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 2
                                    }
                                    // действия уведомления с ПК («Ответить», «Открыть»…)
                                    Flow {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        visible: msg.modelData.pc && (msg.modelData.n.actions?.length ?? 0) > 0
                                        spacing: 6
                                        Repeater {
                                            model: msg.modelData.pc ? (msg.modelData.n.actions ?? []).slice(0, 3) : []
                                            Rectangle {
                                                id: act
                                                required property var modelData
                                                width: actText.implicitWidth + 20
                                                height: 28
                                                radius: 14
                                                color: actArea.containsMouse ? Theme.surfaceHi2 : Theme.surfaceHi
                                                Text {
                                                    id: actText
                                                    anchors.centerIn: parent
                                                    text: act.modelData.text
                                                    color: Theme.fg
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontSize - 3
                                                }
                                                MouseArea {
                                                    id: actArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: { act.modelData.invoke(); gb.close(); }
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
        }
    }
}
