import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services

// всплывающее меню проводника в духе GTK 4: строки без значков, галочки, клавиши справа.
// Пункты: { text, key, check, off, danger, act } · { sep } · { header } · { zoom } (размер значков) ·
// { job } (ход копирования) · { openWith: путь } (программы для файла — подгружаются при раскрытии)
Item {
    id: mn

    required property var br

    anchors.fill: parent
    visible: false
    z: 100

    property var entries: []
    property real px: 0
    property real py: 0
    property bool toLeft: false         // меню выравнивается правым краем по точке (кнопки справа в шапке)
    property var apps: []
    property bool appsOpen: false
    readonly property bool checks: entries.some(e => e.check !== undefined)

    function openAt(x, y, list, alignRight) {
        entries = list;
        apps = [];
        appsOpen = false;
        px = x;
        py = y;
        toLeft = !!alignRight;
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
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: mn.close()
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        id: card
        x: Math.max(6, Math.min(mn.width - width - 6, mn.toLeft ? mn.px - width : mn.px))
        y: Math.max(6, Math.min(mn.height - height - 6, mn.py))
        width: Math.max(220, Math.min(340, list.implicitWidth + 12))
        height: Math.min(mn.height - 12, list.implicitHeight + 12)
        radius: 12
        color: FStyle.popover
        border.width: 1
        border.color: FStyle.sep
        MouseArea { anchors.fill: parent }

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
                        readonly property var e: modelData
                        readonly property bool plain: !e.sep && !e.header && !e.zoom && !e.job
                        Layout.fillWidth: true
                        spacing: 0

                        Rectangle {
                            visible: !!row.e.sep
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            Layout.bottomMargin: 6
                            Layout.leftMargin: 6
                            Layout.rightMargin: 6
                            implicitHeight: 1
                            color: FStyle.sep
                        }
                        Text {
                            visible: !!row.e.header
                            Layout.leftMargin: 12
                            Layout.topMargin: 4
                            Layout.bottomMargin: 4
                            text: row.e.header ?? ""
                            color: Theme.dim
                            font.family: FStyle.ui
                            font.pixelSize: FStyle.fsSmall
                            font.weight: Font.DemiBold
                        }

                        // размер значков: − 100 % +
                        RowLayout {
                            visible: !!row.e.zoom
                            Layout.fillWidth: true
                            Layout.margins: 4
                            spacing: 6
                            FButton {
                                Layout.fillWidth: true
                                flat: false
                                glyph: 0xF06EC
                                off: (mn.br.cfg.zoom ?? 1) <= mn.br.zoomSteps[0]
                                onClicked: mn.br.zoomBy(-1)
                            }
                            Text {
                                Layout.preferredWidth: 56
                                horizontalAlignment: Text.AlignHCenter
                                text: `${Math.round((mn.br.cfg.zoom ?? 1) * 100)}%`
                                color: Theme.fg
                                font.family: FStyle.ui
                                font.pixelSize: FStyle.fs
                            }
                            FButton {
                                Layout.fillWidth: true
                                flat: false
                                glyph: 0xF06ED
                                off: (mn.br.cfg.zoom ?? 1) >= mn.br.zoomSteps[mn.br.zoomSteps.length - 1]
                                onClicked: mn.br.zoomBy(1)
                            }
                        }

                        // ход копирования: название, полоска, сколько, отмена
                        ColumnLayout {
                            visible: !!row.e.job
                            Layout.fillWidth: true
                            Layout.margins: 8
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: mn.br.job?.title ?? I18n.tr("Done")
                                elide: Text.ElideMiddle
                                color: Theme.fg
                                font.family: FStyle.ui
                                font.pixelSize: FStyle.fs
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 6
                                    radius: 3
                                    color: FStyle.field
                                    Rectangle {
                                        width: parent.width * (mn.br.job?.total ? Math.min(1, mn.br.job.done / mn.br.job.total) : mn.br.job ? 0 : 1)
                                        height: parent.height
                                        radius: 3
                                        color: Theme.accent
                                    }
                                }
                                FButton {
                                    visible: !!mn.br.job
                                    circular: true
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    flat: false
                                    glyph: 0xF0156
                                    glyphSize: FStyle.icon - 2
                                    tip: I18n.tr("Cancel")
                                    onClicked: mn.br.cancelJob()
                                }
                            }
                            Text {
                                visible: !!mn.br.job?.total
                                text: mn.br.job?.total ? `${mn.br.human(mn.br.job.done)} ${I18n.tr("of")} ${mn.br.human(mn.br.job.total)}` : ""
                                color: Theme.dim
                                font.family: FStyle.ui
                                font.pixelSize: FStyle.fsSmall
                            }
                        }

                        Rectangle {
                            visible: row.plain
                            Layout.fillWidth: true
                            implicitHeight: 34
                            implicitWidth: line.implicitWidth + 24
                            radius: 6
                            opacity: row.e.off ? 0.45 : 1
                            color: itemArea.pressed && !row.e.off ? FStyle.press : itemArea.containsMouse && !row.e.off ? FStyle.hover : "transparent"

                            RowLayout {
                                id: line
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10
                                Text {
                                    visible: mn.checks
                                    Layout.preferredWidth: 16
                                    text: row.e.check ? String.fromCodePoint(0xF012C) : ""
                                    color: Theme.fg
                                    font.family: FStyle.glyphs
                                    font.pixelSize: FStyle.icon
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.e.text ?? ""
                                    elide: Text.ElideRight
                                    color: row.e.danger ? Theme.urgent : Theme.fg
                                    font.family: FStyle.ui
                                    font.pixelSize: FStyle.fs
                                }
                                Text {
                                    text: row.e.openWith ? String.fromCodePoint(mn.appsOpen ? 0xF0143 : 0xF0142) : (row.e.key ?? "")
                                    color: Theme.dim
                                    font.family: row.e.openWith ? FStyle.glyphs : FStyle.ui
                                    font.pixelSize: FStyle.fsSmall
                                }
                            }
                            MouseArea {
                                id: itemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (row.e.off) return;
                                    if (row.e.openWith) {
                                        mn.appsOpen = !mn.appsOpen;
                                        if (mn.appsOpen && !mn.apps.length) {
                                            appsProc.command = ["python3", mn.br.helper, "apps", row.e.openWith];
                                            appsProc.running = true;
                                        }
                                        return;
                                    }
                                    mn.close();
                                    row.e.act?.();
                                }
                            }
                        }

                        // «Открыть с помощью»: программы для этого типа
                        Repeater {
                            model: row.e.openWith && mn.appsOpen ? mn.apps : []
                            Rectangle {
                                id: app
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: 6
                                color: appArea.containsMouse ? FStyle.hover : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 18
                                    anchors.rightMargin: 12
                                    spacing: 10
                                    IconImage {
                                        implicitSize: 18
                                        source: app.modelData.icon ? Quickshell.iconPath(app.modelData.icon, "application-x-executable") : ""
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: app.modelData.name
                                        elide: Text.ElideRight
                                        color: Theme.fg
                                        font.family: FStyle.ui
                                        font.pixelSize: FStyle.fs
                                    }
                                    Text {
                                        visible: app.modelData.default
                                        text: I18n.tr("default")
                                        color: Theme.dim
                                        font.family: FStyle.ui
                                        font.pixelSize: FStyle.fsSmall
                                    }
                                }
                                MouseArea {
                                    id: appArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        const target = row.e.openWith;
                                        mn.close();
                                        for (const it of mn.br.selItems.length ? mn.br.selItems : [{ path: target }])
                                            mn.br.openWith(it, app.modelData.id);
                                    }
                                }
                            }
                        }
                        Text {
                            visible: !!row.e.openWith && mn.appsOpen && !mn.apps.length
                            Layout.leftMargin: 18
                            Layout.topMargin: 4
                            Layout.bottomMargin: 6
                            text: I18n.tr(appsProc.running ? "Loading…" : "No apps for this type")
                            color: Theme.dim
                            font.family: FStyle.ui
                            font.pixelSize: FStyle.fsSmall
                        }
                    }
                }
            }
        }
    }
}
