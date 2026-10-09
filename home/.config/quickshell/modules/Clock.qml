import QtQuick
import Quickshell
import qs.services

BarText {
    SystemClock {
        id: clock
        precision: Settings.clockFormat.includes("ss") ? SystemClock.Seconds : SystemClock.Minutes
    }

    // английская локаль, чтобы день недели был "Friday", а не "пятница"
    text: Qt.locale(I18n.locale).toString(clock.date, Settings.clockFormat)
}
