import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.services

// звук: устройства, общая громкость (до 150%), громкость приложений
// header: true — с заголовком меню (на баре); в Настройках заголовок свой
ColumnLayout {
    id: root

    property bool input: false
    property bool meters: false   // индикаторы звука (пока микшер виден)
    property bool header: false

    readonly property PwNode current: input ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
    readonly property var devices: Pipewire.nodes.values.filter(n =>
        n.audio && n.type === (input ? PwNodeType.AudioSource : PwNodeType.AudioSink))
    readonly property var streams: Pipewire.nodes.values.filter(n =>
        n.audio && n.type === (input ? PwNodeType.AudioInStream : PwNodeType.AudioOutStream)
        && n.properties?.["application.name"] !== "qs-meter" && !String(n.name).startsWith("qs-meter"))

    function appName(n) {
        const p = n.properties ?? {};
        return p["application.name"] || n.description || n.name;
    }

    function appIcon(n) {
        const p = n.properties ?? {};
        return p["application.icon-name"] || p["application.process.binary"] || "";
    }

    PwObjectTracker { objects: root.devices.concat(root.streams) }

    width: 340
    spacing: 10

    component Caption: Text {
        Layout.topMargin: 2
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
        font.bold: true
    }

    MenuHeader {
        visible: root.header
        icon: root.input ? Icons.mic : Icons.volHigh
        title: root.input ? "Microphone" : "Sound"
        subtitle: root.current?.description ?? ""
        settingsPage: "sound"
    }

    // общая громкость
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 52
        radius: 12
        color: Theme.surface

        VolumeRow {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            node: root.current
            input: root.input
            meter: root.meters
        }
    }

    // устройства
    Caption { text: I18n.tr(root.input ? "INPUT DEVICE" : "OUTPUT DEVICE") }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: devCol.implicitHeight + 8
        radius: 12
        color: Theme.surface

        ColumnLayout {
            id: devCol
            x: 4
            y: 4
            width: parent.width - 8
            spacing: 2

            Repeater {
                model: root.devices

                Rectangle {
                    id: dev
                    required property PwNode modelData
                    readonly property bool selected: modelData === root.current

                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: 9
                    color: selected ? Theme.surfaceHi2 : devArea.containsMouse ? Theme.surfaceHi : "transparent"

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Rectangle {
                        visible: dev.selected
                        x: 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 16
                        radius: 2
                        color: Theme.accent
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 12
                        spacing: 10

                        Text {
                            text: I18n.tr(root.input ? Icons.mic : String.fromCodePoint(/hdmi|displayport/i.test(dev.modelData.description ?? "") ? 0xF0379 : 0xF02CB))
                            color: dev.selected ? Theme.accent : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize - 1
                        }
                        Text {
                            Layout.fillWidth: true
                            text: dev.modelData.description || dev.modelData.nickname || dev.modelData.name
                            elide: Text.ElideRight
                            color: dev.selected ? Theme.fg : Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: dev.selected
                        }
                    }

                    MouseArea {
                        id: devArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.input) Pipewire.preferredDefaultAudioSource = dev.modelData;
                            else Pipewire.preferredDefaultAudioSink = dev.modelData;
                        }
                    }
                }
            }
        }
    }

    // приложения
    Caption { text: I18n.tr("APPS") }

    Text {
        visible: root.streams.length === 0
        leftPadding: 2
        text: I18n.tr(root.input ? "No app is using the microphone" : "Nothing is playing")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    Repeater {
        model: root.streams

        Rectangle {
            id: app
            required property PwNode modelData

            Layout.fillWidth: true
            implicitHeight: appCol.implicitHeight + 20
            radius: 12
            color: Theme.surface

            ColumnLayout {
                id: appCol
                x: 14
                y: 10
                width: parent.width - 28
                spacing: 4

                RowLayout {
                    spacing: 8

                    IconImage {
                        readonly property string ic: root.appIcon(app.modelData)
                        visible: ic !== "" && status === Image.Ready
                        source: ic ? Quickshell.iconPath(ic, true) : ""
                        implicitSize: 16
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.appName(app.modelData)
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                }

                VolumeRow {
                    Layout.fillWidth: true
                    node: app.modelData
                    input: root.input
                    meter: root.meters
                }
            }
        }
    }
}
