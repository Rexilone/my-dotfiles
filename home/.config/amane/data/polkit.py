#!/usr/bin/env python3
"""polkit-агент для amane: регистрируется в polkitd для текущей сессии, на каждый запрос
печатает строки JSON, пароль получает из stdin и проверяет через polkit-agent-helper-1
(сокет /run/polkit/agent-helper.socket в polkit 126+, иначе setuid-программа).
Вывод:  {"begin": {message, action, user}} {"prompt": "Password:", "echo": false}
        {"info": "..."} {"error": "..."} {"failed": true} {"done": true}
Ввод:   {"cmd": "respond", "text": "..."} {"cmd": "cancel"}"""
import ctypes, json, os, pwd, signal, socket, subprocess, sys, threading

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

ctypes.CDLL("libc.so.6").prctl(1, signal.SIGTERM)

DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
PATH = "/org/rexilone/PolicyKit1/AuthenticationAgent"
IFACE = "org.freedesktop.PolicyKit1.AuthenticationAgent"
SOCKET = "/run/polkit/agent-helper.socket"
HELPER = "/usr/lib/polkit-1/polkit-agent-helper-1"


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


class Session:
    """один запрос: помощник PAM, ответы пароля, повтор при ошибке"""

    def __init__(self, cookie, user, reply, error):
        self.cookie, self.user, self.reply, self.error = cookie, user, reply, error
        self.sock = None
        self.proc = None
        self.buf = b""
        self.watch = None
        self.done = False

    def start(self):
        if os.path.exists(SOCKET):
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(SOCKET)
            s.sendall(f"{self.user}\n{self.cookie}\n".encode())
            self.sock = s
            fd = s.fileno()
        else:
            self.proc = subprocess.Popen([HELPER, self.user], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
            self.proc.stdin.write(f"{self.cookie}\n".encode())
            self.proc.stdin.flush()
            fd = self.proc.stdout.fileno()
        self.watch = GLib.io_add_watch(fd, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self.on_data)

    def write(self, text):
        data = (text + "\n").encode()
        if self.sock:
            self.sock.sendall(data)
        elif self.proc:
            self.proc.stdin.write(data)
            self.proc.stdin.flush()

    def close(self):
        if self.watch:
            GLib.source_remove(self.watch)
            self.watch = None
        if self.sock:
            self.sock.close()
            self.sock = None
        if self.proc:
            self.proc.kill()
            self.proc = None

    def on_data(self, fd, cond):
        chunk = os.read(fd, 4096)
        if not chunk:
            self.close()
            if not self.done:
                self.failed()
            return False
        self.buf += chunk
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            self.line(line.decode(errors="replace"))
        return True

    def line(self, l):
        if l.startswith("PAM_PROMPT_ECHO_OFF"):
            emit({"prompt": l[len("PAM_PROMPT_ECHO_OFF"):].strip(), "echo": False})
        elif l.startswith("PAM_PROMPT_ECHO_ON"):
            emit({"prompt": l[len("PAM_PROMPT_ECHO_ON"):].strip(), "echo": True})
        elif l.startswith("PAM_ERROR_MSG"):
            emit({"error": l[len("PAM_ERROR_MSG"):].strip()})
        elif l.startswith("PAM_TEXT_INFO"):
            emit({"info": l[len("PAM_TEXT_INFO"):].strip()})
        elif l.startswith("SUCCESS"):
            self.done = True
            self.close()
            emit({"done": True})
            self.reply()
        elif l.startswith("FAILURE"):
            self.close()
            self.failed()

    def failed(self):
        # неверный пароль — спросить снова
        emit({"failed": True})
        GLib.timeout_add(200, lambda: self.start() and False)

    def cancel(self):
        self.done = True
        self.close()
        self.error(dbus.exceptions.DBusException("Cancelled", name="org.freedesktop.PolicyKit1.Error.Cancelled"))
        emit({"done": True})


current = None


class Agent(dbus.service.Object):
    @dbus.service.method(IFACE, in_signature="sssa{ss}sa(sa{sv})", out_signature="", async_callbacks=("reply", "error"))
    def BeginAuthentication(self, action_id, message, icon_name, details, cookie, identities, reply, error):
        global current
        if current:
            current.cancel()
        me = os.getuid()
        users = [int(i[1]["uid"]) for i in identities if str(i[0]) == "unix-user" and "uid" in i[1]]
        uid = me if me in users else (users[0] if users else me)
        try:
            user = pwd.getpwuid(uid).pw_name
        except KeyError:
            error(dbus.exceptions.DBusException("No such user", name="org.freedesktop.PolicyKit1.Error.Failed"))
            return
        emit({"begin": {"message": str(message), "action": str(action_id), "user": user}})
        current = Session(str(cookie), user, reply, error)
        current.start()

    @dbus.service.method(IFACE, in_signature="s", out_signature="")
    def CancelAuthentication(self, cookie):
        global current
        if current and current.cookie == str(cookie):
            current.cancel()
            current = None


def command(c):
    global current
    if not current:
        return
    if c.get("cmd") == "respond":
        current.write(c.get("text", ""))
    elif c.get("cmd") == "cancel":
        current.cancel()
        current = None


def stdin_loop():
    for line in sys.stdin:
        try:
            c = json.loads(line)
        except ValueError:
            continue
        GLib.idle_add(lambda c=c: command(c) and False)
    os._exit(0)


agent = Agent(bus, PATH)
session = os.environ.get("XDG_SESSION_ID", "")
if session:
    subject = ("unix-session", {"session-id": dbus.String(session, variant_level=1)})
else:
    subject = ("unix-process", {"pid": dbus.UInt32(os.getppid(), variant_level=1), "start-time": dbus.UInt64(0, variant_level=1)})
authority = dbus.Interface(bus.get_object("org.freedesktop.PolicyKit1", "/org/freedesktop/PolicyKit1/Authority"), "org.freedesktop.PolicyKit1.Authority")
try:
    authority.RegisterAuthenticationAgent(subject, os.environ.get("LANG", "en_US.UTF-8"), PATH)
    emit({"registered": True})
except dbus.exceptions.DBusException as e:
    # уже есть другой агент (например, Quickshell) — выходим, amane попробует позже
    emit({"registered": False, "reason": str(e)})
    sys.exit(3)

threading.Thread(target=stdin_loop, daemon=True).start()
GLib.MainLoop().run()
