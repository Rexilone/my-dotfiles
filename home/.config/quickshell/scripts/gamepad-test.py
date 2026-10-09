#!/usr/bin/env python3
"""Проверка геймпада: читает /dev/input/jsN и печатает состояние строками JSON
{"axes": [-1..1], "buttons": [0|1]} не чаще ~30 раз в секунду (для Настроек → Peripherals).
Доступ к js-узлам у пользователя за экраном есть (udev uaccess), root не нужен."""
import fcntl, json, os, select, struct, sys, time

JSIOCGAXES = 0x80016A11
JSIOCGBUTTONS = 0x80016A12


def main():
    dev = sys.argv[1] if len(sys.argv) > 1 else "js0"
    fd = os.open(f"/dev/input/{os.path.basename(dev)}", os.O_RDONLY | os.O_NONBLOCK)
    buf = bytearray(1)
    fcntl.ioctl(fd, JSIOCGAXES, buf)
    axes = [0.0] * buf[0]
    fcntl.ioctl(fd, JSIOCGBUTTONS, buf)
    buttons = [0] * buf[0]

    last, dirty = 0.0, True
    while True:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                data = os.read(fd, 8 * 64)
            except BlockingIOError:
                data = b""
            except OSError:
                return  # геймпад отключили
            if not data and r:
                return
            for i in range(0, len(data) - 7, 8):
                _, value, typ, num = struct.unpack("IhBB", data[i:i + 8])
                typ &= ~0x80  # начальное состояние приходит с флагом 0x80
                if typ == 1 and num < len(buttons):
                    buttons[num] = 1 if value else 0
                elif typ == 2 and num < len(axes):
                    axes[num] = round(value / 32767, 3)
                dirty = True
        now = time.monotonic()
        if dirty and now - last >= 0.033:
            print(json.dumps({"axes": axes, "buttons": buttons}), flush=True)
            last, dirty = now, False


try:
    main()
except (OSError, KeyboardInterrupt, BrokenPipeError):
    pass
