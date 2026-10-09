"""Сеть: TLS-сервер, поиск по UDP, сопряжение, дополнительные потоки.

Кадр управления: u32 длина заголовка | JSON-заголовок | payload (длина в header["bin"]).
Поток (файл/видео): первый кадр {"t": "stream", "sid": ...}, дальше сырые данные.
"""
import hashlib
import json
import secrets
import socket
import ssl
import struct
import threading
import time

from PySide6.QtCore import QObject, Signal

from . import PORT, DISCOVERY_PORT

MAX_HEADER = 1 << 20
MAX_PAYLOAD = 64 << 20


def read_exact(sock, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(min(n - len(buf), 1 << 20))
        if not chunk:
            raise ConnectionError("closed")
        buf += chunk
    return bytes(buf)


def read_frame(sock):
    (n,) = struct.unpack(">I", read_exact(sock, 4))
    if n > MAX_HEADER:
        raise ConnectionError("header too large")
    header = json.loads(read_exact(sock, n))
    size = int(header.get("bin", 0))
    if size > MAX_PAYLOAD:
        raise ConnectionError("payload too large")
    payload = read_exact(sock, size) if size else b""
    return header, payload


def encode_frame(header, payload=b""):
    if payload:
        header = dict(header, bin=len(payload))
    data = json.dumps(header, ensure_ascii=False).encode()
    return struct.pack(">I", len(data)) + data + payload


def pairing_code(cert_der: bytes, device_id: str) -> str:
    # одинаково считается на телефоне по сертификату, который он видит:
    # при подмене сертификата коды не совпадут
    h = hashlib.sha256(cert_der + device_id.encode()).digest()
    return f"{int.from_bytes(h[:8], 'big') % 1_000_000:06d}"


class Connection:
    def __init__(self, sock, addr, device_id, name, info):
        self.sock = sock
        self.addr = addr
        self.id = device_id
        self.name = name
        self.info = info            # kind (phone|tablet|watch), model, caps
        self._lock = threading.Lock()
        self.alive = True

    def send(self, header, payload=b""):
        if not self.alive:
            return False
        try:
            with self._lock:
                self.sock.sendall(encode_frame(header, payload))
            return True
        except OSError:
            self.close()
            return False

    def close(self):
        self.alive = False
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        try:
            self.sock.close()
        except OSError:
            pass


class Server(QObject):
    """TLS-сервер: сколько угодно сопряжённых устройств одновременно (телефон, планшет, часы…)."""
    message = Signal(str, object, object)     # id устройства, header, payload (в главном потоке)
    connected = Signal(str, object)           # id, { name, address, kind, model, caps }
    disconnected = Signal(str)                # id
    pairRequested = Signal(str, str, str)     # id, имя, код
    pairFinished = Signal(str)                # id

    def __init__(self, config):
        super().__init__()
        self.config = config
        if not config.get("pcId"):
            config.set("pcId", secrets.token_hex(8))
        cert, key = config.ensure_cert()
        self.ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        self.ctx.load_cert_chain(cert, key)
        self.cert_der = ssl.PEM_cert_to_DER_cert(cert.read_text())
        self.fingerprint = hashlib.sha256(self.cert_der).hexdigest()
        self.conns = {}             # id -> Connection
        self._streams = {}          # sid -> (callback(sock), время, id устройства)
        self._pending = {}          # id -> {event, ok}
        self._stop = False

    # ── запуск
    def start(self):
        self._tcp = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
        self._tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._tcp.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        self._tcp.bind(("::", PORT))
        self._tcp.listen(16)
        threading.Thread(target=self._accept_loop, daemon=True, name="accept").start()

        self._udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._udp.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self._udp.bind(("0.0.0.0", DISCOVERY_PORT))
        threading.Thread(target=self._discovery_loop, daemon=True, name="discovery").start()
        threading.Thread(target=self._announce_loop, daemon=True, name="announce").start()

    def stop(self):
        self._stop = True
        for c in list(self.conns.values()):
            c.close()

    def announce_packet(self):
        return json.dumps({"t": "rexlink", "id": self.config["pcId"], "name": self.config["name"],
                           "port": PORT, "fp": self.fingerprint}).encode()

    def _discovery_loop(self):
        while not self._stop:
            try:
                data, addr = self._udp.recvfrom(2048)
            except OSError:
                time.sleep(1)
                continue
            if data.startswith(b"REXLINK?"):
                try:
                    self._udp.sendto(self.announce_packet(), addr)
                except OSError:
                    pass

    def _announce_loop(self):
        # пока подключены не все сопряжённые устройства (или их нет), напоминаем о себе
        while not self._stop:
            paired = set(self.config["devices"])
            if not paired or not paired <= set(self.conns):
                try:
                    self._udp.sendto(self.announce_packet(), ("255.255.255.255", DISCOVERY_PORT))
                except OSError:
                    pass
            time.sleep(3)

    def _accept_loop(self):
        while not self._stop:
            try:
                raw, addr = self._tcp.accept()
            except OSError:
                continue
            threading.Thread(target=self._handle, args=(raw, addr), daemon=True).start()

    # ── соединение
    def _handle(self, raw, addr):
        raw.settimeout(20)
        raw.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        try:
            sock = self.ctx.wrap_socket(raw, server_side=True)
            header, _ = read_frame(sock)
        except Exception:
            raw.close()
            return
        devices = self.config["devices"]
        did = str(header.get("id", ""))
        known = did in devices and secrets.compare_digest(str(header.get("token", "")), devices[did]["token"])

        if header.get("t") == "stream":
            entry = self._streams.pop(header.get("sid"), None)
            if not known or not entry or entry[2] != did:
                sock.close()
                return
            sock.settimeout(30)
            try:
                entry[0](sock)
            except Exception as e:  # noqa: BLE001
                print("stream error:", e)
            finally:
                try:
                    sock.close()
                except OSError:
                    pass
            return

        if header.get("t") != "hello" or not did:
            sock.close()
            return
        name = str(header.get("name", "Phone"))[:64]
        info = {"kind": str(header.get("kind", "phone")), "model": str(header.get("model", ""))[:64],
                "caps": [str(c) for c in header.get("caps", [])][:32], "version": str(header.get("version", "")),
                "versionCode": int(header.get("versionCode") or 0)}
        host = addr[0][7:] if addr[0].startswith("::ffff:") else addr[0]

        if not known:
            code = pairing_code(self.cert_der, did)
            try:
                sock.sendall(encode_frame({"t": "pair_pending", "code": code}))
            except OSError:
                return
            ev = {"event": threading.Event(), "ok": False}
            self._pending[did] = ev
            self.pairRequested.emit(did, name, code)
            ev["event"].wait(120)
            self._pending.pop(did, None)
            self.pairFinished.emit(did)
            if not ev["ok"]:
                try:
                    sock.sendall(encode_frame({"t": "pair_rejected"}))
                finally:
                    sock.close()
                return
            token = secrets.token_hex(24)
            devices = dict(self.config["devices"])
            devices[did] = {"name": name, "token": token}
            self.config.set("devices", devices)
            sock.sendall(encode_frame({"t": "paired", "token": token, "pcId": self.config["pcId"]}))

        old = self.conns.get(did)
        if old:
            old.close()
        conn = Connection(sock, host, did, name, info)
        self.conns[did] = conn
        # запоминаем имя и тип устройства — список сопряжённых показывается и без подключения
        devices = dict(self.config["devices"])
        entry = dict(devices.get(did, {}), name=name, kind=info["kind"], model=info["model"], lastSeen=int(time.time()),
                     address=host)
        devices[did] = entry
        self.config.set("devices", devices)
        conn.send({"t": "welcome", "name": self.config["name"], "pcId": self.config["pcId"]})
        self.connected.emit(did, dict(info, name=name, address=host))
        sock.settimeout(60)  # устройство шлёт ping каждые 15 с
        try:
            while conn.alive:
                h, p = read_frame(sock)
                if h.get("t") == "ping":
                    conn.send({"t": "pong"})
                    continue
                self.message.emit(did, h, p)
        except Exception:
            pass
        conn.close()
        if self.conns.get(did) is conn:
            del self.conns[did]
            self.disconnected.emit(did)

    def answer_pair(self, device_id, ok):
        ev = self._pending.get(device_id)
        if ev:
            ev["ok"] = ok
            ev["event"].set()

    def forget(self, device_id):
        devices = dict(self.config["devices"])
        devices.pop(device_id, None)
        self.config.set("devices", devices)
        c = self.conns.get(device_id)
        if c:
            c.send({"t": "forgotten"})
            c.close()

    def rename(self, device_id, name):
        devices = dict(self.config["devices"])
        if device_id in devices:
            devices[device_id] = dict(devices[device_id], alias=name.strip()[:64])
            self.config.set("devices", devices)

    # ── отправка
    def send(self, device_id, header, payload=b""):
        c = self.conns.get(device_id)
        return bool(c and c.send(header, payload))

    def broadcast(self, header, payload=b"", exclude=None):
        for did, c in list(self.conns.items()):
            if did != exclude:
                c.send(header, payload)

    def online(self, device_id):
        c = self.conns.get(device_id)
        return bool(c and c.alive)

    def expect_stream(self, device_id, callback):
        """Зарегистрировать поток; устройство подключится с этим sid. callback(sock) идёт в отдельном потоке."""
        sid = secrets.token_hex(8)
        now = time.time()
        self._streams = {k: v for k, v in self._streams.items() if now - v[1] < 120}
        self._streams[sid] = (callback, now, device_id)
        return sid

    def cancel_stream(self, sid):
        self._streams.pop(sid, None)
