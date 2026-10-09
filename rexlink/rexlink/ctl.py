"""rexlink ctl — клиент API без Qt.

  rexlink ctl devices
  rexlink ctl ring device=<id>
  rexlink ctl send_files paths='["~/a.pdf"]'
  rexlink ctl '{"cmd": "sms_send", "address": "+7900…", "body": "привет"}'
  rexlink ctl watch [событие …]     — печатать события построчно (JSON)
"""
import json
import os
import socket
import sys

SOCKET = os.path.join(os.environ.get("REXLINK_RUNTIME_DIR") or
                      os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/rexlink-{os.getuid()}", "rexlink"),
                      "rexlink.sock")


def connect():
    s = socket.socket(socket.AF_UNIX)
    try:
        s.connect(SOCKET)
    except OSError:
        sys.exit("rexlink не запущен (нет сокета API)")
    return s


def request(req, sock=None):
    s = sock or connect()
    s.sendall(json.dumps(req, ensure_ascii=False).encode() + b"\n")
    f = s.makefile("rb")
    for line in f:
        msg = json.loads(line)
        if "event" not in msg:
            return msg
    sys.exit("соединение закрыто")


def parse(args):
    if len(args) == 1 and args[0].lstrip().startswith("{"):
        return json.loads(args[0])
    req = {"cmd": args[0]}
    for a in args[1:]:
        k, _, v = a.partition("=")
        try:
            req[k] = json.loads(v)
        except ValueError:
            req[k] = v
    return req


def main(args):
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if args[0] == "watch":
        s = connect()
        request({"id": 0, "cmd": "subscribe", "events": args[1:] or None}, s)
        for line in s.makefile("rb"):
            sys.stdout.write(line.decode())
            sys.stdout.flush()
        return 0
    req = parse(args)
    req.setdefault("id", 1)
    res = request(req)
    if not res.get("ok"):
        print(res.get("error"), file=sys.stderr)
        return 1
    print(json.dumps(res.get("result"), ensure_ascii=False, indent=2, default=str))
    return 0
