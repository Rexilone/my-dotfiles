import QtQuick
import QtQuick.Layouts
import qs.services
import qs.settings

// виджет телефона (Rexlink) для рабочего стола
// device — id устройства ("" — текущее), variant — battery | status | notifications | media | actions | full
Item {
    id: root

    property string device: ""
    property string variant: "full"

    readonly property var dev: Rexlink.devFor(device)
    readonly property string did: dev?.id ?? ""
    readonly property bool online: dev?.online ?? false
    readonly property var st: Rexlink.statusFor(device)
    readonly property var media: Rexlink.mediaFor(device)
    readonly property var notifs: Rexlink.notifsFor(device)
    readonly property int battery: st.battery ?? dev?.battery ?? -1

    implicitWidth: loader.implicitWidth
    implicitHeight: loader.implicitHeight

    function bars(level) {
        // уровень сигнала 0..4 — столбиками
        let s = "";
        for (let i = 1; i <= 4; i++) s += i <= (level ?? 0) ? "▮" : "▯";
        return s;
    }

    component Title: RowLayout {
        spacing: 8
        Text {
            text: Rexlink.kindIcon(root.dev?.kind)
            color: root.online ? Theme.accent : Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.iconSize + 2
        }
        Text {
            Layout.fillWidth: true
            text: I18n.tr(root.dev?.name ?? (Rexlink.connected ? "No device" : "Rexlink is off"))
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
        }
        Text {
            visible: !root.online
            text: I18n.tr("offline")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
    }

    Loader {
        id: loader
        sourceComponent: ({ battery: batteryC, status: statusC, notifications: notifsC, media: mediaC, actions: actionsC })[root.variant] ?? fullC
    }

    // ── заряд: компактное кольцо
    Component {
        id: batteryC
        ColumnLayout {
            spacing: 6
            StatRing {
                Layout.alignment: Qt.AlignHCenter
                size: 104
                thickness: 8
                battery: true
                value: Math.max(0, root.battery / 100)
                center: root.online && root.battery >= 0 ? `${root.battery}%` : "—"
                label: root.dev?.name ?? ""
                sub: !root.online ? "offline" : root.st.charging ? "charging" : `${root.st.temp ?? "—"}°C`
            }
        }
    }

    // ── статус: заряд полосой, сеть, температура
    Component {
        id: statusC
        ColumnLayout {
            width: 300
            spacing: 10
            Title {}

            RowLayout {
                spacing: 10
                Text {
                    text: Rexlink.batteryIcon(root.battery, root.st.charging)
                    color: root.battery >= 0 && root.battery <= 15 && !root.st.charging ? Theme.urgent : Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 22
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    radius: 4
                    color: Theme.surfaceHi2
                    Rectangle {
                        width: parent.width * Math.max(0, root.battery) / 100
                        height: parent.height
                        radius: 4
                        color: root.battery <= 15 && !root.st.charging ? Theme.urgent : Theme.accent
                        Behavior on width { NumberAnimation { duration: 400 } }
                    }
                }
                Text {
                    text: root.battery >= 0 ? `${root.battery}%` : "—"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
            }

            GridLayout {
                columns: 2
                columnSpacing: 14
                rowSpacing: 4
                Text { text: `${Icons.wifi}  ${root.st.net === "wifi" ? (root.st.wifi?.ssid || "Wi-Fi") : I18n.tr("Wi-Fi off")}`; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontSize - 2 }
                Text { text: root.bars(root.st.wifi?.level); color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.fontSize - 2 }
                Text { text: `${String.fromCodePoint(0xF08BD)}  ${root.st.cell?.operator ?? "—"} ${root.st.cell?.gen ?? ""}`; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontSize - 2 }
                Text { text: root.bars(root.st.cell?.level); color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.fontSize - 2 }
                Text { text: `${String.fromCodePoint(0xF050F)}  ${I18n.tr("Temperature")}`; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontSize - 2 }
                Text { text: `${root.st.temp ?? "—"}°C`; color: Theme.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize - 2 }
            }
        }
    }

    // ── уведомления
    Component {
        id: notifsC
        ColumnLayout {
            width: 340
            spacing: 8
            RowLayout {
                Title { Layout.fillWidth: true }
                Text {
                    text: `${String.fromCodePoint(0xF009A)} ${root.notifs.length}`
                    color: root.notifs.length ? Theme.accent : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
            }
            Text {
                visible: root.notifs.length === 0
                text: I18n.tr(root.online ? "Nothing new" : "Device is offline")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            Repeater {
                model: root.notifs.slice(0, 5)
                Rectangle {
                    id: n
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: nc.implicitHeight + 16
                    radius: 10
                    color: Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.7)

                    ColumnLayout {
                        id: nc
                        x: 10
                        y: 8
                        width: parent.width - 20
                        spacing: 1
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: n.modelData.app ?? ""
                                elide: Text.ElideRight
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 3
                            }
                            Text {
                                visible: n.modelData.clearable !== false
                                text: Icons.close
                                color: x1.containsMouse ? Theme.urgent : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 2
                                MouseArea {
                                    id: x1
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Rexlink.notifDismiss(n.modelData.key, root.did)
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: n.modelData.title ?? ""
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: n.modelData.text ?? ""
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }
            }
            Text {
                visible: root.notifs.length > 5
                text: I18n.ru ? `ещё ${root.notifs.length - 5}` : `+${root.notifs.length - 5} more`
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    // ── медиа
    Component {
        id: mediaC
        ColumnLayout {
            width: 320
            spacing: 8
            Title {}
            Text {
                Layout.fillWidth: true
                text: root.media.title || "Nothing playing"
                elide: Text.ElideRight
                color: root.media.title ? Theme.fg : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 1
                font.bold: !!root.media.title
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: [root.media.artist, root.media.app].filter(s => s).join("  ·  ")
                elide: Text.ElideRight
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
            Rectangle {
                visible: (root.media.len ?? 0) > 0
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: Theme.surfaceHi2
                Rectangle {
                    width: parent.width * Math.min(1, (root.media.pos ?? 0) / Math.max(1, root.media.len ?? 1))
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10
                Repeater {
                    model: [["prev", 0xF04AE, false], ["toggle", root.media.playing ? 0xF03E4 : 0xF040A, true], ["next", 0xF04AD, false]]
                    Rectangle {
                        required property var modelData
                        implicitWidth: modelData[2] ? 44 : 36
                        implicitHeight: implicitWidth
                        radius: width / 2
                        color: modelData[2] ? Theme.accent : (mb.containsMouse ? Theme.surfaceHi2 : Theme.surfaceHi)
                        opacity: root.online ? 1 : 0.4
                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(parent.modelData[1])
                            color: parent.modelData[2] ? Theme.bg : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize + (parent.modelData[2] ? 2 : 0)
                        }
                        MouseArea {
                            id: mb
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.online
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Rexlink.mediaAction(parent.modelData[0], root.did)
                        }
                    }
                }
            }
        }
    }

    // ── быстрые действия
    Component {
        id: actionsC
        ColumnLayout {
            width: 300
            spacing: 10
            Title {}
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: 8
                rowSpacing: 8
                Repeater {
                    model: [
                        [0xF08D3, "Find", () => Rexlink.ring(root.did)],
                        [Icons.clipboard.codePointAt(0), "Clipboard", () => Rexlink.clipboardPull(root.did)],
                        [0xF0552, "Files", () => { Rexlink.select(root.did); Rexlink.show("files"); }],
                        [0xF0379, "Screen", () => Rexlink.screenStart(root.did)],
                        [0xF0100, "Webcam", () => Rexlink.cameraToggle(root.did)],
                        [0xF0369, "Messages", () => { Rexlink.select(root.did); Rexlink.show("messages"); }],
                    ]
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 58
                        radius: 12
                        color: ab.pressed ? Theme.surfaceHi2 : ab.containsMouse ? Theme.surfaceHi : Qt.rgba(Theme.surfaceHi.r, Theme.surfaceHi.g, Theme.surfaceHi.b, 0.6)
                        opacity: root.online ? 1 : 0.4
                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: String.fromCodePoint(parent.parent.modelData[0])
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.iconSize + 2
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.parent.modelData[1]
                                color: Theme.muted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 3
                            }
                        }
                        MouseArea {
                            id: ab
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.online
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.modelData[2]()
                        }
                    }
                }
            }
        }
    }

    // ── всё сразу
    Component {
        id: fullC
        RowLayout {
            width: 380
            spacing: 18
            StatRing {
                size: 96
                thickness: 7
                battery: true
                value: Math.max(0, root.battery / 100)
                center: root.online && root.battery >= 0 ? `${root.battery}%` : "—"
                label: root.st.charging ? "Charging" : ""
                sub: ""
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Title {}
                Text {
                    text: !root.online ? "Offline"
                        : `${root.st.cell?.operator ?? ""} ${root.st.cell?.gen ?? ""}  ·  ${root.st.net === "wifi" ? "Wi-Fi" : "mobile"}  ·  ${root.st.temp ?? "—"}°C`
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    visible: root.online
                    text: `${String.fromCodePoint(0xF009A)} ${root.notifs.length} ${I18n.plural(root.notifs.length, "notification", "notifications", "уведомление", "уведомления", "уведомлений")}`
                    color: root.notifs.length ? Theme.accent : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    visible: root.online && !!root.media.title
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: `${String.fromCodePoint(root.media.playing ? 0xF040A : 0xF03E4)}  ${root.media.title ?? ""}`
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }
}
