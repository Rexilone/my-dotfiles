pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// диски и флешки (lsblk + udisksctl): разделы не системы — подключённые и нет.
// Флешки по желанию подключаются сами, с уведомлением «Открыть» (Настройки → Файлы).
Singleton {
    id: root

    readonly property var cfg: Settings.files ?? {}
    // [{ dev, parent, name, size, free, fstype, mount, removable }]
    property var drives: []
    property var known: ({})          // устройства, которые уже видели (новые — подключили только что)
    property bool first: true
    signal mounted(string dev, string path)

    // системные разделы и служебные типы разделов не показываем
    readonly property var systemMounts: ["/", "/boot", "/boot/efi", "/efi", "/home", "/var", "/var/log", "/var/cache/pacman/pkg", "/nix", "/nix/store", "/usr", "/opt", "/srv", "/tmp", "[SWAP]"]
    readonly property var hiddenTypes: ["c12a7328-f81f-11d2-ba4b-00a0c93ec93b", "21686148-6449-6e6f-744e-656564454649",
        "e3c9e316-0b5c-4db8-817d-f92df00215ae", "de94bba4-06d1-4d40-a16a-bfd50179d6ac", "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"]

    function human(n) {
        const u = I18n.ru ? ["Б", "КБ", "МБ", "ГБ", "ТБ"] : ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (n >= 1000 && i < u.length - 1) { n /= 1000; i++; }
        return `${n < 10 && i ? n.toFixed(1) : Math.round(n)} ${u[i]}`;
    }

    function parse(text) {
        let tree = [];
        try { tree = JSON.parse(text).blockdevices ?? []; } catch (e) { return; }
        const out = [];
        const walk = (n, parent, rmParent) => {
            const removable = !!(n.rm || n.hotplug || n.tran === "usb" || rmParent);
            const mounts = (n.mountpoints ?? []).filter(m => m);
            const kids = n.children ?? [];
            if ((n.type === "part" || (n.type === "disk" && !kids.length)) && n.fstype
                && !["swap", "LVM2_member", "crypto_LUKS", "linux_raid_member", "zfs_member"].includes(n.fstype)
                && !hiddenTypes.includes((n.parttype ?? "").toLowerCase())
                && !mounts.some(m => systemMounts.includes(m) || m.startsWith("/var/") || m.startsWith("/nix/"))
                && !String(n.name).startsWith("zram") && !String(n.name).startsWith("loop")) {
                out.push({
                    dev: n.path,
                    parent: parent ? parent.path : n.path,
                    name: n.label || n.partlabel || (n.parttypename && !/microsoft basic|linux filesystem/i.test(n.parttypename) ? n.parttypename : "")
                          || (removable ? (parent?.model ?? I18n.tr("Flash drive")) : I18n.tr("Disk")),
                    size: n.size ?? 0,
                    sizeText: human(n.size ?? 0),
                    free: n.fsavail ?? null,
                    fstype: n.fstype,
                    mount: mounts[0] ?? "",
                    removable,
                });
            }
            for (const c of kids) walk(c, n.type === "disk" ? n : parent, removable);
        };
        for (const n of tree) walk(n, null, false);
        drives = out;

        // новые флешки: подключить сами и сказать
        const seen = {};
        for (const d of out) {
            seen[d.dev] = true;
            if (first || known[d.dev] || !d.removable) continue;
            if (!d.mount && (cfg.automount ?? true)) mount(d.dev, true);
            else if (d.mount && (cfg.driveNotify ?? true)) notifyDrive(d, d.mount);
        }
        known = seen;
        first = false;
    }

    function notifyDrive(d, path) {
        Quickshell.execDetached(["sh", "-c",
            'a=$(notify-send -a "$1" -i drive-removable-media -A open="$4" "$2" "$3"); [ "$a" = open ] && "$HOME/.local/bin/rexilone-files" "$5"',
            "sh", I18n.tr("Files"), `${I18n.tr("Connected")}: ${d.name}`, `${d.sizeText}   ·   ${path}`, I18n.tr("Open"), path]);
    }

    // ── подключить / отключить / извлечь (udisks2; для внутренних дисков спросит пароль)
    property var pending: []
    function mount(dev, announce) {
        pending = pending.concat([{ op: "mount", dev, announce: !!announce }]);
        if (!job.running) run();
    }
    function unmount(dev) {
        pending = pending.concat([{ op: "unmount", dev }]);
        if (!job.running) run();
    }
    function eject(d) {
        // все разделы этого устройства, затем выключить его
        const parts = drives.filter(x => x.parent === d.parent && x.mount).map(x => x.dev);
        pending = pending.concat(parts.map(dev => ({ op: "unmount", dev }))).concat([{ op: "power-off", dev: d.parent }]);
        if (!job.running) run();
    }
    function run() {
        if (!pending.length) {
            scan.running = true;
            return;
        }
        const j = pending[0];
        pending = pending.slice(1);
        job.cur = j;
        job.command = ["udisksctl", j.op, "-b", j.dev];
        job.running = true;
    }
    Process {
        id: job
        property var cur: null
        stdout: StdioCollector { id: jobOut }
        stderr: StdioCollector { id: jobErr }
        onExited: code => {
            const j = job.cur;
            if (code === 0 && j.op === "mount") {
                const m = /at (.+?)\.?\s*$/.exec(jobOut.text.trim());
                const path = m ? m[1] : "";
                root.mounted(j.dev, path);
                const d = root.drives.find(x => x.dev === j.dev);
                if (j.announce && d && (root.cfg.driveNotify ?? true)) root.notifyDrive(d, path);
            } else if (code === 0 && j.op === "power-off") {
                Quickshell.execDetached(["notify-send", "-a", I18n.tr("Files"), "-i", "media-eject", I18n.tr("Safe to remove")]);
            } else if (code !== 0) {
                Quickshell.execDetached(["notify-send", "-a", I18n.tr("Files"), "-i", "dialog-error", I18n.tr("Disk"),
                    jobErr.text.trim().split("\n").pop() || I18n.tr("Failed")]);
            }
            root.run();
        }
    }

    Process {
        id: scan
        command: ["lsblk", "-J", "-b", "-o", "NAME,PATH,LABEL,PARTLABEL,PARTTYPE,PARTTYPENAME,SIZE,FSTYPE,FSAVAIL,MOUNTPOINTS,RM,HOTPLUG,TYPE,TRAN,MODEL"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    // события udev (вставили/вынули, подключили раздел) вместо опроса; редкий опрос — на всякий случай
    Process {
        running: true
        // setpriv --pdeathsig: умирает вместе с шеллом (иначе после перезапуска/падения шелла остаётся висеть)
        command: ["setpriv", "--pdeathsig", "TERM", "udevadm", "monitor", "--udev", "--subsystem-match=block"]
        stdout: SplitParser {
            onRead: line => { if (/ (add|remove|change) /.test(line)) rescan.restart(); }
        }
    }
    Timer {
        id: rescan
        interval: 700
        onTriggered: if (!job.running) scan.running = true
    }
    Timer {
        running: true
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!job.running) scan.running = true
    }
    // окно «Файлов» открыто — свежие данные о свободном месте
    function refresh() {
        if (!job.running) scan.running = true;
    }
}
