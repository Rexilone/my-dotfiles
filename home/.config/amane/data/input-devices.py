#!/usr/bin/env python3
"""Устройства ввода для Настроек → Peripherals, одной строкой JSON.

Источники: /proc/bus/input/devices (узлы event/js) и свойства udev из /run/udev/data
(ID_INPUT_KEYBOARD / MOUSE / TOUCHPAD / TABLET / JOYSTICK, размер планшета в мм) —
всё читается без прав root. Узлы одного физического устройства (USB-приёмник даёт
по 3–4 узла) склеиваются по bus:vendor:product. Батареи — из UPower.
"""
import json, os, re, subprocess

TYPES = ["tablet", "gamepad", "touchpad", "mouse", "keyboard"]
UDEV_KEY = {
    "ID_INPUT_TABLET": "tablet",
    "ID_INPUT_JOYSTICK": "gamepad",
    "ID_INPUT_TOUCHPAD": "touchpad",
    "ID_INPUT_MOUSE": "mouse",
    "ID_INPUT_KEYBOARD": "keyboard",
}
BUS = {"0003": "usb", "0005": "bluetooth", "0011": "ps2", "0018": "i2c", "0019": "builtin", "0006": "virtual"}


def udev_props(event):
    """Свойства udev узла /dev/input/eventN (major 13, minor 64+N)."""
    props = {}
    try:
        # номер устройства берём из sysfs: у узлов event32+ он не равен 64+N
        major, minor = open(f"/sys/class/input/{event}/dev").read().strip().split(":")
        with open(f"/run/udev/data/c{major}:{minor}") as f:
            for line in f:
                if line.startswith("E:") and "=" in line:
                    k, v = line[2:].strip().split("=", 1)
                    props[k] = v
    except (OSError, ValueError):
        pass
    return props


def parse_proc():
    try:
        text = open("/proc/bus/input/devices").read()
    except OSError:
        return []
    out = []
    for block in text.strip().split("\n\n"):
        d = {"handlers": [], "name": "", "bus": "", "vendor": "", "product": ""}
        for line in block.splitlines():
            if line.startswith("I:"):
                m = re.search(r"Bus=(\w+) Vendor=(\w+) Product=(\w+)", line)
                if m:
                    d["bus"], d["vendor"], d["product"] = m.groups()
            elif line.startswith("N:"):
                d["name"] = line.split("=", 1)[1].strip().strip('"')
            elif line.startswith("H:"):
                d["handlers"] = line.split("=", 1)[1].split()
        out.append(d)
    return out


def batteries():
    """UPower: модель -> процент (клавиатуры, мыши, геймпады)."""
    res = []
    try:
        dump = subprocess.run(["upower", "-d"], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.TimeoutExpired):
        return res
    for block in dump.split("\n\n"):
        model = re.search(r"^\s*model:\s*(.+)$", block, re.M)
        pct = re.search(r"^\s*percentage:\s*([\d.]+)%", block, re.M)
        if model and pct and "DisplayDevice" not in block:
            res.append((model.group(1).strip().lower(), round(float(pct.group(1)))))
    return res


def main():
    groups = {}
    for d in parse_proc():
        events = [h for h in d["handlers"] if h.startswith("event")]
        js = [h for h in d["handlers"] if h.startswith("js")]
        if not events:
            continue
        props = udev_props(events[0])
        kinds = {t for k, t in UDEV_KEY.items() if props.get(k) == "1"}
        # udev ставит JOYSTICK и лишним узлам приёмников клавиатур — геймпад только с узлом js
        if not js:
            kinds.discard("gamepad")
        if not kinds:
            continue  # кнопки питания, микрофоны, HDMI-аудио…
        key = f'{d["bus"]}:{d["vendor"]}:{d["product"]}'
        g = groups.setdefault(key, {
            "id": key, "names": [], "kinds": set(), "bus": BUS.get(d["bus"], "other"),
            "js": [], "events": [], "vendor": props.get("ID_VENDOR", "").replace("_", " "),
            "model": props.get("ID_MODEL", "").replace("_", " "),
        })
        g["names"].append(d["name"])
        g["kinds"] |= kinds
        g["js"] += js
        g["events"] += events
        # планшет-экран (INPUT_PROP_DIRECT): libinput применяет к нему матрицу калибровки,
        # к обычному планшету — нет (только «левша» = поворот на 180°)
        try:
            bits = int(open(f"/sys/class/input/{events[0]}/device/properties").read().split()[-1], 16)
            if bits & 0x2:
                g["direct"] = True
        except (OSError, ValueError, IndexError):
            pass
        if "ID_INPUT_WIDTH_MM" in props:
            g["widthMm"] = float(props["ID_INPUT_WIDTH_MM"])
            g["heightMm"] = float(props.get("ID_INPUT_HEIGHT_MM", 0))

    bats = batteries()
    devices = []
    for g in groups.values():
        names = sorted(g["names"], key=len)
        name = names[0]
        low = " ".join(names).lower()
        # одно главное назначение: приёмник «клавиатура+мышь» — это клавиатура и т.п.
        kind = next(t for t in TYPES if t in g["kinds"])
        if kind == "mouse" and "keyboard" in g["kinds"] and "keyboard" in name.lower():
            kind = "keyboard"
        if kind == "keyboard" and "mouse" in g["kinds"] and "mouse" in name.lower():
            kind = "mouse"
        # у планшета имя узла пера: «Wacom One by Wacom M Pen» -> без « Pen»
        if kind == "tablet":
            name = re.sub(r"\s+(Pen|Stylus|Finger|Pad)$", "", name)
        # планшетом управляет OpenTabletDriver: показываем настоящее имя из его настроек
        driver = ""
        if name.startswith("OpenTabletDriver"):
            driver = "otd"
            g["bus"] = "usb"
            try:
                prof = json.load(open(os.path.expanduser("~/.config/OpenTabletDriver/settings.json")))["Profiles"]
                if prof:
                    name = prof[0]["Tablet"]
            except (OSError, ValueError, KeyError, IndexError):
                pass
        bat = next((p for m, p in bats if m and (m in low or low.startswith(m))), None)
        dev = {
            "id": g["id"], "name": name, "kind": kind, "bus": BUS.get("0003") if driver else g["bus"],
            "wireless": g["bus"] == "bluetooth" or bool(re.search(r"wireless|2\.4g|receiver|dongle", low)),
            "js": sorted(set(g["js"])), "battery": bat,
            "vendor": g["vendor"], "model": g["model"],
        }
        if "widthMm" in g:
            dev["widthMm"], dev["heightMm"] = g["widthMm"], g["heightMm"]
        if g["kinds"] & {"tablet", "touchpad"}:
            dev["direct"] = bool(g.get("direct")) and not driver
        if driver:
            dev["driver"] = driver
            dev.pop("widthMm", None)
            dev.pop("heightMm", None)
        devices.append(dev)
    # у планшета под OpenTabletDriver остаётся общий USB-узел «… CTL-672 Mouse» — это не отдельная мышь
    otd = [d["name"] for d in devices if d.get("driver") == "otd"]
    devices = [d for d in devices if not (otd and d["kind"] == "mouse" and d["model"] and any(d["model"] in n for n in otd))]
    devices.sort(key=lambda d: (TYPES.index(d["kind"]), d["name"].lower()))
    print(json.dumps(devices, ensure_ascii=False))


main()
