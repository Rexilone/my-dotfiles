import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services

// контекстное меню проводника: [{ icon, text, key, check, off, sep, act, openWith }]
// «Открыть в…» (openWith: путь) подгружает список программ при раскрытии
Item {
    id: mn

    required property var br

    anchors.fill: parent
    visible: false
    z: 100

    property var entries: []
    property real px: 0
    property real py: 0
    property var apps: []
    property bool appsOpen: false

    function openAt(x, y, list) {
        entries = list;
        apps = [];
        appsOpen = false;
        px = x;
        py = y;
        visible = true;
    }
    function close() {
        visible = false;
        br.forceViewFocus();
    }

    Process {
        id: appsProc
        stdout: StdioCollector {
            onStreamFinished: { try { mn.apps = JSON.parse(text).apps ?? []; } catch (e) { mn.apps = []; } }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mn.close()
    }

    Rectangle {
        id: card
        x: Math.max(6, Math.min(mn.width - width - 6, mn.px))
        y: Math.max(6, Math.min(mn.height - height - 6, mn.py))
        width: 270
        height: Math.min(mn.height - 12, list.implicitHeight + 12)
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        Flickable {
            anchors.fill: parent
            anchors.margins: 6
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: list
                width: parent.width
                spacing: 0

                Repeater {
                    model: mn.entries

                    ColumnLayout {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0

                        Rectangle {
                            visible: !!row.modelData.sep
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            Layout.bottomMargin: 4
                            implicitHeight: 1
                            color: Theme.surfaceHi2
                        }

                        Rectangle {
                            visible: !row.modelData.sep
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: 8
                            opacity: row.modelData.off ? 0.4 : 1
                            color: itemArea.containsMouse && !row.modelData.off ? Theme.surfaceHi2 : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10
                                Text {
                                    Layout.preferredWidth: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    text: row.modelData.check !== undefined ? (row.modelData.check ? String.fromCodePoint(0xF012C) : "")
                                        : row.modelData.icon ? String.fromCodePoint(row.modelData.icon) : ""
                                    color: row.modelData.check ? Theme.accent : Theme.muted
                                    font.family: Theme.font
                                    font.pixelSize: Theme.iconSize - 1
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: I18n.tr(row.modelData.text ?? "")
                                    elide: Text.ElideRight
                                    color: row.modelData.danger ? Theme.urgent : Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 1
                                }
                                Text {
                                    text: row.modelData.openWith ? String.fromCodePoint(mn.appsOpen ? 0xF0143 : 0xF0140) : (row.modelData.key ?? "")
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 3
                                }
                            }
                            MouseArea {
                                id: itemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: row.modelData.off ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (row.modelData.off) return;
                                    if (row.modelData.openWith) {
                                        mn.appsOpen = !mn.appsOpen;
                                        if (mn.appsOpen && !mn.apps.length) {
                                            appsProc.command = ["python3", mn.br.helper, "apps", row.modelData.openWith];
                                            appsProc.running = true;
                                        }
                                        return;
                                    }
                                    mn.close();
                                    row.modelData.act?.();
                                }
                            }
                        }

                        // «Открыть в…»: программы для этого типа
                        Repeater {
                            model: row.modelData.openWith && mn.appsOpen ? mn.apps : []
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radius: 8
                                color: appArea.containsMouse ? Theme.surfaceHi2 : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 38
                                    anchors.rightMargin: 10
                                    spacing: 8
                                    IconImage {
                                        implicitSize: 16
                                        source: parent.parent.modelData.icon ? Quickshell.iconPath(parent.parent.modelData.icon, "application-x-executable") : ""
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: parent.parent.modelData.name + (parent.parent.modelData.default ? `   ·   ${I18n.tr("default")}` : "")
                                        elide: Text.ElideRight
                                        color: Theme.fg
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 2
                                    }
                                }
                                MouseArea {
                                    id: appArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const target = row.modelData.openWith;
                                        mn.close();
                                        for (const it of mn.br.selItems.length ? mn.br.selItems : [{ path: target }])
                                            mn.br.openWith(it, parent.modelData.id);
                                    }
                                }
                            }
                        }
                        Text {
                            visible: !!row.modelData.openWith && mn.appsOpen && !mn.apps.length
                            Layout.leftMargin: 38
                            Layout.bottomMargin: 4
                            text: I18n.tr(appsProc.running ? "Loading…" : "No apps for this type")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }
            }
        }
    }
}
