import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.settings

// приложения, скрытые с демонстрации экрана (Super+G): кто скрыт и кнопка «Показать»
ColumnLayout {
    id: root

    width: 340
    spacing: 10

    MenuHeader {
        icon: String.fromCodePoint(0xF0209)  // eye-off
        title: "Hidden from screencast"
        subtitle: I18n.ru ? `${CastHide.apps.length} ${I18n.plural(CastHide.apps.length, "", "", "приложение скрыто", "приложения скрыты", "приложений скрыто")} от зрителей`
                : CastHide.apps.length === 1 ? "1 app is blacked out for viewers"
                : `${CastHide.apps.length} apps are blacked out for viewers`
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: CastHide.apps

            Rectangle {
                id: row
                required property string modelData
                readonly property var entry: DesktopEntries.heuristicLookup(modelData)
                readonly property bool focused: !!Niri.focusedWindow && Niri.focusedWindow.app_id === modelData

                Layout.fillWidth: true
                implicitHeight: 52
                radius: 10
                color: Theme.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 12

                    IconImage {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        source: Quickshell.iconPath(row.entry?.icon ?? "", "application-x-executable")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: row.entry?.name || row.modelData
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr(row.focused ? "Active window" : row.modelData)
                            elide: Text.ElideRight
                            color: row.focused ? Theme.warn : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }

                    SButton {
                        text: I18n.tr("Show")
                        icon: String.fromCodePoint(0xF0208)  // eye
                        onClicked: CastHide.unhide(row.modelData)
                    }
                }
            }
        }
    }

    // скрыть активное окно отсюда же (то же, что Super+G)
    SButton {
        Layout.fillWidth: true
        visible: !!Niri.focusedWindow && !CastHide.focusedHidden && Niri.focusedWindow.app_id !== "org.quickshell"
        text: `${I18n.tr("Hide")} ${Niri.focusedWindow?.title ? "“" + Niri.focusedWindow.title.slice(0, 28) + "”" : I18n.tr("active window")}`
        icon: String.fromCodePoint(0xF0209)
        onClicked: CastHide.hideApp(Niri.focusedWindow.app_id)
    }

    Text {
        Layout.fillWidth: true
        text: I18n.tr("Super+G hides or shows the active app. Viewers see a black box in its place.")
        wrapMode: Text.Wrap
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }
}
