import QtQuick
import qs.services

// живая картинка с устройства (экран или камера). Служба пишет кадры JPEG-файлами
// по кругу и сообщает о каждом; два Image по очереди: новый кадр показываем, когда он
// загрузился, — без мигания. Пока элемент активен, канал «смотрится» (служба шлёт кадры).
Item {
    id: root

    property string channel: ""
    property bool active: false

    readonly property var frame: Rexlink.frames[channel] ?? null
    readonly property int frameWidth: frame?.w ?? 0
    readonly property int frameHeight: frame?.h ?? 0
    readonly property bool live: !!frame && shown >= 0

    // прямоугольник картинки внутри элемента
    readonly property real scaleK: frameWidth ? Math.min(width / frameWidth, height / frameHeight) : 1
    readonly property real contentW: frameWidth * scaleK
    readonly property real contentH: frameHeight * scaleK
    readonly property real contentX: (width - contentW) / 2
    readonly property real contentY: (height - contentH) / 2

    // точка в элементе → доли 0…1 картинки
    function norm(x, y) {
        return [Math.max(0, Math.min(1, (x - contentX) / contentW)), Math.max(0, Math.min(1, (y - contentY) / contentH))];
    }

    property int shown: -1      // какой из двух Image сейчас на экране
    property int loading: 0

    property string watched: ""
    function sync() {
        const want = active && Rexlink.connected && channel ? channel : "";
        if (want === watched) return;
        if (watched) Rexlink.watch(watched, false);
        watched = want;
        if (want) Rexlink.watch(want, true);
    }
    onActiveChanged: sync()
    onChannelChanged: { shown = -1; sync(); }
    Connections {
        target: Rexlink
        function onConnectedChanged() { root.watched = ""; root.sync(); }
    }
    Component.onCompleted: sync()
    Component.onDestruction: if (watched) Rexlink.watch(watched, false)

    onFrameChanged: {
        if (!frame || !active) return;
        const img = imgs.itemAt(shown === 0 ? 1 : 0);
        if (!img) return;
        if (img.status === Image.Loading) return;     // не успеваем — пропускаем кадр
        img.source = `file://${frame.path}?${frame.seq}`;
    }

    Repeater {
        id: imgs
        model: 2
        Image {
            required property int index
            x: root.contentX
            y: root.contentY
            width: root.contentW
            height: root.contentH
            cache: false
            asynchronous: true
            smooth: true
            mipmap: true
            visible: root.shown === index
            onStatusChanged: if (status === Image.Ready && source != "") root.shown = index
        }
    }
}
