pragma Singleton
import QtQuick
import Quickshell

// долгие операции шелла для «острова» в баре: копирование в проводнике и т.п.
// set(id, { title, done, total }) — начать или обновить, remove(id) — закончилась
Singleton {
    id: root

    property var list: []

    function set(id, job) {
        const i = list.findIndex(j => j.id === id);
        const j = Object.assign({ id }, job);
        list = i < 0 ? list.concat([j]) : list.map(x => x.id === id ? j : x);
    }
    function remove(id) {
        list = list.filter(j => j.id !== id);
    }
}
