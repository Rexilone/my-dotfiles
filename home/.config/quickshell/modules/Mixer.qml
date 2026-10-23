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
            property bool pick: false
            readonly property string rule: (Settings.audioRoutes?.[root.input ? "in" : "out"] ?? {})[AudioRoutes.appKey(modelData)] ?? ""

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

                // куда идёт звук этого приложения (запоминается: services/AudioRoutes.qml)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: 8
                    color: routeArea.containsMouse || app.pick ? Theme.surfaceHi2 : Theme.surfaceHi

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8
                        Text {
                            text: String.fromCodePoint(root.input ? 0xF036C : 0xF04C3)
                            color: app.rule ? Theme.accent : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize - 2
                        }
                        Text {
                            Layout.fillWidth: true
                            text: app.rule ? (root.devices.find(d => d.name === app.rule)?.description ?? app.rule) : I18n.tr("Same as the system")
                            elide: Text.ElideRight
                            color: app.rule ? Theme.fg : Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            text: String.fromCodePoint(app.pick ? 0xF0143 : 0xF0140)
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize - 2
                        }
                    }
                    MouseArea {
                        id: routeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: app.pick = !app.pick
                    }
                }

                Repeater {
                    model: app.pick ? [null].concat(root.devices) : []

                    Rectangle {
                        id: opt
                        required property var modelData
                        readonly property string devName: modelData ? modelData.name : ""
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 8
                        color: optArea.containsMouse ? Theme.surfaceHi : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 30
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: opt.modelData ? (opt.modelData.description || opt.modelData.name) : I18n.tr("Same as the system")
                            elide: Text.ElideRight
                            color: opt.devName === app.rule ? Theme.accent : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: opt.devName === app.rule
                        }
                        MouseArea {
                            id: optArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                AudioRoutes.route(app.modelData, opt.devName);
                                app.pick = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
