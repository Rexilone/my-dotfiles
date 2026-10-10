import QtQuick
import QtQuick.Layouts
import qs.services
import qs.settings

// полоса задач внизу магазина: что ставится сейчас, очередь, итог, журнал
Rectangle {
    id: bar

    property bool showLog: false
    // последняя задача: текущая или только что завершённая
    readonly property var job: Store.current ?? Store.jobs.slice().reverse().find(j => j.state !== "queued" && j.state !== "cancelled" || j.line) ?? null
    readonly property bool active: !!Store.current
    readonly property bool shown: !!job && (active || !dismissed)
    property bool dismissed: false

    Connections {
        target: Store
        function onJobsChanged() { if (Store.current) bar.dismissed = false; }
    }

    Layout.preferredHeight: shown ? col.implicitHeight + 24 : 0
    visible: Layout.preferredHeight > 0
    color: Theme.surface
    clip: true

    Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    function title(j) {
        if (!j) return "";
        const name = j.kind === "upgrade" ? I18n.tr("System update") : Store.displayName(j.pkgs[0]);
        const verb = j.state === "running" ? I18n.tr(j.kind === "install" ? "Installing" : j.kind === "remove" ? "Removing" : "Updating")
            : j.state === "done" ? I18n.tr(j.kind === "install" ? "Installed" : j.kind === "remove" ? "Removed" : "Updated")
            : j.state === "failed" ? I18n.tr("Failed") : I18n.tr("Cancelled");
        if (j.kind === "upgrade")
            return I18n.tr(j.state === "running" ? "Updating the system…" : j.state === "done" ? "System updated" : j.state === "failed" ? "System update failed" : "System update cancelled");
        return `${verb}: ${name}`;
    }

    ColumnLayout {
        id: col
        x: 24
        y: 12
        width: parent.width - 48
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Text {
                id: jobIcon
                text: String.fromCodePoint(bar.active ? 0xF0772 : bar.job?.state === "done" ? 0xF012C : 0xF0028)
                color: bar.job?.state === "failed" ? Theme.urgent : bar.job?.state === "done" ? Theme.fg : Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.iconSize + 4

                RotationAnimation on rotation {
                    running: bar.active
                    from: 0
                    to: 360
                    duration: 1400
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) jobIcon.rotation = 0
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: bar.title(bar.job) + (Store.queued.length ? `   ·   ${I18n.tr("queued")}: ${Store.queued.length}` : "")
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true
                    }
                    Text {
                        visible: bar.active && (bar.job?.total ?? 0) > 0
                        text: `${bar.job?.step ?? 0}/${bar.job?.total ?? 0}`
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: bar.job?.line ?? ""
                    elide: Text.ElideRight
                    color: bar.job?.state === "failed" ? Theme.urgent : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
                // прогресс: шаги pacman, иначе бегущая полоска
                Rectangle {
                    visible: bar.active
                    Layout.fillWidth: true
                    implicitHeight: 3
                    radius: 2
                    color: Theme.surfaceHi2
                    clip: true

                    Rectangle {
                        id: fill
                        readonly property bool known: (bar.job?.total ?? 0) > 0
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                        width: known ? parent.width * bar.job.step / bar.job.total : parent.width * 0.3
                        x: known ? 0 : sweep.pos * (parent.width * 1.3) - parent.width * 0.3

                        Behavior on width { NumberAnimation { duration: 250 } }
                    }
                    NumberAnimation {
                        id: sweep
                        property real pos: 0
                        target: sweep
                        property: "pos"
                        running: bar.active && !fill.known
                        from: 0
                        to: 1
                        duration: 1300
                        loops: Animation.Infinite
                    }
                }
            }

            SButton {
                visible: bar.job?.state === "done" && bar.job?.kind === "install" && Store.canLaunch(bar.job.pkgs[0])
                text: "Open"
                primary: true
                onClicked: Store.launch(bar.job.pkgs[0])
            }
            SButton {
                text: bar.showLog ? "Hide log" : "Log"
                enabled: !!bar.job?.log
                onClicked: bar.showLog = !bar.showLog
            }
            SButton {
                visible: !bar.active
                icon: String.fromCodePoint(0xF0156)
                onClicked: {
                    bar.dismissed = true;
                    bar.showLog = false;
                    Store.clearFinished();
                }
            }
        }

        // журнал
        Rectangle {
            visible: bar.showLog
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            radius: 8
            color: Theme.bg

            Flickable {
                id: logFlick
                anchors.fill: parent
                anchors.margins: 10
                contentHeight: logText.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

                TextEdit {
                    id: logText
                    width: logFlick.width
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    text: bar.job?.log ?? ""
                    color: Theme.muted
                    selectionColor: Theme.accent
                    font.family: Settings.monoFont || Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }
}
