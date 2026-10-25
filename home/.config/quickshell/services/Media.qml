pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// переключение треков для любого плеера (MPRIS). Браузеры часто не умеют «следующий»/«предыдущий»
// (YouTube без плейлиста — CanGoNext = false): тогда «следующий» — перемотка в конец (сайт сам включит
// следующее видео), «предыдущий» — к началу трека. Как и у плееров, «предыдущий» после 5 секунд — к началу
Singleton {
    id: root

    function canNext(p) {
        return !!p && (p.canGoNext || (p.canSeek && p.lengthSupported && p.length > 0));
    }
    function canPrevious(p) {
        return !!p && (p.canGoPrevious || p.canSeek);
    }
    function next(p) {
        if (!p) return;
        if (p.canGoNext) p.next();
        else if (p.canSeek && p.lengthSupported && p.length > 1) p.position = p.length - 0.5;
    }
    function previous(p) {
        if (!p) return;
        if (p.canSeek && p.position > 5) p.position = 0;
        else if (p.canGoPrevious) p.previous();
        else if (p.canSeek) p.position = 0;
    }

    // плеер для клавиш: тот, что играет, иначе первый
    readonly property var current: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null

    // медиаклавиши (niri): qs ipc call media next | previous | toggle
    IpcHandler {
        target: "media"
        function next(): void { root.next(root.current); }
        function previous(): void { root.previous(root.current); }
        function toggle(): void { if (root.current?.canTogglePlaying) root.current.togglePlaying(); }
    }
}
