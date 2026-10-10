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
    // пока здесь двигают ползунки, нижний индикатор громкости не всплывает
    onShownChanged: Ui.menusOpen = Math.max(0, Ui.menusOpen + (shown ? 1 : -1))
    Component.onDestruction: if (shown) Ui.menusOpen = Math.max(0, Ui.menusOpen - 1)
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

    SSection { text: I18n.tr("Indicator") }

    SCard {
        icon: String.fromCodePoint(0xF0A1D)
        title: "Pop-up at the bottom"
        desc: "When volume, microphone or brightness change, and while voice typing listens (Super+H)"
        SSwitch {
            checked: Settings.moduleOn("osd", true)
            onToggled: v => Settings.setModule("osd", v)
        }
    }
}
