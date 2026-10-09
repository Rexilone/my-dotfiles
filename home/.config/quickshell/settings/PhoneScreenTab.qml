import QtQuick
import QtQuick.Layouts
import qs.services

// Телефон → Экран устройства: картинка + мышь и клавиатура, кнопки навигации,
// режим «экран выключен» (ADB) и подключение отладки по Wi-Fi
ColumnLayout {
    id: tab

    property bool active: false

    readonly property var sc: Rexlink.screen
    readonly property bool live: !!sc.running && fv.live

    Layout.fillWidth: true
    spacing: 10

    function key(k) { Rexlink.key(k); }

    // ── управление
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: !Rexlink.online ? I18n.tr("The device is not connected")
                : tab.sc.running ? `${Rexlink.dev?.name ?? ""}   ·   ${tab.sc.w ?? 0}×${tab.sc.h ?? 0}${tab.sc.source === "adb" ? "   ·   ADB" : ""}`
                : (Rexlink.dev?.name ?? "")
            elide: Text.ElideRight
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
        SChoice {
            visible: !!tab.sc.running
            options: [{ value: false, label: "Screen on" }, { value: true, label: "Screen off" }]
            current: !!tab.sc.off
            onPicked: v => Rexlink.screenOff(v)
        }
        SButton {
            text: tab.sc.running ? "Disconnect" : "Connect"
            icon: String.fromCodePoint(tab.sc.running ? 0xF04DB : 0xF0379)
            primary: !tab.sc.running
            danger: !!tab.sc.running
            enabled: Rexlink.online && Rexlink.settings.ffmpeg !== false
            onClicked: tab.sc.running ? Rexlink.screenStop() : Rexlink.screenStart()
        }
    }

    // ── отладка по Wi-Fi (для «экран выключен»)
    Rectangle {
        id: adb
        readonly property var ports: tab.sc.adbPorts ?? ({})
        visible: !!tab.sc.running && !!tab.sc.adbNeedPair && !tab.sc.off
        onVisibleChanged: if (visible) Rexlink.adbInfo()
        Layout.fillWidth: true
        implicitHeight: adbCol.implicitHeight + 32
        radius: 10
        color: Theme.surface
        border.width: 1
        border.color: Theme.warn

        ColumnLayout {
            id: adbCol
            x: 18
            y: 16
            width: parent.width - 36
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: String.fromCodePoint(0xF00E4)
                    color: Theme.warn
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize + 4
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Turning the device screen off needs wireless debugging (ADB)")
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                SButton { icon: String.fromCodePoint(0xF0450); onClicked: Rexlink.adbInfo() }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: I18n.tr("On the device: Settings → Developer options → Wireless debugging → on. The first time, tap “Pair device with pairing code” there and enter the port and code below. After that it connects by itself while wireless debugging is on.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
            Text {
                visible: !!adb.ports.connect || !!adb.ports.pairing
                text: `${I18n.tr("Found on the device")}: ${[adb.ports.connect ? I18n.tr("debugging port") + " " + adb.ports.connect : "", adb.ports.pairing ? I18n.tr("pairing port") + " " + adb.ports.pairing : ""].filter(x => x).join("   ·   ")}`
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                SField {
                    id: pport
                    Layout.fillWidth: false
                    implicitWidth: 150
                    placeholder: "Pairing port"
                    text: adb.ports.pairing ? String(adb.ports.pairing) : ""
                }
                SField {
                    id: pcode
                    Layout.fillWidth: false
                    implicitWidth: 150
                    placeholder: "Code (6 digits)"
                    onAccepted: pairBtn.clicked()
                }
                SButton {
                    id: pairBtn
                    text: "Pair"
                    primary: true
                    enabled: pport.text.trim() !== "" && pcode.text.trim() !== ""
                    onClicked: Rexlink.adbPair(parseInt(pport.text), pcode.text.trim())
                }
                Item { Layout.fillWidth: true }
                SField {
                    id: cport
                    Layout.fillWidth: false
                    implicitWidth: 150
                    placeholder: "Debugging port"
                    text: adb.ports.connect ? String(adb.ports.connect) : ""
                    onAccepted: connBtn.clicked()
                }
                SButton {
                    id: connBtn
                    text: "Connect"
                    enabled: cport.text.trim() !== ""
                    onClicked: Rexlink.adbConnect(parseInt(cport.text))
                }
            }
        }
    }

    // ── картинка и кнопки
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: Theme.surface
            clip: true

            PhoneFrame {
                id: fv
                anchors.fill: parent
                anchors.margins: 10
                channel: Rexlink.current ? `screen:${Rexlink.current}` : ""
                active: tab.active && !!tab.sc.running
                visible: !!tab.sc.running

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    enabled: tab.live
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: tab.live ? Qt.CrossCursor : Qt.ArrowCursor

                    property var pts: []
                    property real t0: 0

                    onPressed: mouse => {
                        surface.forceActiveFocus();
                        if (mouse.button !== Qt.LeftButton) return;
                        t0 = Date.now();
                        pts = [fv.norm(mouse.x, mouse.y)];
                    }
                    onPositionChanged: mouse => {
                        if (!(mouse.buttons & Qt.LeftButton) || !pts.length) return;
                        const p = fv.norm(mouse.x, mouse.y), l = pts[pts.length - 1];
                        if (Math.hypot((p[0] - l[0]) * fv.contentW, (p[1] - l[1]) * fv.contentH) > 6) pts.push(p);
                    }
                    onReleased: mouse => {
                        if (mouse.button === Qt.RightButton) { tab.key("back"); return; }
                        if (mouse.button === Qt.MiddleButton) { tab.key("home"); return; }
                        if (!pts.length) return;
                        const dt = Date.now() - t0;
                        const p = fv.norm(mouse.x, mouse.y), a = pts[0];
                        const moved = Math.hypot((p[0] - a[0]) * fv.contentW, (p[1] - a[1]) * fv.contentH) > 8;
                        if (!moved) {
                            Rexlink.input({ kind: dt > 450 ? "long" : "tap", x: a[0], y: a[1] });
                        } else {
                            pts.push(p);
                            // не больше 30 точек: жест передаётся одним путём
                            const step = Math.max(1, Math.ceil(pts.length / 30));
                            const path = pts.filter((_, i) => i % step === 0 || i === pts.length - 1);
                            Rexlink.input({ kind: "swipe", points: path, duration: Math.max(60, Math.min(3000, dt)) });
                        }
                        pts = [];
                    }
                    onWheel: wheel => {
                        const p = fv.norm(wheel.x, wheel.y);
                        Rexlink.input({ kind: "scroll", x: p[0], y: p[1], dy: wheel.angleDelta.y > 0 ? 1 : -1 });
                    }
                }
            }

            // клавиатура: печать уходит в поле ввода на устройстве
            Item {
                id: surface
                anchors.fill: parent
                focus: tab.active
                Keys.onPressed: event => {
                    if (!tab.live) return;
                    const map = {
                        [Qt.Key_Backspace]: "backspace", [Qt.Key_Return]: "enter", [Qt.Key_Enter]: "enter",
                        [Qt.Key_Escape]: "back", [Qt.Key_Tab]: "tab", [Qt.Key_Left]: "left", [Qt.Key_Right]: "right",
                        [Qt.Key_Up]: "up", [Qt.Key_Down]: "down", [Qt.Key_Home]: "home", [Qt.Key_Delete]: "delete",
                    };
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                        tab.key("paste");
                    } else if (map[event.key]) {
                        tab.key(map[event.key]);
                    } else if (event.text && event.text.length && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                        Rexlink.input({ kind: "text", text: event.text });
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }

            PhoneEmpty {
                anchors.centerIn: parent
                width: Math.min(parent.width - 60, 560)
                visible: !tab.live
                icon: String.fromCodePoint(0xF0379)
                text: tab.sc.running ? "Waiting for the device…" : Rexlink.online ? "The screen is not connected" : "The device is not connected"
                hint: tab.sc.running
                    ? (tab.sc.source === "adb" ? "Connecting over ADB…" : "Press “Start” on the device — Android asks this without ADB. To skip the question, connect the device over USB or turn on wireless debugging.")
                    : "Click — tap, hold — long press, drag — swipe, wheel — scroll, right button — Back, middle — Home, keyboard — typing. Control needs the Rexlink accessibility service on the device."
            }
        }

        // кнопки навигации
        Rectangle {
            visible: !!tab.sc.running
            Layout.fillHeight: true
            Layout.preferredWidth: 58
            radius: 12
            color: Theme.surface

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 12
                spacing: 6

                Repeater {
                    model: [
                        { icon: 0xF004D, key: "back" }, { icon: 0xF02DC, key: "home" },
                        { icon: 0xF0570, key: "recents" }, { icon: 0xF0E91, key: "notifications" },
                        { icon: 0xF075D, key: "volup" }, { icon: 0xF075E, key: "voldown" },
                        { icon: 0xF0493, key: "quick" }, { icon: 0xF033E, key: "lock" },
                        { icon: 0xF0104, key: "screenshot" },
                    ]
                    SButton {
                        required property var modelData
                        width: 40
                        implicitHeight: 40
                        icon: String.fromCodePoint(modelData.icon)
                        onClicked: { tab.key(modelData.key); surface.forceActiveFocus(); }
                    }
                }
            }
        }
    }
}
