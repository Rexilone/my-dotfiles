import QtQuick
import QtQuick.Layouts
import qs.services

// Телефон → Веб-камера: камера устройства как обычная веб-камера (v4l2loopback) + превью
ColumnLayout {
    id: tab

    property bool active: false

    readonly property var cam: Rexlink.settings.camera ?? ({})
    readonly property var c: Rexlink.camera
    readonly property string vdev: Rexlink.settings.webcamResolved ?? ""

    Layout.fillWidth: true
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: I18n.tr("Works in OBS, browsers, Telegram and Zoom — pick “Rexlink Camera” there.")
            wrapMode: Text.Wrap
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
        SButton {
            text: tab.c.running ? "Stop" : "Turn on"
            icon: String.fromCodePoint(tab.c.running ? 0xF04DB : 0xF05A0)
            primary: !tab.c.running
            danger: !!tab.c.running
            enabled: Rexlink.online && Rexlink.settings.ffmpeg !== false
            onClicked: Rexlink.cameraToggle()
        }
    }

    // превью
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(380, width * 9 / 16)
        radius: 12
        color: Theme.surface
        clip: true

        PhoneFrame {
            id: fv
            anchors.fill: parent
            anchors.margins: 6
            channel: "camera"
            active: tab.active && !!tab.c.running
            visible: !!tab.c.running
        }
        PhoneEmpty {
            anchors.centerIn: parent
            visible: !tab.c.running || !fv.live
            icon: String.fromCodePoint(0xF05A0)
            text: tab.c.running ? "Starting the camera…" : Rexlink.online ? "The camera is off" : "The device is not connected"
            hint: tab.c.running ? "The first time, allow camera access on the device" : ""
        }
        Rectangle {
            visible: !!tab.c.running && fv.live
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 14
            implicitWidth: liveRow.implicitWidth + 18
            implicitHeight: 26
            radius: 13
            color: Qt.rgba(0, 0, 0, 0.55)
            Row {
                id: liveRow
                anchors.centerIn: parent
                spacing: 6
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: Theme.rec }
                Text {
                    text: `${tab.c.w ?? fv.frameWidth}×${tab.c.h ?? fv.frameHeight}`
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }

    SCard {
        Layout.topMargin: 6
        icon: String.fromCodePoint(0xF0379)
        title: tab.vdev ? `${I18n.tr("Virtual camera")}: ${tab.vdev}` : "No virtual camera"
        desc: tab.c.error ? tab.c.error
            : tab.vdev ? "Pick “Rexlink Camera” in the video call app"
            : "Needs the v4l2loopback-dkms module (./install.sh --with-webcam). Set up loads it now and after every boot"

        SButton {
            visible: !tab.vdev
            text: "Set up"
            primary: true
            onClicked: Rexlink.setupWebcam()
        }
    }

    SSection { text: I18n.tr("Options") }

    SCard {
        icon: String.fromCodePoint(0xF0100)
        title: "Camera"
        SChoice {
            options: [{ value: "back", label: "Back" }, { value: "front", label: "Front" }]
            current: tab.cam.facing ?? "back"
            onPicked: v => Rexlink.cameraSwitch(v)
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF05A0)
        title: "Resolution"
        desc: "Applies the next time the camera turns on"
        SChoice {
            options: [{ value: 640, label: "480p" }, { value: 1280, label: "720p" }, { value: 1920, label: "1080p" }]
            current: tab.cam.width ?? 1280
            onPicked: v => Rexlink.set("camera", { width: v, height: v === 640 ? 480 : v === 1280 ? 720 : 1080 })
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF040A)
        title: "Frame rate"
        SChoice {
            options: [{ value: 24, label: "24" }, { value: 30, label: "30" }, { value: 60, label: "60" }]
            current: tab.cam.fps ?? 30
            onPicked: v => Rexlink.set("camera", { fps: v })
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF0467)
        title: "Rotation"
        desc: "If the phone stands upright"
        SChoice {
            options: [{ value: 0, label: "0°" }, { value: 90, label: "90°" }, { value: 180, label: "180°" }, { value: 270, label: "270°" }]
            current: tab.cam.rotate ?? 0
            onPicked: v => Rexlink.set("camera", { rotate: v })
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF04E1)
        title: "Mirror"
        SSwitch {
            checked: !!tab.cam.mirror
            onToggled: v => Rexlink.set("camera", { mirror: v })
        }
    }
}
