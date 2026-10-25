import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.services

// «Динамический остров» — центр бара в стиле «Остров»: чёрная капсула с часами, которая сама показывает,
// что происходит (звонок, запись экрана, таймер, копирование и передача файлов, музыка), и по наведению
// раскрывается в карточку с подробностями и кнопками. Своё окно поверх бара: прозрачное, щелчки ловит только
// сама капсула (mask), поэтому окна под ним работают как обычно
PanelWindow {
    id: win

    required property var bar

    screen: bar.screen
    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    implicitWidth: 460
    implicitHeight: Theme.barHeight + bar.gap + 230
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-island"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: shape }

    // ── цвета: капсула всегда тёмная, как у телефона
    readonly property color bg: "#050505"
    readonly property color fg: "#f2f2f2"
    readonly property color dim: "#8e8e93"
    readonly property color btn: "#232325"
    readonly property color btnHover: "#323236"
    readonly property color red: "#ff5f57"
    readonly property color green: "#33c759"
    readonly property color orange: "#ff9f0a"

    // ── что сейчас главное
    readonly property var player: Media.current
    readonly property bool playing: player?.isPlaying ?? false
    readonly property var transfers: Rexlink.transfers.filter(t => t.state === "active")
    readonly property var jobs: Jobs.list
    readonly property var busyList: jobs.map(j => ({ title: j.title, done: j.done, total: j.total, cancel: j.cancel }))
        .concat(transfers.map(t => ({ title: `${t.dir === "in" ? "↓" : "↑"} ${t.name}`, done: t.done, total: t.size, cancel: () => Rexlink.transferCancel(t.fid) })))
    readonly property real busyPart: {
        const d = busyList.reduce((a, j) => a + (j.done ?? 0), 0), t = busyList.reduce((a, j) => a + (j.total ?? 0), 0);
        return t > 0 ? Math.min(1, d / t) : 0;
    }
    readonly property string kind: Rexlink.ringing ? "call"
        : Recorder.countdown > 0 ? "countdown"
        : Recorder.recording ? "record"
        : Timers.justFinished ? "timerDone"
        : Timers.active ? "timer"
        : busyList.length > 0 ? "busy"
        : playing ? "media"
        : "clock"
    // звонок и конец таймера раскрывают остров сами
    readonly property bool urgent: kind === "call" || kind === "timerDone"

    // ── раскрытие: по наведению (с задержкой, чтобы не мигал), и на пару секунд — когда что-то началось
    property bool expanded: false
    property bool peek: false
    readonly property bool open: expanded || urgent || peek
    Timer { id: openT; interval: 140; onTriggered: win.expanded = true }
    Timer { id: closeT; interval: 280; onTriggered: win.expanded = false }
    Timer { id: peekT; interval: 2600; onTriggered: win.peek = false }
    onKindChanged: if (kind !== "clock" && kind !== "media" && !expanded) { peek = true; peekT.restart(); }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    component IconBtn: Rectangle {
        id: ib
        property int glyph: 0
        property color tint: win.fg
        property color fill: win.btn
        property int size: 38
        signal clicked
        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        color: ibArea.pressed ? Qt.lighter(fill, 1.35) : ibArea.containsMouse ? Qt.lighter(fill, 1.18) : fill
        scale: ibArea.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(ib.glyph)
            color: ib.tint
            font.family: Theme.font
            font.pixelSize: ib.size * 0.42
        }
        MouseArea {
            id: ibArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { Sounds.click(); ib.clicked(); }
        }
    }
    component TextBtn: Rectangle {
        id: tb
        property string text
        property color tint: win.fg
        property color fill: win.btn
        signal clicked
        implicitWidth: tbText.implicitWidth + 26
        implicitHeight: 34
        radius: 17
        color: tbArea.pressed ? Qt.lighter(fill, 1.35) : tbArea.containsMouse ? Qt.lighter(fill, 1.18) : fill
        Text {
            id: tbText
            anchors.centerIn: parent
            text: tb.text
            color: tb.tint
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
        MouseArea {
            id: tbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { Sounds.click(); tb.clicked(); }
        }
    }
    component Label: Text {
        color: win.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        elide: Text.ElideRight
    }
    // тонкая полоска хода
    component ProgressLine: Rectangle {
        property real part: 0
        property color tint: Theme.accent
        implicitHeight: 5
        radius: 3
        color: "#2c2c2e"
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.part))
            height: parent.height
            radius: 3
            color: parent.tint
        }
    }

    Rectangle {
        id: shape

        readonly property int fullW: win.kind === "media" || win.kind === "busy" ? 420 : 380
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.bar.gap
        width: win.open ? fullW : compact.implicitWidth + 32
        height: win.open ? full.implicitHeight + 36 : Theme.barHeight
        radius: win.open ? 28 : height / 2
        color: win.bg
        clip: true

        Behavior on width { NumberAnimation { duration: 360; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on height { NumberAnimation { duration: 360; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        HoverHandler {
            id: hover
            onHoveredChanged: {
                if (hovered) { closeT.stop(); openT.restart(); }
                else { openT.stop(); closeT.restart(); }
            }
        }

        // ══════════ капсула
        Row {
            id: compact
            anchors.centerIn: parent
            spacing: 8
            opacity: win.open ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 140 } }

            // значок слева
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.kind === "record" || win.kind === "countdown"
                width: 9
                height: 9
                radius: 5
                color: win.red
            }
            ClippingRectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.kind === "media" && !!win.player?.trackArtUrl
                width: Theme.barHeight - 12
                height: width
                radius: 6
                color: win.btn
                Image {
                    anchors.fill: parent
                    source: win.kind === "media" ? (win.player?.trackArtUrl ?? "") : ""
                    sourceSize.width: 64
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            Text {
                readonly property int glyph: ({ call: 0xF03F2, timer: 0xF13AB, timerDone: 0xF0020, busy: 0xF01DA,
                                                media: win.player?.trackArtUrl ? 0 : 0xF075A })[win.kind] ?? 0
                anchors.verticalCenter: parent.verticalCenter
                visible: glyph !== 0
                text: glyph ? String.fromCodePoint(glyph) : ""
                color: win.kind === "call" ? win.green : win.kind === "timer" || win.kind === "timerDone" ? win.orange : Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.iconSize
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 220)
                font.pixelSize: Theme.fontSize
                font.bold: win.kind === "clock"
                text: win.kind === "call" ? (Rexlink.call.name || Rexlink.call.number || I18n.tr("Incoming call"))
                    : win.kind === "countdown" ? String(Recorder.countdown)
                    : win.kind === "record" ? Recorder.elapsedText
                    : win.kind === "timerDone" ? I18n.tr("Time is up")
                    : win.kind === "timer" ? Timers.fmt(Timers.remaining)
                    : win.kind === "busy" ? `${Math.round(win.busyPart * 100)}%`
                    : win.kind === "media" ? (win.player?.trackTitle ?? "")
                    : Qt.locale(I18n.locale).toString(clock.date, "HH:mm")
            }
            // справа: погода у часов, «играет» у музыки
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.kind === "clock" && Weather.configured && !!Weather.current
                text: Weather.current ? `${Weather.info(Weather.current.code, Weather.current.isDay).icon} ${Math.round(Weather.current.temp)}°` : ""
                color: win.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.kind === "media"
                text: String.fromCodePoint(0xF0EA2)
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.iconSize - 1
            }
            // второе дело — точкой справа (например, играет музыка, пока идёт запись)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.kind !== "media" && win.kind !== "clock" && win.playing
                width: 7
                height: 7
                radius: 4
                color: Theme.accent
            }
        }

        // ══════════ раскрытый
        Item {
            id: full
            x: 18
            y: 18
            width: shape.fullW - 36
            implicitHeight: content.implicitHeight
            opacity: win.open ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            ColumnLayout {
                id: content
                width: parent.width
                spacing: 14

                // ── часы: время, дата, погода, быстрые таймеры
                ColumnLayout {
                    visible: win.kind === "clock"
                    Layout.fillWidth: true
                    spacing: 14
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                text: Qt.locale(I18n.locale).toString(clock.date, "HH:mm")
                                font.pixelSize: 34
                                font.bold: true
                            }
                            Label {
                                Layout.fillWidth: true
                                text: Qt.locale(I18n.locale).toString(clock.date, "dddd, d MMMM")
                                color: win.dim
                                font.pixelSize: Theme.fontSize - 1
                            }
                        }
                        ColumnLayout {
                            visible: Weather.configured && !!Weather.current
                            spacing: 0
                            Label {
                                Layout.alignment: Qt.AlignRight
                                text: Weather.current ? `${Weather.info(Weather.current.code, Weather.current.isDay).icon}  ${Math.round(Weather.current.temp)}°` : ""
                                font.pixelSize: 24
                            }
                            Label {
                                Layout.alignment: Qt.AlignRight
                                text: Weather.current ? Weather.info(Weather.current.code, Weather.current.isDay).text : ""
                                color: win.dim
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: String.fromCodePoint(0xF13AB)
                            color: win.orange
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize + 2
                        }
                        Repeater {
                            model: [1, 5, 10, 25]
                            TextBtn {
                                required property int modelData
                                Layout.fillWidth: true
                                text: `${modelData} ${I18n.ru ? "мин" : "min"}`
                                onClicked: Timers.start(modelData)
                            }
                        }
                        IconBtn {
                            glyph: 0xF00ED
                            size: 34
                            onClicked: win.bar.openDash(0)
                        }
                    }
                }

                // ── музыка
                RowLayout {
                    visible: win.kind === "media"
                    Layout.fillWidth: true
                    spacing: 14
                    ClippingRectangle {
                        implicitWidth: 72
                        implicitHeight: 72
                        radius: 14
                        color: win.btn
                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF075A)
                            color: win.dim
                            font.family: Theme.font
                            font.pixelSize: 28
                        }
                        Image {
                            anchors.fill: parent
                            source: win.kind === "media" ? (win.player?.trackArtUrl ?? "") : ""
                            sourceSize.width: 144
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label {
                            Layout.fillWidth: true
                            text: win.player?.trackTitle ?? ""
                            font.bold: true
                        }
                        Label {
                            Layout.fillWidth: true
                            text: win.player?.trackArtist || win.player?.identity || ""
                            color: win.dim
                            font.pixelSize: Theme.fontSize - 1
                        }
                        RowLayout {
                            Layout.topMargin: 4
                            spacing: 10
                            IconBtn {
                                glyph: 0xF04AE
                                size: 34
                                fill: "transparent"
                                opacity: Media.canPrevious(win.player) ? 1 : 0.4
                                onClicked: Media.previous(win.player)
                            }
                            IconBtn {
                                glyph: win.playing ? 0xF03E4 : 0xF040A
                                size: 40
                                fill: win.fg
                                tint: win.bg
                                onClicked: win.player?.togglePlaying()
                            }
                            IconBtn {
                                glyph: 0xF04AD
                                size: 34
                                fill: "transparent"
                                opacity: Media.canNext(win.player) ? 1 : 0.4
                                onClicked: Media.next(win.player)
                            }
                        }
                    }
                }

                // ── таймер
                ColumnLayout {
                    visible: win.kind === "timer" || win.kind === "timerDone"
                    Layout.fillWidth: true
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: String.fromCodePoint(0xF13AB)
                            color: win.orange
                            font.family: Theme.font
                            font.pixelSize: 26
                        }
                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: win.kind === "timerDone" ? I18n.tr("Time is up") : Timers.fmt(Timers.remaining)
                            color: win.kind === "timerDone" ? win.orange : win.fg
                            font.pixelSize: 34
                            font.bold: true
                        }
                    }
                    ProgressLine {
                        visible: win.kind === "timer"
                        Layout.fillWidth: true
                        part: Timers.progress
                        tint: win.orange
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        TextBtn { text: I18n.ru ? "+1 мин" : "+1 min"; onClicked: Timers.add(1) }
                        TextBtn { text: I18n.ru ? "+5 мин" : "+5 min"; onClicked: Timers.add(5) }
                        Item { Layout.fillWidth: true }
                        IconBtn {
                            visible: win.kind === "timer"
                            glyph: Timers.paused ? 0xF040A : 0xF03E4
                            fill: win.orange
                            tint: win.bg
                            onClicked: Timers.paused ? Timers.resume() : Timers.pause()
                        }
                        IconBtn {
                            glyph: 0xF0156
                            onClicked: { Timers.cancel(); Timers.justFinished = false; }
                        }
                    }
                }

                // ── запись экрана
                ColumnLayout {
                    visible: win.kind === "record" || win.kind === "countdown"
                    Layout.fillWidth: true
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle {
                            width: 12
                            height: 12
                            radius: 6
                            color: win.red
                        }
                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            text: win.kind === "countdown" ? I18n.tr("Recording starts in") : I18n.tr(Recorder.paused ? "Recording paused" : "Screen recording")
                            color: win.dim
                        }
                        Label {
                            text: win.kind === "countdown" ? String(Recorder.countdown) : Recorder.elapsedText
                            font.pixelSize: 28
                            font.bold: true
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        TextBtn {
                            text: I18n.tr("Folder")
                            onClicked: Recorder.openFolder()
                        }
                        Item { Layout.fillWidth: true }
                        IconBtn {
                            visible: win.kind === "record"
                            glyph: Recorder.paused ? 0xF040A : 0xF03E4
                            onClicked: Recorder.togglePause()
                        }
                        IconBtn {
                            glyph: 0xF04DB
                            fill: win.red
                            tint: "white"
                            onClicked: Recorder.stop()
                        }
                    }
                }

                // ── копирование и передача файлов
                ColumnLayout {
                    visible: win.kind === "busy"
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: win.kind === "busy" ? win.busyList.slice(0, 3) : []
                        ColumnLayout {
                            id: job
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: job.modelData.title
                                    font.pixelSize: Theme.fontSize - 1
                                }
                                Label {
                                    text: job.modelData.total ? `${Math.round(100 * job.modelData.done / job.modelData.total)}%` : "…"
                                    color: win.dim
                                    font.pixelSize: Theme.fontSize - 1
                                }
                                IconBtn {
                                    visible: !!job.modelData.cancel
                                    glyph: 0xF0156
                                    size: 28
                                    onClicked: job.modelData.cancel()
                                }
                            }
                            ProgressLine {
                                Layout.fillWidth: true
                                part: job.modelData.total ? job.modelData.done / job.modelData.total : 0
                            }
                        }
                    }
                }

                // ── звонок
                ColumnLayout {
                    visible: win.kind === "call"
                    Layout.fillWidth: true
                    spacing: 14
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Rectangle {
                            implicitWidth: 46
                            implicitHeight: 46
                            radius: 23
                            color: win.btn
                            Text {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xF0004)
                                color: win.fg
                                font.family: Theme.font
                                font.pixelSize: 22
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                Layout.fillWidth: true
                                text: Rexlink.call.name || Rexlink.call.number || I18n.tr("Incoming call")
                                font.pixelSize: Theme.fontSize + 3
                                font.bold: true
                            }
                            Label {
                                Layout.fillWidth: true
                                text: Rexlink.call.name ? (Rexlink.call.number ?? "") : I18n.tr("Incoming call")
                                color: win.dim
                                font.pixelSize: Theme.fontSize - 1
                            }
                        }
                        IconBtn {
                            glyph: 0xF0581
                            onClicked: Rexlink.callAction("silence")
                        }
                        IconBtn {
                            glyph: 0xF03F2
                            fill: win.red
                            tint: "white"
                            rotation: 135
                            onClicked: Rexlink.callAction("reject")
                        }
                        IconBtn {
                            glyph: 0xF03F2
                            fill: win.green
                            tint: "white"
                            onClicked: Rexlink.callAction("accept")
                        }
                    }
                }
            }
        }
    }
}
