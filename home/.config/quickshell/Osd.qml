import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.services

// нижний индикатор (OSD): выезжает снизу, когда меняются громкость, микрофон или яркость
// (клавишами, колёсиком на баре, из другой программы), и пока идёт голосовой ввод (Voxtype, Super+H).
// Пока открыто меню бара (там свой ползунок), громкость не показывает.
PanelWindow {
    id: root

    // что показываем: volume | mic | brightness | voice
    property string kind: "volume"
    property bool shown: false
    readonly property bool voiceActive: Voice.state === "recording" || Voice.state === "transcribing"
    readonly property bool visibleNow: shown || voiceActive
    readonly property bool enabled_: Settings.moduleOn("osd", true)

    screen: Settings.activeScreen()
    visible: visibleNow || hideTimer.running
    color: "transparent"
    anchors.bottom: true
    margins.bottom: 0
    implicitWidth: 380
    implicitHeight: 110
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    mask: Region {}

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    onVisibleNowChanged: if (!visibleNow) hideTimer.restart()

    // плавно спрятать окно после уезжания карточки
    Timer {
        id: hideTimer
        interval: 320
    }
    Timer {
        id: autoHide
        interval: 1600
        onTriggered: root.shown = false
    }

    function pop(k) {
        if (!enabled_) return;
        kind = k;
        shown = true;
        autoHide.restart();
    }

    // ── что показываем сейчас
    readonly property string showKind: voiceActive ? "voice" : kind
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source] }

    readonly property real level: showKind === "volume" ? (sink?.audio?.volume ?? 0)
        : showKind === "mic" ? (source?.audio?.volume ?? 0)
        : showKind === "brightness" ? Brightness.value : 0
    readonly property bool muted: showKind === "volume" ? !!sink?.audio?.muted : showKind === "mic" ? !!source?.audio?.muted : false

    readonly property string icon: {
        const g = c => String.fromCodePoint(c);
        if (showKind === "voice") return g(Voice.state === "transcribing" ? 0xF0772 : 0xF036C);
        if (showKind === "brightness") return g(level < 0.34 ? 0xF00DE : level < 0.67 ? 0xF00DF : 0xF00E0);
        if (showKind === "mic") return muted ? g(0xF036D) : g(0xF036C);
        if (muted || level <= 0.001) return g(0xF075F);
        return g(level < 0.34 ? 0xF057F : level < 0.67 ? 0xF0580 : 0xF057E);
    }
    readonly property string label: showKind === "voice" ? I18n.tr(Voice.state === "transcribing" ? "Recognizing…" : "Listening…")
        : showKind === "brightness" ? I18n.tr("Brightness")
        : showKind === "mic" ? I18n.tr("Microphone")
        : I18n.tr("Volume")

    // ── реакция на изменения (первые значения после запуска и смены устройства — не показываем)
    property bool armed: false
    Timer {
        running: true
        interval: 2500
        onTriggered: root.armed = true
    }
    property real lastSinkVol: -1
    property bool lastSinkMute: false
    property real lastSrcVol: -1
    property bool lastSrcMute: false
    onSinkChanged: { lastSinkVol = -1; }
    onSourceChanged: { lastSrcVol = -1; }

    Connections {
        target: root.sink?.audio ?? null
        function onVolumeChanged() { root.sinkUpdate(); }
        function onMutedChanged() { root.sinkUpdate(); }
    }
    Connections {
        target: root.source?.audio ?? null
        function onVolumeChanged() { root.srcUpdate(); }
        function onMutedChanged() { root.srcUpdate(); }
    }
    Connections {
        target: Brightness
        function onChanged() { if (root.armed) root.pop("brightness"); }
    }

    function sinkUpdate() {
        const a = sink?.audio;
        if (!a) return;
        const changed = lastSinkVol >= 0 && (Math.abs(a.volume - lastSinkVol) > 0.004 || a.muted !== lastSinkMute);
        lastSinkVol = a.volume;
        lastSinkMute = a.muted;
        if (changed && armed && Ui.menusOpen === 0) pop("volume");
    }
    function srcUpdate() {
        const a = source?.audio;
        if (!a) return;
        const changed = lastSrcVol >= 0 && (Math.abs(a.volume - lastSrcVol) > 0.004 || a.muted !== lastSrcMute);
        lastSrcVol = a.volume;
        lastSrcMute = a.muted;
        if (changed && armed && Ui.menusOpen === 0) pop("mic");
    }

    // ── карточка
    RectangularShadow {
        anchors.fill: card
        radius: card.radius
        blur: 24
        offset.y: 6
        color: "#70000000"
        opacity: card.opacity
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 40
        height: 56
        radius: height / 2
        y: root.visibleNow ? parent.height - height - 24 : parent.height + 10
        opacity: root.visibleNow ? 1 : 0
        color: Theme.panel
        border.width: 1
        border.color: root.showKind === "voice" && Voice.state === "recording" ? Theme.rec : Theme.surfaceHi2

        Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 20
            spacing: 14

            // значок (у голосового ввода — пульсирующая точка записи)
            Item {
                implicitWidth: 24
                implicitHeight: 24

                Rectangle {
                    anchors.centerIn: parent
                    visible: root.showKind === "voice" && Voice.state === "recording"
                    width: 24
                    height: 24
                    radius: 12
                    color: Theme.rec
                    opacity: 0.25
                    SequentialAnimation on scale {
                        running: root.showKind === "voice" && Voice.state === "recording"
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.8; to: 1.3; duration: 650; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.3; to: 0.8; duration: 650; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    id: osdIcon
                    anchors.centerIn: parent
                    text: root.icon
                    color: root.showKind === "voice" && Voice.state === "recording" ? Theme.rec : root.muted ? Theme.dim : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize + 4

                    RotationAnimation on rotation {
                        running: root.showKind === "voice" && Voice.state === "transcribing"
                        from: 0
                        to: 360
                        duration: 1200
                        loops: Animation.Infinite
                        // после остановки — ровно (иначе значок застывает под углом)
                        onRunningChanged: if (!running) osdIcon.rotation = 0
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: root.label + (root.muted ? `   ·   ${I18n.tr("muted")}` : "")
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true
                    }
                    Text {
                        visible: root.showKind !== "voice"
                        text: `${Math.round(root.level * 100)}%`
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Text {
                        visible: root.showKind === "voice"
                        text: Voice.state === "recording" ? "Super+H" : ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }

                // полоса уровня; у голосового ввода — бегущая полоса
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Theme.surfaceHi2
                    clip: true

                    Rectangle {
                        visible: root.showKind !== "voice"
                        width: parent.width * Math.min(1, root.level)
                        height: parent.height
                        radius: 2
                        color: root.muted ? Theme.dim : Theme.accent
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                    Rectangle {
                        id: sweep
                        visible: root.showKind === "voice"
                        property real pos: 0
                        width: parent.width * 0.3
                        height: parent.height
                        radius: 2
                        x: pos * parent.width * 1.3 - width
                        color: Voice.state === "recording" ? Theme.rec : Theme.accent
                        NumberAnimation on pos {
                            running: root.showKind === "voice"
                            from: 0
                            to: 1
                            duration: Voice.state === "recording" ? 1600 : 900
                            loops: Animation.Infinite
                        }
                    }
                }
            }
        }
    }
}
