import QtQuick
import QtQuick.Layouts
import qs.services
import Quickshell
import qs.modules

// Звук: устройства вывода/ввода, громкость до 150%, громкость приложений
Page {
    id: page
    title: "Sound"

    // индикаторы звука работают, пока страница на экране
    readonly property bool shown: visible && (Window.window?.visible ?? false)
    subtitle: "Output and input devices, volume and per-app volume"

    SSection { text: I18n.tr("Output") }

    Mixer {
        id: outMixer
        Layout.fillWidth: true
        meters: page.shown
    }

    SSection { text: I18n.tr("Input") }

    Mixer {
        id: inMixer
        Layout.fillWidth: true
        meters: page.shown
        input: true
    }

    SCard {
        Layout.topMargin: 10
        icon: String.fromCodePoint(0xF1120)
        title: "More sound settings"
        desc: "Open pavucontrol for profiles and advanced options"
        clickable: true
        onClicked: Quickshell.execDetached(["pavucontrol"])
    }
}
