"""Дочерние процессы, которые умирают вместе с приложением (PR_SET_PDEATHSIG)."""
import ctypes
import signal
import subprocess

_libc = ctypes.CDLL(None, use_errno=True)


def _die_with_parent():
    _libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG


def popen(args, **kw):
    return subprocess.Popen(args, preexec_fn=_die_with_parent, **kw)
