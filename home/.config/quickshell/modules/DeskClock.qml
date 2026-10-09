import QtQuick
import Quickshell
import qs.services

// часы: шрифт, формат, дата — в Настройках → Виджеты
Column {
    id: root

    property var cfg: ({})
    readonly property string fmt: cfg.format ?? "HH:mm"

    spacing: 0

    SystemClock {
        id: clock
        precision: root.fmt.includes("ss") ? SystemClock.Seconds : SystemClock.Minutes
    }

    Text {
        text: Qt.locale(I18n.locale).toString(clock.date, root.fmt)
        color: Theme.fg
        font.family: root.cfg.font || Theme.font
        font.pixelSize: 96
        font.bold: true
        font.letterSpacing: -2
    }

    Text {
        visible: root.cfg.showDate ?? true
        leftPadding: 6
        text: Qt.locale(I18n.locale).toString(clock.date, "dddd, d MMMM")
        color: Theme.muted
        font.family: root.cfg.font || Theme.font
        font.pixelSize: 22
    }
}
