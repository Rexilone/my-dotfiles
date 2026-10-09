import QtQuick
import Quickshell
import qs.services

// значок приложения: из каталога / темы значков, иначе — буква на плашке
Item {
    id: root

    property string pkg: ""
    property int size: 48

    implicitWidth: size
    implicitHeight: size

    readonly property string src: pkg ? Store.iconFor(pkg) : ""
    // картинка каталога не читается (нет плагина формата) — значок из темы, если есть
    property bool failed: false
    onSrcChanged: failed = false
    readonly property string fallback: pkg ? Quickshell.iconPath(Store.byPkg[pkg]?.icon?.startsWith("stock:") ? Store.byPkg[pkg].icon.slice(6) : pkg, true) : ""

    Image {
        id: img
        anchors.fill: parent
        visible: status === Image.Ready
        source: root.failed ? root.fallback : root.src
        onStatusChanged: if (status === Image.Error && !root.failed) root.failed = true
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
    }

    Rectangle {
        anchors.fill: parent
        visible: img.status !== Image.Ready
        radius: root.size * 0.26
        color: Theme.surfaceHi2

        Text {
            anchors.centerIn: parent
            text: (Store.displayName(root.pkg) || "?").replace(/^(lib|python-|ttf-)/, "").charAt(0).toUpperCase()
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: root.size * 0.42
            font.bold: true
        }
    }
}
