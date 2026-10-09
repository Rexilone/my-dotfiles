import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.services

// переключатель обоев (как в caelestia), выезжает сверху: qs ipc call wallpaper toggle (Super+W)
// ←/→ или колесо — листать, Enter — поставить, печатать — поиск, Esc — закрыть
PanelWindow {
    id: root

    property bool open: false
    property bool shown: false
    property string query: ""

    readonly property var results: {
        const q = query.trim().toLowerCase();
        return q ? Wallpapers.items.filter(w => w.name.toLowerCase().includes(q)) : Wallpapers.items;
    }
    readonly property var selected: results[view.currentIndex] ?? null

    function focusCurrent() {
        const i = results.findIndex(w => w.path === Wallpapers.current);
        view.currentIndex = Math.max(0, i);
    }

    function applySelected() {
        if (!selected) return;
        Wallpapers.apply(selected.path);
        open = false;
    }

    onOpenChanged: {
        if (open) {
            targetScreen = Settings.activeScreen();
            hideTimer.stop();
            query = "";
            search.text = "";
            Wallpapers.refresh();
            shown = true;
            search.forceActiveFocus();
        } else {
            hideTimer.restart();
        }
    }

    Connections {
        target: Wallpapers
        function onItemsChanged() { root.focusCurrent(); }
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): void { root.open = !root.open; }
        function hide(): void { root.open = false; }
        function random(): void { Wallpapers.random(); }
    }

    Timer {
        id: hideTimer
        interval: Theme.animSlow + 60
        onTriggered: root.shown = false
    }

    // открывается на мониторе, где сейчас курсор/фокус
    property var targetScreen: Settings.activeScreen()
    screen: targetScreen
    visible: shown
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
        item: panel
        radius: panel.radius
    }
    WlrLayershell.namespace: "quickshell-wallpaper"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // лёгкое затемнение сверху, чтобы видеть сами обои
    Rectangle {
        anchors.fill: parent
        opacity: root.open ? 1 : 0
        gradient: Gradient {
            GradientStop { position: 0; color: "#aa000000" }
            GradientStop { position: 0.55; color: "#00000000" }
        }

        Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }
    }

    Rectangle {
        id: panel

        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 80, 1180)
        height: content.implicitHeight + 36
        // выезжает сверху, из-под бара
        y: root.open ? Theme.barHeight + 12 : -height - 20
        opacity: root.open ? 1 : 0
        radius: 22
        color: Theme.panel
        border.width: 1
        border.color: Theme.surfaceHi2

        Behavior on y { NumberAnimation { duration: Theme.animSlow + 60; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: content

            x: 18
            y: 18
            width: parent.width - 36
            spacing: 14

            // ── верх: заголовок, поиск, кнопки
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: String.fromCodePoint(0xF0E09)  // image-multiple
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize + 3
                }

                Text {
                    text: I18n.tr("Wallpapers")
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }

                Text {
                    text: Wallpapers.loading ? "loading…" : `${root.results.length}`
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }

                Item { Layout.fillWidth: true }

                // поиск
                Rectangle {
                    implicitWidth: 260
                    implicitHeight: 32
                    radius: 10
                    color: Theme.surface
                    border.width: search.activeFocus ? 1 : 0
                    border.color: Theme.line

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: Icons.search
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize - 1
                        }

                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            color: Theme.fg
                            selectionColor: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            clip: true

                            onTextChanged: {
                                root.query = text;
                                view.currentIndex = 0;
                            }

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !search.text
                                text: I18n.tr("Search…")
                                color: Theme.dim
                                font: search.font
                            }

                            Keys.onPressed: event => {
                                const k = event.key;
                                if (k === Qt.Key_Escape) root.open = false;
                                else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.applySelected();
                                else if (k === Qt.Key_Right || k === Qt.Key_Tab || k === Qt.Key_Down) view.incrementCurrentIndex();
                                else if (k === Qt.Key_Left || k === Qt.Key_Backtab || k === Qt.Key_Up) view.decrementCurrentIndex();
                                else return;
                                event.accepted = true;
                            }
                        }
                    }
                }

                component HeadButton: Rectangle {
                    id: hb
                    property string icon
                    property string label
                    signal hit

                    implicitWidth: hbRow.implicitWidth + 20
                    implicitHeight: 32
                    radius: 10
                    color: hbArea.pressed ? Theme.surfaceHi2 : hbArea.containsMouse ? Theme.surfaceHi : Theme.surface

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Row {
                        id: hbRow
                        anchors.centerIn: parent
                        spacing: 7

                        Text {
                            text: hb.icon
                            color: hbArea.containsMouse ? Theme.fg : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.iconSize - 1
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: I18n.tr(hb.label)
                            visible: hb.label !== ""
                            color: hbArea.containsMouse ? Theme.fg : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: hbArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hb.hit()
                    }
                }

                HeadButton {
                    icon: String.fromCodePoint(0xF049D)  // shuffle
                    label: "Random"
                    onHit: {
                        Wallpapers.random();
                        root.open = false;
                    }
                }

                HeadButton {
                    icon: Icons.folder
                    onHit: {
                        Wallpapers.openFolder();
                        root.open = false;
                    }
                }
            }

            // ── карусель
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 230

                Text {
                    anchors.centerIn: parent
                    visible: !Wallpapers.loading && root.results.length === 0
                    text: Wallpapers.items.length ? "Nothing found" : `No images in ${Wallpapers.dir}`
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }

                ListView {
                    id: view

                    readonly property int cardW: 336
                    readonly property int cardH: 189

                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    spacing: 16
                    model: root.results
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // выбранная карточка всегда по центру
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: (width - cardW) / 2
                    preferredHighlightEnd: (width + cardW) / 2
                    highlightMoveDuration: 280
                    highlightMoveVelocity: -1
                    cacheBuffer: 2000

                    delegate: Item {
                        id: card

                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: ListView.isCurrentItem
                        readonly property bool isActive: modelData.path === Wallpapers.current

                        width: view.cardW
                        height: view.height

                        Item {
                            id: frame
                            anchors.centerIn: parent
                            width: view.cardW
                            height: view.cardH
                            scale: card.isCurrent ? 1.06 : 0.9
                            opacity: card.isCurrent ? 1 : hover.containsMouse ? 0.85 : 0.5

                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            ClippingRectangle {
                                anchors.fill: parent
                                radius: 14
                                color: Theme.surface

                                Image {
                                    anchors.fill: parent
                                    source: "file://" + card.modelData.thumb
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    mipmap: true
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 64
                                    opacity: card.isCurrent ? 1 : 0
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: "#00000000" }
                                        GradientStop { position: 1; color: "#cc000000" }
                                    }
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                            }

                            // рамка выбранной
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -4
                                radius: 18
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.accent
                                opacity: card.isCurrent ? 1 : 0

                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }

                            // «сейчас стоят»
                            Rectangle {
                                visible: card.isActive
                                x: 10
                                y: 10
                                implicitWidth: badge.implicitWidth + 16
                                implicitHeight: 22
                                radius: 8
                                color: Theme.accent

                                Row {
                                    id: badge
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Rectangle {
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: Theme.bg
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: I18n.tr("current")
                                        color: Theme.bg
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 3
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 12
                                width: parent.width - 110
                                elide: Text.ElideRight
                                opacity: card.isCurrent ? 1 : 0
                                text: I18n.tr(card.modelData.name)
                                color: "#ffffff"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: true

                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 12
                                opacity: card.isCurrent ? 0.8 : 0
                                text: card.modelData.size
                                color: "#ffffff"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 3

                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: frame
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (card.isCurrent) root.applySelected();
                                else view.currentIndex = card.index;
                            }
                        }
                    }

                    WheelHandler {
                        onWheel: ev => (ev.angleDelta.y > 0 || ev.angleDelta.x > 0) ? view.decrementCurrentIndex() : view.incrementCurrentIndex()
                    }
                }
            }

            // ── подсказки
            RowLayout {
                Layout.fillWidth: true

                // точки-индикатор позиции
                Row {
                    spacing: 5
                    visible: root.results.length > 1 && root.results.length <= 30

                    Repeater {
                        model: root.results.length

                        Rectangle {
                            required property int index
                            width: index === view.currentIndex ? 16 : 6
                            height: 6
                            radius: 3
                            color: index === view.currentIndex ? Theme.fg : Theme.line

                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: I18n.tr("←/→  browse   ·   Enter  apply   ·   type to search   ·   Esc  close")
                    color: Theme.line
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }
}
