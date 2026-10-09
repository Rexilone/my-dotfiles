import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.settings

// меню телефона (Rexlink): состояние, быстрые действия, медиа и уведомления с телефона
ColumnLayout {
    id: root

    property bool active: false
    property string replyKey: ""
    property int replyAction: -1

    width: 400
    spacing: 10

    function ago(ms) {
        if (!ms) return "";
        const min = Math.floor((Date.now() - ms) / 60000);
        return min < 1 ? "now" : min < 60 ? `${min}m` : min < 1440 ? `${Math.floor(min / 60)}h` : `${Math.floor(min / 1440)}d`;
    }

    MenuHeader {
        icon: Rexlink.kindIcon(Rexlink.dev?.kind)
        title: Rexlink.dev?.name ?? "Rexlink"
        subtitle: !Rexlink.connected ? "Rexlink isn't running"
            : !Rexlink.dev ? "No paired devices"
            : `${Rexlink.dev.model}  ·  ${Rexlink.online ? "connected" : "offline"}`
        settingsPage: "phone"

        // переключение устройств
        SDropdown {
            visible: Rexlink.devices.length > 1
            minWidth: 40
            implicitWidth: 40
            options: Rexlink.devices.map(d => ({ value: d.id, label: `${d.name}${d.online ? "" : "  " + I18n.tr("(offline)")}` }))
            current: Rexlink.current
            onPicked: v => Rexlink.select(v)
        }
    }

    // Rexlink не запущен
    Rectangle {
        visible: !Rexlink.connected
        Layout.fillWidth: true
        implicitHeight: 60
        radius: 12
        color: Theme.surface

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            Text {
                Layout.fillWidth: true
                text: I18n.tr(Rexlink.installed ? "Start Rexlink to connect your phone" : "Rexlink is not installed")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            SButton {
                visible: Rexlink.installed
                text: I18n.tr("Start")
                primary: true
                onClicked: Rexlink.start()
            }
        }
    }

    // ── состояние
    Rectangle {
        visible: Rexlink.connected && Rexlink.online
        Layout.fillWidth: true
        implicitHeight: 70
        radius: 12
        color: Theme.surface

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 18

            Row {
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Rexlink.batteryIcon(Rexlink.status.battery ?? -1, Rexlink.status.charging)
                    color: (Rexlink.status.battery ?? 100) <= 15 && !Rexlink.status.charging ? Theme.urgent : Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 26
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: `${Rexlink.status.battery ?? "—"}%`
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 5
                        font.bold: true
                    }
                    Text {
                        text: Rexlink.status.charging ? "charging" : `${Rexlink.status.temp ?? "—"}°C`
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Column {
                spacing: 3
                Text {
                    anchors.right: parent.right
                    text: `${Icons.wifi} ${Rexlink.status.net === "wifi" ? (Rexlink.status.wifi?.ssid || "Wi-Fi") + " · " + (Rexlink.status.wifi?.level ?? 0) + "/4" : "off"}`
                    color: Rexlink.status.net === "wifi" ? Theme.fg : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    anchors.right: parent.right
                    text: `${String.fromCodePoint(0xF08BD)} ${Rexlink.status.cell?.operator ?? "—"} ${Rexlink.status.cell?.gen ?? ""} · ${Rexlink.status.cell?.level ?? 0}/4`
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }

    // ── быстрые действия
    component Act: Rectangle {
        id: a
        property string icon
        property string label
        property bool on: false
        signal hit

        Layout.fillWidth: true
        implicitHeight: 62
        radius: 12
        color: on ? Theme.accent : aArea.pressed ? Theme.surfaceHi2 : aArea.containsMouse ? Theme.surfaceHi : Theme.surface

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Column {
            anchors.centerIn: parent
            spacing: 5
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: a.icon
                color: a.on ? Theme.bg : Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 2
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr(a.label)
                color: a.on ? Theme.bg : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
        }
        MouseArea {
            id: aArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: a.hit()
        }
    }

    GridLayout {
        visible: Rexlink.connected && Rexlink.online
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 8
        rowSpacing: 8

        Act { icon: String.fromCodePoint(0xF08D3); label: "Find"; on: Rexlink.dev?.ringing ?? false; onHit: Rexlink.ring() }
        Act { icon: String.fromCodePoint(0xF0552); label: "Send files"; onHit: { Ui.closeMenus(); Rexlink.show("files"); } }
        Act { icon: Icons.clipboard; label: "Get clipboard"; onHit: Rexlink.clipboardPull() }
        Act { icon: String.fromCodePoint(0xF0379); label: "Screen"; onHit: { Ui.closeMenus(); Rexlink.screenStart(); } }
        Act { icon: String.fromCodePoint(0xF0100); label: Rexlink.camera.running ? "Webcam on" : "Webcam"; on: Rexlink.camera.running ?? false; onHit: Rexlink.cameraToggle() }
        Act { icon: String.fromCodePoint(0xF0369); label: "Messages"; onHit: { Ui.closeMenus(); Rexlink.show("messages"); } }
    }

    // ── медиа на телефоне
    Rectangle {
        visible: Rexlink.online && !!Rexlink.media.title
        Layout.fillWidth: true
        implicitHeight: 58
        radius: 12
        color: Theme.surface

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 8
            spacing: 10

            Text {
                text: String.fromCodePoint(0xF075A)
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 1
            }
            Column {
                Layout.fillWidth: true
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: Rexlink.media.title ?? ""
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: [Rexlink.media.artist, Rexlink.media.app].filter(s => s).join(" · ")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }
            Repeater {
                model: [["prev", 0xF04AE], ["toggle", Rexlink.media.playing ? 0xF03E4 : 0xF040A], ["next", 0xF04AD]]
                Rectangle {
                    required property var modelData
                    implicitWidth: 32
                    implicitHeight: 32
                    radius: 16
                    color: mArea.containsMouse ? Theme.surfaceHi2 : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(parent.modelData[1])
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.iconSize
                    }
                    MouseArea {
                        id: mArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Rexlink.mediaAction(parent.modelData[0])
                    }
                }
            }
        }
    }

    // ── уведомления с телефона
    RowLayout {
        visible: Rexlink.online
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: `${I18n.tr("PHONE NOTIFICATIONS")} · ${Rexlink.notifs.length}`
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
            font.bold: true
        }
    }

    Text {
        visible: Rexlink.online && Rexlink.notifs.length === 0
        text: I18n.tr("Nothing new")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    Flickable {
        visible: Rexlink.online && Rexlink.notifs.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(nCol.implicitHeight, 360)
        contentHeight: nCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: nCol
            width: parent.width
            spacing: 6

            Repeater {
                model: Rexlink.notifs

                Rectangle {
                    id: n
                    required property var modelData
                    readonly property bool replying: root.replyKey === modelData.key

                    width: nCol.width
                    height: nc.implicitHeight + 20
                    radius: 12
                    color: nArea.containsMouse ? Theme.surfaceHi : Theme.surface

                    MouseArea {
                        id: nArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    ColumnLayout {
                        id: nc
                        x: 12
                        y: 10
                        width: parent.width - 24
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: `${n.modelData.app ?? ""}  ·  ${root.ago(n.modelData.time)}`
                                elide: Text.ElideRight
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 3
                            }
                            Text {
                                visible: n.modelData.clearable !== false
                                text: Icons.close
                                color: dArea.containsMouse ? Theme.urgent : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 1
                                MouseArea {
                                    id: dArea
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Rexlink.notifDismiss(n.modelData.key)
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
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
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }

                        // действия уведомления (и быстрый ответ)
                        Flow {
                            visible: (n.modelData.actions ?? []).length > 0 && !n.replying
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 6
                            Repeater {
                                model: n.modelData.actions ?? []
                                SButton {
                                    required property var modelData
                                    text: I18n.tr(modelData.title)
                                    implicitHeight: 28
                                    onClicked: {
                                        if (modelData.reply) {
                                            root.replyKey = n.modelData.key;
                                            root.replyAction = modelData.i;
                                        } else {
                                            Rexlink.notifAction(n.modelData.key, modelData.i);
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            visible: n.replying
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: 8
                                color: Theme.surfaceHi
                                border.width: 1
                                border.color: Theme.line

                                TextInput {
                                    id: replyInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 1
                                    clip: true
                                    onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                                    Keys.onReturnPressed: sendBtn.clicked()
                                    Keys.onEscapePressed: root.replyKey = ""
                                }
                            }
                            SButton {
                                id: sendBtn
                                text: I18n.tr("Send")
                                primary: true
                                implicitHeight: 32
                                onClicked: {
                                    if (replyInput.text.trim()) Rexlink.notifReply(n.modelData.key, root.replyAction, replyInput.text);
                                    root.replyKey = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
