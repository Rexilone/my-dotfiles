import QtQuick
import QtQuick.Layouts
import qs.services
import qs.screenshot

// низ проводника: сколько объектов, что выделено, свободное место; ход копирования с отменой
Item {
    id: sbar

    required property var br

    implicitHeight: 34

    readonly property var sel: br.selItems
    readonly property real selSize: sel.filter(i => !i.dir).reduce((a, i) => a + (i.size ?? 0), 0)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 14
        spacing: 12

        Text {
            visible: !sbar.br.job
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: sbar.sel.length
                ? `${I18n.tr("Selected")}: ${sbar.sel.length}${sbar.selSize ? "   ·   " + sbar.br.human(sbar.selSize) : ""}${sbar.sel.length === 1 ? "   ·   " + sbar.sel[0].name : ""}`
                : `${I18n.plural(sbar.br.shown.length, "item", "items", "объект", "объекта", "объектов")}: ${sbar.br.shown.length}`
                  + (sbar.br.mode === "dir" && sbar.br.freeSpace ? `   ·   ${I18n.tr("free")} ${sbar.br.freeSpace}` : "")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }

        // копирование/перемещение
        RowLayout {
            visible: !!sbar.br.job
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: sbar.br.job?.title ?? ""
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
                elide: Text.ElideRight
                Layout.maximumWidth: 320
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Theme.surfaceHi2
                Rectangle {
                    width: parent.width * (sbar.br.job?.total ? Math.min(1, sbar.br.job.done / sbar.br.job.total) : 0)
                    height: parent.height
                    radius: 3
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 150 } }
                }
            }
            Text {
                text: sbar.br.job?.total ? `${sbar.br.human(sbar.br.job.done)} / ${sbar.br.human(sbar.br.job.total)}` : ""
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
            ToolButton { icon: 0xF0156; tip: "Cancel"; onClicked: sbar.br.cancelJob() }
        }

        // размер значков
        Row {
            visible: !sbar.br.job
            spacing: 2
            ToolButton { icon: 0xF0374; tip: "Smaller"; key: "Ctrl+−"; onClicked: Settings.setFiles("zoom", Math.max(0.5, (sbar.br.cfg.zoom ?? 1) - 0.25)) }
            ToolButton { icon: 0xF0415; tip: "Bigger"; key: "Ctrl++"; onClicked: Settings.setFiles("zoom", Math.min(2, (sbar.br.cfg.zoom ?? 1) + 0.25)) }
        }
    }
}
