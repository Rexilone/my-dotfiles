import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.services

// polkit-агент: окно ввода пароля для pkexec и приложений, которым нужны права
PanelWindow {
    id: root

    readonly property AuthFlow flow: agent.flow
    readonly property bool open: agent.isActive

    onOpenChanged: {
        if (open) {
            targetScreen = Settings.activeScreen();
            input.text = "";
            input.forceActiveFocus();
        }
    }

    PolkitAgent {
        id: agent
    }

    property var targetScreen: Settings.activeScreen()
    screen: targetScreen
    visible: open
    color: "transparent"
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    // размытие только под карточкой (Персонализация → Прозрачность)
    BackgroundEffect.blurRegion: Theme.blurOn ? blurReg : null
    Region {
        id: blurReg
        item: polkitCard
        radius: polkitCard.radius
    }
    WlrLayershell.namespace: "quickshell-polkit"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.5
    }

    Rectangle {
        id: polkitCard
        anchors.centerIn: parent
        width: 420
        height: column.implicitHeight + 40
        radius: Theme.radius + 2
        color: Theme.panel
        border.width: 1
        border.color: Theme.faint

        ColumnLayout {
            id: column

            x: 20
            y: 20
            width: parent.width - 40
            spacing: 12

            RowLayout {
                spacing: 12

                Text {
                    text: Icons.lock
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 20
                }

                Text {
                    text: I18n.tr("Authentication required")
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.flow?.message ?? ""
                wrapMode: Text.Wrap
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 36
                radius: 8
                color: Theme.surfaceHi
                border.width: 1
                border.color: root.flow?.failed ? Theme.urgent : input.activeFocus ? Theme.line : Theme.faint

                TextInput {
                    id: input

                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                    focus: true
                    enabled: root.flow?.isResponseRequired ?? false

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !input.text
                        text: I18n.tr((root.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || "Password")
                        color: Theme.dim
                        font: input.font
                    }

                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: root.flow?.cancelAuthenticationRequest()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: I18n.tr(root.flow?.failed ? "Wrong password, try again" : (root.flow?.supplementaryMessage ?? ""))
                wrapMode: Text.Wrap
                color: root.flow?.failed || root.flow?.supplementaryIsError ? Theme.urgent : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }

            Text {
                Layout.alignment: Qt.AlignRight
                text: I18n.tr("Enter — confirm · Esc — cancel")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    function submit() {
        if (!flow || !flow.isResponseRequired) return;
        flow.submit(input.text);
        input.text = "";
    }
}
