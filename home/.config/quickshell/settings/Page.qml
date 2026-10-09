import QtQuick
import QtQuick.Layouts
import qs.services

// страница настроек: заголовок + прокручиваемая колонка карточек
Flickable {
    id: page

    property string title
    property string subtitle
    property string crumb: ""      // подстраница (хлебные крошки); пусто — корень раздела
    signal back
    default property alias content: col.data

    contentHeight: col.implicitHeight + 56
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: col

        x: 36
        y: 28
        width: page.width - 72
        spacing: 6

        // заголовок; на подстранице — «Раздел › Подстраница», раздел кликабелен (назад)
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: I18n.tr(page.title)
                color: page.crumb === "" ? Theme.fg : backArea.containsMouse ? Theme.fg : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 13
                font.bold: true

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    enabled: page.crumb !== ""
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.back()
                }
            }
            Text {
                visible: page.crumb !== ""
                text: "›"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 13
            }
            Text {
                Layout.fillWidth: true
                visible: page.crumb !== ""
                text: I18n.tr(page.crumb)
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 13
                font.bold: true
            }
        }

        Text {
            visible: page.subtitle !== ""
            Layout.fillWidth: true
            elide: Text.ElideMiddle
            Layout.bottomMargin: 10
            text: I18n.tr(page.subtitle)
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }

        Item {
            visible: page.subtitle === ""
            implicitHeight: 10
        }
    }
}
