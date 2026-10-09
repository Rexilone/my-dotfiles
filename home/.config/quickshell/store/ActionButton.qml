import QtQuick
import qs.services
import qs.settings

// кнопка действия для пакета: Установить / Открыть / в очереди / идёт установка
SButton {
    id: btn

    property string pkg: ""
    property bool aur: false
    property bool compact: false

    readonly property string busy: Store.busyWith(pkg)
    readonly property bool installed: Store.isInstalled(pkg)

    text: busy === "install" ? (!!Store.current?.pkgs?.includes(pkg) ? "Installing…" : "Queued")
        : busy === "remove" ? "Removing…"
        : installed ? (Store.canLaunch(pkg) ? "Open" : "Installed")
        : "Install"
    icon: busy ? "" : installed ? "" : String.fromCodePoint(0xF01DA)
    primary: !installed && !busy
    enabled: !busy && (!installed || Store.canLaunch(pkg))
    onClicked: installed ? Store.launch(pkg) : Store.install(pkg, aur)
}
