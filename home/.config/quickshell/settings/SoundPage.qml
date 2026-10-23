import QtQuick
import QtQuick.Layouts
import qs.services
import Quickshell
import qs.modules
import Quickshell.Services.Pipewire

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

    // запомненные устройства приложений: выбираются в списке «Приложения» выше
    SSection { text: I18n.tr("Apps and devices") }

    SCard {
        visible: page.rules.length === 0
        icon: String.fromCodePoint(0xF04C3)
        title: "Each app can play on its own device"
        desc: "Pick a device under an app above — e.g. Discord to headphones, music to speakers. The choice is remembered"
    }

    readonly property var rules: {
        const r = Settings.audioRoutes ?? {};
        const devName = n => Pipewire.nodes.values.find(d => d.name === n)?.description ?? n;
        return Object.entries(r.out ?? {}).map(([app, n]) => ({ app, n, input: false, dev: devName(n) }))
            .concat(Object.entries(r.in ?? {}).map(([app, n]) => ({ app, n, input: true, dev: devName(n) })));
    }

    Repeater {
        model: page.rules
        SCard {
            id: rc
            required property var modelData
            icon: String.fromCodePoint(modelData.input ? 0xF036C : 0xF04C3)
            title: modelData.app
            desc: `→ ${modelData.dev}`
            SButton {
                icon: Icons.trash
                danger: true
                onClicked: Settings.setAudioRoute(rc.modelData.input, rc.modelData.app, "")
            }
        }
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
