import QtQuick
import QtQuick.Layouts
import qs.services

// Телефон → Буфер обмена: синхронизация и история
ColumnLayout {
    Layout.fillWidth: true
    spacing: 6

    readonly property var st: Rexlink.settings

    SCard {
        icon: String.fromCodePoint(0xF014D)
        title: "Shared clipboard"
        desc: st.wlClipboard === false ? "Needs the wl-clipboard package" : "Copy on one device — paste on the other. Repeats aren't sent back"
        SSwitch {
            checked: st.clipboard ?? true
            onToggled: v => Rexlink.set("clipboard", v)
        }
    }
    SCard {
        icon: String.fromCodePoint(0xF02E9)
        title: "Images"
        desc: "Also sync screenshots and copied pictures (up to 25 MB)"
        SSwitch {
            checked: st.clipboardImages ?? true
            onToggled: v => Rexlink.set("clipboardImages", v)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 14
        spacing: 8

        SSection {
            Layout.fillWidth: true
            text: I18n.tr("History")
        }
        SButton {
            text: "Get from the device"
            icon: String.fromCodePoint(0xF01DA)
            enabled: Rexlink.online
            onClicked: Rexlink.clipboardPull()
        }
        SButton {
            visible: Rexlink.clips.length > 0
            text: "Clear"
            icon: Icons.trash
            onClicked: Rexlink.clipboardClear()
        }
    }

    PhoneEmpty {
        visible: Rexlink.clips.length === 0
        icon: String.fromCodePoint(0xF014D)
        text: "Nothing synced yet"
        hint: "Android 10+ doesn't let apps read the clipboard in the background: turn on the Rexlink accessibility service on the phone, then copied text is sent by itself."
    }

    Repeater {
        model: Rexlink.clips

        Rectangle {
            id: clip
            required property var modelData

            Layout.fillWidth: true
            implicitHeight: Math.max(56, body.implicitHeight + 28)
            radius: 10
            color: Theme.surface

            RowLayout {
                id: body
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 18
                anchors.rightMargin: 16
                spacing: 16

                Text {
                    Layout.alignment: Qt.AlignTop
                    text: String.fromCodePoint(clip.modelData.dir === "in" ? 0xF01DA : 0xF0552)
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize + 2
                }
                Text {
                    visible: clip.modelData.kind === "text"
                    Layout.fillWidth: true
                    text: clip.modelData.text ?? ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                Item {
                    visible: clip.modelData.kind === "image"
                    Layout.fillWidth: true
                    implicitHeight: img.height
                    Image {
                        id: img
                        source: clip.modelData.url ?? ""
                        fillMode: Image.PreserveAspectFit
                        height: Math.min(160, sourceSize.height)
                        width: Math.min(parent.width, sourceSize.width * height / Math.max(1, sourceSize.height))
                        asynchronous: true
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignTop
                    text: `${I18n.tr(clip.modelData.dir === "in" ? "from" : "to")} ${clip.modelData.device || I18n.tr("devices")}   ·   ${clip.modelData.time}`
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }
}
