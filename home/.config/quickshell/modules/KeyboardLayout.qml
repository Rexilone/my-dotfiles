import QtQuick
import qs.services

BarText {
    readonly property string name: Niri.layoutName.toLowerCase()

    readonly property var codes: ({
        english: "en", russian: "ru", ukrainian: "ua", belarusian: "by", kazakh: "kz", german: "de",
        french: "fr", spanish: "es", italian: "it", polish: "pl", czech: "cz", turkish: "tr",
        japanese: "jp", korean: "kr", chinese: "cn", georgian: "ge", armenian: "am", arabic: "ar",
    })
    text: codes[name.split(/[ (]/)[0]] ?? name.slice(0, 2)

    onClicked: Niri.action(["switch-layout", "next"])
    onWheel: w => Niri.action(["switch-layout", w.angleDelta.y > 0 ? "prev" : "next"])
}
