import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.services

// плеер (MPRIS): обложка, трек, прогресс с перемоткой, управление
Item {
    id: root

    property bool active: false
    property int index: 0
    property int artSize: 104

    readonly property var players: Mpris.players.values
    // по умолчанию — тот, что играет
    readonly property MprisPlayer player: {
        if (players.length === 0) return null;
        const playing = players.findIndex(p => p.isPlaying);
        const i = index > 0 ? index % players.length : (playing >= 0 ? playing : 0);
        return players[i];
    }

    function fmt(sec) {
        if (!isFinite(sec) || sec < 0) return "0:00";
        sec = Math.floor(sec);
        const m = Math.floor(sec / 60), s = sec % 60;
        return `${m}:${s < 10 ? "0" : ""}${s}`;
    }

    implicitWidth: 380
    implicitHeight: artSize

    // позиция в MPRIS не обновляется сама
    Timer {
        interval: 1000
        repeat: true
        running: root.active && (root.player?.isPlaying ?? false)
        onTriggered: root.player.positionChanged()
    }

    Column {
        anchors.centerIn: parent
        visible: !root.player
        spacing: 8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String.fromCodePoint(0xF075A)  // music-note
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 30
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("Nothing playing")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
    }

    RowLayout {
        anchors.fill: parent
        visible: !!root.player
        spacing: 14

        // обложка
        ClippingRectangle {
            implicitWidth: root.artSize
            implicitHeight: root.artSize
            radius: 14
            color: Theme.surfaceHi

            Text {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: String.fromCodePoint(0xF075A)
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 34
            }

            Image {
                id: art
                anchors.fill: parent
                source: root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: root.artSize * 2
                sourceSize.height: root.artSize * 2
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            // источник (клик — следующий плеер, если их несколько)
            Text {
                text: (root.player?.identity ?? "") + (root.players.length > 1 ? `  ·  ${root.players.length} players` : "")
                color: srcArea.containsMouse && root.players.length > 1 ? Theme.fg : Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1

                MouseArea {
                    id: srcArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.players.length > 1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.index = (root.players.indexOf(root.player) + 1) || 1
                }
            }

            Text {
                Layout.fillWidth: true
                text: I18n.tr(root.player?.trackTitle || "Unknown")
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                text: root.player?.trackArtist || ""
                elide: Text.ElideRight
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }

            // прогресс
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 6
                implicitHeight: 12
                visible: (root.player?.lengthSupported ?? false) && root.player.length > 0

                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.surfaceHi2

                    Rectangle {
                        width: parent.width * Math.min(1, (root.player?.position ?? 0) / (root.player?.length || 1))
                        height: parent.height
                        radius: 2
                        color: Theme.fg

                        Behavior on width { NumberAnimation { duration: 900 } }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    enabled: root.player?.canSeek ?? false
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        root.player.position = Math.max(0, Math.min(1, mouse.x / width)) * root.player.length;
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: root.player?.lengthSupported ? `${root.fmt(root.player.position)} / ${root.fmt(root.player.length)}` : ""
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }

                Item { Layout.fillWidth: true }

                // управление
                Row {
                    spacing: 4

                    component Ctrl: Rectangle {
                        id: c
                        property string icon
                        property bool primary: false
                        property bool can: true
                        signal hit

                        width: primary ? 34 : 28
                        height: width
                        radius: width / 2
                        opacity: can ? 1 : 0.35
                        color: primary ? (cArea.containsMouse ? Theme.fgHover : Theme.fg) : (cArea.containsMouse ? Theme.surfaceHi2 : "transparent")

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            anchors.centerIn: parent
                            text: c.icon
                            color: c.primary ? Theme.bg : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: c.primary ? Theme.iconSize + 1 : Theme.iconSize
                        }

                        MouseArea {
                            id: cArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: c.can
                            cursorShape: Qt.PointingHandCursor
                            onClicked: c.hit()
                        }
                    }

                    Ctrl {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: String.fromCodePoint(0xF04AE)  // skip-previous
                        can: root.player?.canGoPrevious ?? false
                        onHit: root.player.previous()
                    }
                    Ctrl {
                        primary: true
                        icon: root.player?.isPlaying ? Icons.pause : Icons.play
                        can: root.player?.canTogglePlaying ?? false
                        onHit: root.player.togglePlaying()
                    }
                    Ctrl {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: String.fromCodePoint(0xF04AD)  // skip-next
                        can: root.player?.canGoNext ?? false
                        onHit: root.player.next()
                    }
                }
            }
        }
    }
}
