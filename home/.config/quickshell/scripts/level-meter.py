#!/usr/bin/env python3
"""Пиковый уровень звука узла PipeWire: печатает число 0..1 каждые 50 мс.
argv: <target: node.name или object.serial> <1 = монитор выхода (sink), 0 = вход/поток>"""
import ctypes, signal, struct, subprocess, sys

target, is_sink = sys.argv[1], sys.argv[2] == "1"
libc = ctypes.CDLL("libc.so.6")


def die_with_parent():
    libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG: pw-record умрёт вместе с нами


props = "{ node.name=qs-meter application.name=qs-meter node.dont-reconnect=true"
props += " stream.capture.sink=true }" if is_sink else " }"
p = subprocess.Popen(
    ["pw-record", "-P", props, "--target", target, "--rate", "8000", "--channels", "1",
     "--format", "s16", "--latency", "30ms", "-"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, preexec_fn=die_with_parent)

N = 400  # 50 мс при 8 кГц
while True:
    b = p.stdout.read(N * 2)
    if len(b) < N * 2:
        break
    v = struct.unpack("<%dh" % N, b)
    print(round(max(abs(x) for x in v) / 32768, 3), flush=True)
