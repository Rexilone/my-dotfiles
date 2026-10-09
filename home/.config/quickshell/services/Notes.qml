pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// заметки календаря + напоминания (заметки со временем)
// напоминания, время которых прошло пока ПК был выключен, приходят при следующем запуске
Singleton {
    id: root

    // источник правды — объект в памяти; хранилище только пишем на диск
    property var notes: ({})   // "yyyy-MM-dd" -> [{ id, text, time, notified }]

    function key(d) {
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function list(d) {
        const arr = notes[key(d)] ?? [];
        return arr.slice().sort((a, b) => (a.time || "99:99").localeCompare(b.time || "99:99"));
    }

    function has(d) {
        return (notes[key(d)] ?? []).length > 0;
    }

    function normTime(t) {
        const m = (t ?? "").trim().match(/^(\d{1,2}):?(\d{2})$/);
        if (!m) return "";
        const h = Number(m[1]), min = Number(m[2]);
        if (h > 23 || min > 59) return "";
        return `${h < 10 ? "0" : ""}${h}:${m[2]}`;
    }

    function save(next) {
        notes = next;
        store.notes = JSON.parse(JSON.stringify(next));
        file.writeAdapter();
    }

    function add(d, text, time) {
        text = text.trim();
        if (!text) return;
        const k = key(d);
        const next = Object.assign({}, notes);
        const t = normTime(time);
        const due = t ? new Date(`${k}T${t}:00`) : null;
        next[k] = (next[k] ?? []).concat([{
            id: `${Date.now()}${Math.floor(Math.random() * 1000)}`,
            text,
            time: t,
            // напоминание в прошлом не присылаем — его только что создали
            notified: due ? due <= new Date() : false,
        }]);
        save(next);
    }

    function remove(d, id) {
        const k = key(d);
        const next = Object.assign({}, notes);
        next[k] = (next[k] ?? []).filter(n => n.id !== id);
        if (next[k].length === 0) delete next[k];
        save(next);
    }

    function check() {
        const now = new Date();
        let changed = false;
        const next = {};
        for (const k in notes) {
            next[k] = notes[k].map(n => {
                if (!n.time || n.notified) return n;
                const due = new Date(`${k}T${n.time}:00`);
                if (due > now) return n;
                const missed = now - due > 2 * 60 * 1000;
                const when = missed ? `${Qt.locale(I18n.locale).toString(due, "d MMM")}, ${n.time}` : n.time;
                Quickshell.execDetached(["notify-send", "-a", "Calendar", "-u", "critical",
                    "-i", "x-office-calendar", missed ? `Missed reminder · ${when}` : `Reminder · ${when}`, n.text]);
                changed = true;
                return Object.assign({}, n, { notified: true });
            });
        }
        if (changed) save(next);
    }

    FileView {
        id: file
        path: Quickshell.statePath("notes.json")
        blockLoading: true
        printErrors: false

        JsonAdapter {
            id: store
            property var notes: ({})
        }
    }

    Component.onCompleted: {
        try {
            notes = JSON.parse(JSON.stringify(store.notes ?? {}));
        } catch (e) {
            notes = {};
        }
        check();
    }

    Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: root.check()
    }
}
