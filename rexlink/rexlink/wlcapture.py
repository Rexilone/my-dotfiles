"""Захват одного монитора по wlr-screencopy — минимальный клиент Wayland без библиотек.

Кадр приходит, только когда на мониторе что-то изменилось (copy_with_damage), в общую память (wl_shm);
дальше его забирает ffmpeg и кодирует на видеокарте. niri, sway, Hyprland и др. умеют wlr-screencopy.
"""
import array
import mmap
import os
import socket
import struct

# wl_shm.format → pix_fmt ffmpeg (в памяти little-endian)
PIX_FMT = {0: "bgra", 1: "bgr0", 0x34324241: "rgba", 0x34324258: "rgb0"}   # ARGB/XRGB/ABGR/XBGR8888


class WaylandError(Exception):
    pass


class Capture:
    def __init__(self, output_name, cursor=True):
        path = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
        if not path.startswith("/"):
            path = os.path.join(os.environ["XDG_RUNTIME_DIR"], path)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.buf = b""
        self.fds = []
        self.next_id = 2
        self.handlers = {}          # id объекта -> функция(opcode, data)
        self.cursor = cursor
        self.globals = {}           # интерфейс -> [(name, version)]
        self.outputs = {}           # id wl_output -> имя
        self.pool = None            # (id буфера, mmap, размер, формат, w, h, stride)
        self.frame = None

        reg = self.new(self.on_registry)
        self.send(1, 1, struct.pack("<I", reg))          # wl_display.get_registry
        self.roundtrip()
        if "zwlr_screencopy_manager_v1" not in self.globals:
            raise WaylandError("композитор не поддерживает wlr-screencopy")
        self.shm = self.bind(reg, "wl_shm", 1, lambda *a: None)
        name, ver = self.globals["zwlr_screencopy_manager_v1"][0]
        self.copy_ver = min(ver, 3)
        self.manager = self.bind(reg, "zwlr_screencopy_manager_v1", self.copy_ver, lambda *a: None)
        for gname, gver in self.globals.get("wl_output", []):
            if gver < 4:
                continue
            oid = self.bind_name(reg, gname, "wl_output", 4, None)
            self.handlers[oid] = lambda op, data, oid=oid: self.on_output(oid, op, data)
        self.roundtrip()
        self.output = next((oid for oid, n in self.outputs.items() if n == output_name), None)
        if self.output is None:
            raise WaylandError(f"нет монитора {output_name}")

    # ── протокол
    def new(self, handler):
        oid = self.next_id
        self.next_id += 1
        self.handlers[oid] = handler
        return oid

    def send(self, obj, opcode, args=b"", fds=None):
        msg = struct.pack("<II", obj, ((8 + len(args)) << 16) | opcode) + args
        if fds:
            self.sock.sendmsg([msg], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", fds))])
        else:
            self.sock.sendall(msg)

    @staticmethod
    def string(s):
        b = s.encode() + b"\0"
        return struct.pack("<I", len(b)) + b + b"\0" * (-len(b) % 4)

    def bind_name(self, reg, name, iface, version, handler):
        oid = self.new(handler)
        self.send(reg, 0, struct.pack("<I", name) + self.string(iface) + struct.pack("<II", version, oid))
        return oid

    def bind(self, reg, iface, version, handler):
        name, ver = self.globals[iface][0]
        return self.bind_name(reg, name, iface, min(version, ver), handler)

    def roundtrip(self):
        done = []
        cb = self.new(lambda op, data: done.append(1))
        self.send(1, 0, struct.pack("<I", cb))              # wl_display.sync
        while not done:
            self.dispatch()
        self.handlers.pop(cb, None)

    def dispatch(self):
        """Прочитать и обработать события (блокирует до прихода данных)."""
        data, anc, _, _ = self.sock.recvmsg(1 << 16, socket.CMSG_SPACE(16 * 4))
        if not data:
            raise WaylandError("композитор закрыл соединение")
        for level, kind, payload in anc:
            if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                fds = array.array("i")
                fds.frombytes(payload[:len(payload) - len(payload) % 4])
                for fd in fds:
                    os.close(fd)       # нам дескрипторы от композитора не нужны (keymap и т.п.)
        self.buf += data
        while len(self.buf) >= 8:
            obj, word = struct.unpack_from("<II", self.buf)
            size, op = word >> 16, word & 0xFFFF
            if len(self.buf) < size:
                break
            body = self.buf[8:size]
            self.buf = self.buf[size:]
            if obj == 1 and op == 0:                          # wl_display.error
                _, code = struct.unpack_from("<II", body)
                raise WaylandError(f"ошибка протокола {code}: {self.read_string(body, 8)[0]}")
            h = self.handlers.get(obj)
            if h:
                h(op, body)

    @staticmethod
    def read_string(body, off):
        (n,) = struct.unpack_from("<I", body, off)
        s = body[off + 4:off + 4 + n - 1].decode(errors="replace")
        return s, off + 4 + n + (-n % 4)

    def on_registry(self, op, body):
        if op == 0:
            (name,) = struct.unpack_from("<I", body)
            iface, off = self.read_string(body, 4)
            (ver,) = struct.unpack_from("<I", body, off)
            self.globals.setdefault(iface, []).append((name, ver))

    def on_output(self, oid, op, body):
        if op == 4:                                           # wl_output.name
            self.outputs[oid] = self.read_string(body, 0)[0]

    # ── кадры
    def _buffer(self, fmt, w, h, stride):
        if self.pool and self.pool[3:] == (fmt, w, h, stride):
            return self.pool[0]
        self._free()
        size = stride * h
        fd = os.memfd_create("rexlink-capture", os.MFD_CLOEXEC)
        os.ftruncate(fd, size)
        mm = mmap.mmap(fd, size)
        pool = self.new(lambda *a: None)
        self.send(self.shm, 0, struct.pack("<Ii", pool, size), [fd])          # wl_shm.create_pool
        buf = self.new(lambda *a: None)
        self.send(pool, 0, struct.pack("<IiiiiI", buf, 0, w, h, stride, fmt))   # create_buffer
        self.send(pool, 1)                                                    # pool.destroy
        os.close(fd)
        self.pool = (buf, mm, size, fmt, w, h, stride)
        return buf

    def _free(self):
        if self.pool:
            self.send(self.pool[0], 0)                                        # wl_buffer.destroy
            self.pool[1].close()
            self.pool = None

    def grab(self, first=False):
        """Следующий кадр: (memoryview, pix_fmt, w, h, stride). Ждёт изменений на мониторе (кроме первого)."""
        st = {"info": None, "done": False, "result": None}

        def on_frame(op, body):
            if op == 0:                                       # buffer: shm-формат
                fmt, w, h, stride = struct.unpack_from("<IIII", body)
                if fmt in PIX_FMT and st["info"] is None:
                    st["info"] = (fmt, w, h, stride)
                if self.copy_ver < 3:
                    st["done"] = True
            elif op == 6:                                     # buffer_done
                st["done"] = True
            elif op == 2:
                st["result"] = "ready"
            elif op == 3:
                st["result"] = "failed"

        frame = self.new(on_frame)
        self.send(self.manager, 0, struct.pack("<IiI", frame, 1 if self.cursor else 0, self.output))
        while not st["done"]:
            self.dispatch()
        if not st["info"]:
            raise WaylandError("неподдерживаемый формат кадра")
        fmt, w, h, stride = st["info"]
        buf = self._buffer(fmt, w, h, stride)
        self.send(frame, 0 if first or self.copy_ver < 2 else 2, struct.pack("<I", buf))  # copy / copy_with_damage
        while st["result"] is None:
            self.dispatch()
        self.send(frame, 1)                                   # frame.destroy
        self.handlers.pop(frame, None)
        if st["result"] != "ready":
            raise WaylandError("кадр не снят (монитор выключен или пропал)")
        return memoryview(self.pool[1]), PIX_FMT[fmt], w, h, stride

    def close(self):
        try:
            self._free()
        except OSError:
            pass
        self.sock.close()
