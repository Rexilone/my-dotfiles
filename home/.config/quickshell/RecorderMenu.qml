import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.services

// меню записи экрана: qs ipc call recorder toggle (Alt+Z)
// Enter — начать/остановить, P — пауза, R — сохранить повтор, Esc — закрыть
PanelWindow {
    id: root

    property bool open: false
    property bool shown: false

    readonly property color card: Theme.surface
    readonly property color cardHover: Theme.surfaceHi
    readonly property color line: Theme.surfaceHi2
    readonly property color red: Theme.rec

    readonly property bool sysOn: Recorder.audio === "system" || Recorder.audio === "both"
    readonly property bool micOn: Recorder.audio === "mic" || Recorder.audio === "both"

    function setAudio(sys, mic) {
        Recorder.audio = sys && mic ? "both" : sys ? "system" : mic ? "mic" : "none";
    }

    onOpenChanged: {
        if (open) {
            targetScreen = Settings.activeScreen();
            hideTimer.stop();
            shown = true;
            keys.forceActiveFocus();
        } else {
            hideTimer.restart();
        }
    }

    function recordAction() {
        if (Recorder.recording || Recorder.countdown > 0) {
            Recorder.stop();
        } else {
            open = false;
            startDelay.start();  // меню успевает спрятаться и не попадает в запись
        }
    }

    Timer {
        id: startDelay
        interval: Theme.animSlow + 80
        onTriggered: Recorder.start()
    }

    Timer {
        id: hideTimer
        interval: Theme.animSlow
        onTriggered: root.shown = false
    }

    IpcHandler {
        target: "recorder"

        function toggle(): void { root.open = !root.open; }
        function hide(): void { root.open = false; }
        function record(): void { Recorder.toggle(); }
        function pause(): void { Recorder.togglePause(); }
        function replay(): void { Recorder.toggleReplay(); }
        function saveReplay(): void { Recorder.saveReplay(); }
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    // открывается на мониторе, где сейчас курсор/фокус
    property var targetScreen: Settings.activeScreen()
    screen: targetScreen
    visible: shown
    color: "transparent"
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    // размытие только под карточкой (Персонализация → Прозрачность)
    BackgroundEffect.blurRegion: Theme.blurOn ? blurReg : null
    Region {
        id: blurReg
        item: bg
        radius: bg.radius
    }
    WlrLayershell.namespace: "quickshell-recorder"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.open ? 0.45 : 0

        Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }
    }

    Item {
        id: keys
        focus: true

        Keys.onPressed: event => {
            const k = event.key;
            if (k === Qt.Key_Escape) root.open = false;
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.recordAction();
            else if (k === Qt.Key_P) Recorder.togglePause();
            else if (k === Qt.Key_R) Recorder.saveReplay();
            else return;
            event.accepted = true;
        }
    }

    // ── компоненты ────────────────────────────────────────

    component Caption: Text {
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
        font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
    }

    component Switch: Rectangle {
        property bool checked: false
        implicitWidth: 34
        implicitHeight: 20
        radius: 10
        color: checked ? Theme.fg : Theme.surfaceHi2

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Rectangle {
            x: parent.checked ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: parent.checked ? Theme.bg : Theme.dim

            Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutBack } }
        }
    }

    // компактные «пилюли»-переключатели
    component Pills: Rectangle {
        id: pills
        property var options: []
        property var current
        signal picked(var value)

        implicitWidth: pillRow.implicitWidth + 6
        implicitHeight: 30
        radius: 10
        color: root.card

        // подсветка выбранного значения, плавно переезжает
        Rectangle {
            id: pillHighlight
            property Item target: null
            x: target ? target.x + 3 : 3
            width: target ? target.width : 0
            y: 3
            height: parent.height - 6
            radius: 8
            color: Theme.surfaceHi2

            Behavior on x { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
        }

        Row {
            id: pillRow
            x: 3
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: pills.options

                Item {
                    id: pill
                    required property var modelData
                    readonly property bool selected: pills.current === modelData.value

                    width: pillText.implicitWidth + 20
                    height: 24
                    onSelectedChanged: if (selected) pillHighlight.target = pill
                    Component.onCompleted: if (selected) pillHighlight.target = pill

                    Text {
                        id: pillText
                        anchors.centerIn: parent
                        text: I18n.tr(pill.modelData.label)
                        color: pill.selected ? Theme.fg : pillArea.containsMouse ? Theme.muted : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }

                    MouseArea {
                        id: pillArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pills.picked(pill.modelData.value)
                    }
                }
            }
        }
    }

    // круглая иконка-переключатель
    component IconToggle: Rectangle {
        id: it
        property string icon: ""
        property bool checked: false
        signal toggled

        implicitWidth: 30
        implicitHeight: 30
        radius: 10
        color: checked ? Theme.surfaceHi2 : itArea.containsMouse ? root.cardHover : root.card

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Text {
            anchors.centerIn: parent
            text: it.icon
            color: it.checked ? Theme.fg : Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.iconSize
        }

        MouseArea {
            id: itArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: it.toggled()
        }
    }

    // плитка источника
    component SourceTile: Rectangle {
        id: tile
        property string value
        property string label
        property string kind: "monitor"   // monitor | region | window
        property real aspect: 16 / 9
        readonly property bool selected: (Recorder.target || Settings.primary) === value

        implicitWidth: 104
        implicitHeight: 92
        // на узком экране с несколькими мониторами плитки сжимаются
        Layout.minimumWidth: 72
        radius: 14
        color: selected ? Theme.surfaceHi : tileArea.containsMouse ? root.cardHover : root.card
        border.width: selected ? 1.5 : 0
        border.color: Theme.fg
        scale: tileArea.pressed ? 0.96 : 1

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast } }

        // мини-превью
        Item {
            id: glyph
            anchors.horizontalCenter: parent.horizontalCenter
            y: 14
            width: 56
            height: 38

            readonly property color stroke: tile.selected ? Theme.fg : Theme.dim
            readonly property real w: tile.aspect >= 56 / 38 ? 56 : 38 * tile.aspect
            readonly property real h: tile.aspect >= 56 / 38 ? 56 / tile.aspect : 38

            // монитор
            Rectangle {
                visible: tile.kind === "monitor"
                anchors.centerIn: parent
                width: glyph.w
                height: glyph.h
                radius: 4
                color: "transparent"
                border.width: 1.5
                border.color: glyph.stroke
            }

            // окно
            Rectangle {
                visible: tile.kind === "window"
                anchors.centerIn: parent
                width: 50
                height: 34
                radius: 4
                color: "transparent"
                border.width: 1.5
                border.color: glyph.stroke

                Rectangle {
                    width: parent.width
                    height: 7
                    radius: 4
                    color: glyph.stroke
                }
            }

            // область: пунктирная рамка
            Canvas {
                visible: tile.kind === "region"
                anchors.fill: parent
                property color stroke: glyph.stroke
                onStrokeChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = stroke;
                    ctx.lineWidth = 1.5;
                    ctx.setLineDash([3, 3]);
                    ctx.strokeRect(4, 4, width - 8, height - 8);
                    ctx.setLineDash([]);
                    ctx.fillStyle = stroke;
                    for (const [x, y] of [[4, 4], [width - 4, 4], [4, height - 4], [width - 4, height - 4]])
                        ctx.fillRect(x - 2.5, y - 2.5, 5, 5);
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            width: Math.min(implicitWidth, tile.width - 12)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr(tile.label)
            color: tile.selected ? Theme.fg : Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }

        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Recorder.target = tile.value
        }
    }

    // карточка аудио-источника
    component AudioCard: Rectangle {
        id: ac
        property string icon
        property string title
        property string device
        property bool checked
        signal toggled

        implicitHeight: 64
        radius: 14
        color: acArea.containsMouse ? root.cardHover : root.card
        scale: acArea.pressed ? 0.98 : 1

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12

            Rectangle {
                implicitWidth: 36
                implicitHeight: 36
                radius: 18
                color: ac.checked ? Theme.fg : Theme.surfaceHi2

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Text {
                    anchors.centerIn: parent
                    text: ac.icon
                    color: ac.checked ? Theme.bg : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize + 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: I18n.tr(ac.title)
                    color: ac.checked ? Theme.fg : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
                Text {
                    Layout.fillWidth: true
                    text: ac.device || "—"
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }

            Switch { checked: ac.checked }
        }

        MouseArea {
            id: acArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ac.toggled()
        }
    }

    // ── карточка ──────────────────────────────────────────

    Item {
        id: cardWrap
        anchors.centerIn: parent
        // шире, если не помещаются плитки источников (по одной на монитор) или параметры
        // (по-русски подписи длиннее), но не шире экрана
        width: Math.min(root.width - 40, Math.max(540, sourceRow.implicitWidth + 48, paramRow.implicitWidth + 48))
        height: column.implicitHeight + 48

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.94

        Behavior on opacity { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animSlow + 60; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

        // мягкая тень
        RectangularShadow {
            anchors.fill: bg
            radius: bg.radius
            blur: 40
            spread: 2
            offset.y: 12
            color: "#99000000"
        }

        Rectangle {
            id: bg
            anchors.fill: parent
            radius: 22
            color: Theme.panel
            border.width: 1
            border.color: Theme.surfaceHi2

            // лёгкий красный отсвет сверху во время записи
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                opacity: Recorder.recording ? 1 : 0
                gradient: Gradient {
                    GradientStop { position: 0; color: "#22e05d5d" }
                    GradientStop { position: 0.35; color: "#00e05d5d" }
                }

                Behavior on opacity { NumberAnimation { duration: 400 } }
            }

            MouseArea { anchors.fill: parent }
        }

        ColumnLayout {
            id: column

            x: 24
            y: 24
            width: parent.width - 48
            spacing: 18

            // ── заголовок
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: Recorder.recording ? I18n.tr(Recorder.paused ? "Paused" : "Recording")
                            : Recorder.countdown > 0 ? (I18n.ru ? `Старт через ${Recorder.countdown}…` : `Starting in ${Recorder.countdown}…`) : I18n.tr("Record screen")
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 7
                        font.bold: true
                    }

                    Text {
                        readonly property string src: Recorder.target === "region" ? I18n.tr("Region")
                            : Recorder.target === "window" ? I18n.tr("Window") : (Recorder.target || Settings.primary)
                        readonly property string snd: I18n.tr(({ none: "no audio", system: "system audio", mic: "microphone", both: "system + mic" })[Recorder.audio])
                        text: Recorder.recording ? `${Recorder.elapsedText} · ${src} · ${snd}`
                            : `${src} · ${Recorder.fps} fps · ${snd}`
                        color: Recorder.recording ? root.red : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                }

                Item { Layout.fillWidth: true }

                IconToggle {
                    icon: Icons.folder
                    onToggled: {
                        root.open = false;
                        Recorder.openFolder();
                    }
                }
                IconToggle {
                    icon: Icons.close
                    onToggled: root.open = false
                }
            }

            // ── источник
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                enabled: !Recorder.recording
                opacity: enabled ? 1 : 0.4

                Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

                Caption { text: I18n.tr("Source") }

                RowLayout {
                    id: sourceRow
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: Quickshell.screens

                        SourceTile {
                            required property ShellScreen modelData
                            Layout.fillWidth: true
                            value: modelData.name
                            label: modelData.name
                            aspect: modelData.width / modelData.height
                        }
                    }

                    SourceTile {
                        Layout.fillWidth: true
                        value: "region"
                        label: "Region"
                        kind: "region"
                    }

                    SourceTile {
                        Layout.fillWidth: true
                        value: "window"
                        label: "Window"
                        kind: "window"
                    }
                }
            }

            // ── звук
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                enabled: !Recorder.recording
                opacity: enabled ? 1 : 0.4

                Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

                Caption { text: I18n.tr("Audio") }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    AudioCard {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        icon: Icons.volHigh
                        title: "System audio"
                        device: Pipewire.defaultAudioSink?.description ?? ""
                        checked: root.sysOn
                        onToggled: root.setAudio(!root.sysOn, root.micOn)
                    }

                    AudioCard {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        icon: Icons.mic
                        title: "Microphone"
                        device: Pipewire.defaultAudioSource?.description ?? ""
                        checked: root.micOn
                        onToggled: root.setAudio(root.sysOn, !root.micOn)
                    }
                }
            }

            // ── параметры
            RowLayout {
                id: paramRow
                Layout.fillWidth: true
                spacing: 8
                enabled: !Recorder.recording
                opacity: enabled ? 1 : 0.4

                Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

                Pills {
                    current: Recorder.fps
                    options: [30, 60, 120].map(f => ({ value: f, label: `${f} fps` }))
                    onPicked: v => Recorder.fps = v
                }

                Pills {
                    current: Recorder.quality
                    options: [
                        { value: "high", label: "High" },
                        { value: "very_high", label: "Very high" },
                        { value: "ultra", label: "Ultra" },
                    ]
                    onPicked: v => Recorder.quality = v
                }

                Item { Layout.fillWidth: true }

                IconToggle {
                    icon: Icons.pointer
                    checked: Recorder.cursor
                    onToggled: Recorder.cursor = !Recorder.cursor
                }

                IconToggle {
                    icon: Icons.timer
                    checked: Recorder.countdownEnabled
                    onToggled: Recorder.countdownEnabled = !Recorder.countdownEnabled
                }
            }

            // ── кнопка записи (монохром)
            Item {
                id: control

                readonly property bool live: Recorder.recording
                readonly property bool counting: Recorder.countdown > 0

                Layout.fillWidth: true
                Layout.preferredHeight: 52

                // ожидание: светлая кнопка, красная только точка
                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: startArea.pressed ? Theme.fgPressed : startArea.containsMouse ? Theme.fgHover : Theme.fg
                    opacity: control.live || control.counting ? 0 : 1
                    visible: opacity > 0
                    scale: startArea.pressed ? 0.985 : 1

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }
                    Behavior on scale { NumberAnimation { duration: Theme.animFast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 14
                        spacing: 12

                        Rectangle {
                            implicitWidth: 10
                            implicitHeight: 10
                            radius: 5
                            color: root.red
                        }

                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Start recording")
                            color: Theme.bg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 1
                            font.bold: true
                        }

                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 22
                            radius: 6
                            color: "transparent"
                            border.width: 1
                            border.color: "#26000000"

                            Text {
                                anchors.centerIn: parent
                                text: "⏎"
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 1
                            }
                        }
                    }

                    MouseArea {
                        id: startArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.recordAction()
                    }
                }

                // отсчёт перед стартом
                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: root.card
                    opacity: control.counting ? 1 : 0
                    visible: opacity > 0
                    clip: true

                    Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

                    Rectangle {
                        width: parent.width * Recorder.countdown / 3
                        height: parent.height
                        radius: parent.radius
                        color: Theme.surfaceHi2

                        Behavior on width { NumberAnimation { duration: 1000 } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: I18n.ru ? `Старт через ${Recorder.countdown}` : `Starting in ${Recorder.countdown}`
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Recorder.stop()
                    }
                }

                // идёт запись: тёмная, без обводки
                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: root.card
                    opacity: control.live ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 8
                        spacing: 12

                        Rectangle {
                            implicitWidth: 10
                            implicitHeight: 10
                            radius: 5
                            color: Recorder.paused ? Theme.dim : root.red

                            SequentialAnimation on opacity {
                                running: control.live && !Recorder.paused
                                loops: Animation.Infinite
                                onRunningChanged: if (!running) parent.opacity = 1
                                NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }

                        Text {
                            text: Recorder.elapsedText
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 3
                            font.bold: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr(Recorder.paused ? "paused" : "")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }

                        // пауза
                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 10
                            color: pauseArea.pressed ? Theme.line : pauseArea.containsMouse ? Theme.surfaceHi2 : Theme.surfaceHi

                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            Text {
                                anchors.centerIn: parent
                                text: Recorder.paused ? Icons.play : Icons.pause
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.iconSize
                            }

                            MouseArea {
                                id: pauseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Recorder.togglePause()
                            }
                        }

                        // стоп: светлый, как кнопка старта
                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 10
                            color: stopArea.pressed ? Theme.fgPressed : stopArea.containsMouse ? Theme.fgHover : Theme.fg

                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 12
                                height: 12
                                radius: 2
                                color: Theme.bg
                            }

                            MouseArea {
                                id: stopArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Recorder.stop()
                            }
                        }
                    }
                }
            }

            // ── мгновенный повтор
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 56
                radius: 14
                color: root.card
                border.width: Recorder.replayActive ? 1 : 0
                border.color: Theme.line

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        text: Icons.replay
                        color: Recorder.replayActive ? Theme.fg : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.iconSize + 2
                    }

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: I18n.tr("Instant replay")
                            color: Recorder.replayActive ? Theme.fg : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            text: Recorder.replayActive ? (I18n.ru ? `пишет последние ${Recorder.replaySeconds} с · R — сохранить` : `buffering last ${Recorder.replaySeconds}s · R to save`) : I18n.tr("keeps the last moments in memory")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Pills {
                        visible: !Recorder.replayActive
                        current: Recorder.replaySeconds
                        options: [15, 30, 60, 120].map(s => ({ value: s, label: `${s}s` }))
                        onPicked: v => Recorder.replaySeconds = v
                    }

                    Rectangle {
                        visible: Recorder.replayActive
                        implicitWidth: saveText.implicitWidth + 24
                        implicitHeight: 30
                        radius: 10
                        color: saveArea.containsMouse ? Theme.fgHover : Theme.fg

                        Text {
                            id: saveText
                            anchors.centerIn: parent
                            text: I18n.tr("Save")
                            color: Theme.bg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                        }

                        MouseArea {
                            id: saveArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Recorder.saveReplay()
                        }
                    }

                    Switch {
                        checked: Recorder.replayActive

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Recorder.toggleReplay()
                        }
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: I18n.tr("Enter  start / stop   ·   P  pause   ·   R  save replay   ·   Esc  close")
                color: Theme.line
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }
}
