import QtQuick
import qs.services

// индикатор записи в баре
// ЛКМ — стоп (или сохранить повтор), ПКМ — пауза, СКМ — меню записи
BarText {
    id: root

    signal openMenu

    visible: Recorder.recording || Recorder.countdown > 0 || Recorder.replayActive
    active: true
    color: Recorder.recording && !Recorder.paused || Recorder.countdown > 0 ? Theme.urgent : Theme.dim
    text: Recorder.countdown > 0 ? `${Icons.record} ${Recorder.countdown}`
        : Recorder.recording ? `${Recorder.paused ? Icons.pause : Icons.record} ${Recorder.elapsedText}`
        : `${Icons.replay} ${Recorder.replaySeconds}s`

    // мигание точки во время записи
    SequentialAnimation on opacity {
        running: Recorder.recording && !Recorder.paused
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.opacity = 1
        NumberAnimation { to: 0.45; duration: 800; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
    }

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) openMenu();
        else if (mouse.button === Qt.RightButton) Recorder.togglePause();
        else if (Recorder.recording || Recorder.countdown > 0) Recorder.stop();
        else Recorder.saveReplay();
    }
}
