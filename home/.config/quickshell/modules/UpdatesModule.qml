import QtQuick
import qs.services

// обновления системы: иконка и число; клик — обновить в терминале, ПКМ — проверить сейчас
BarText {
    visible: !Updates.installed || Updates.count > 0 || Updates.checking
    active: Updates.count > 0
    color: Updates.count > 0 ? Theme.accent : Theme.dim
    text: !Updates.installed ? `${String.fromCodePoint(0xF06B0)} ?`
        : Updates.checking && Updates.count === 0 ? String.fromCodePoint(0xF06B0)
        : `${String.fromCodePoint(0xF06B0)} ${Updates.count}`
    onClicked: mouse => {
        if (!Updates.installed) Updates.install();
        else if (mouse.button === Qt.RightButton) Updates.refresh();
        else Updates.upgrade();
    }
}
