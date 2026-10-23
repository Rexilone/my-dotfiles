"""Wake-on-LAN: что сообщить устройству, чтобы оно могло включить компьютер «магическим пакетом»."""
import json
import subprocess
from pathlib import Path


def _ip(*args):
    try:
        return json.loads(subprocess.run(["ip", "-j", *args], capture_output=True, text=True, timeout=2).stdout or "[]")
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []


def lan_info(peer: str = "") -> dict:
    """MAC и широковещательный адрес карты, через которую виден peer (иначе — через которую идёт интернет)."""
    peer = (peer or "").removeprefix("::ffff:")
    route = _ip("route", "get", peer or "1.1.1.1") or _ip("route", "get", "1.1.1.1")
    dev = route[0].get("dev", "") if route else ""
    mac = ""
    try:
        mac = Path(f"/sys/class/net/{dev}/address").read_text().strip() if dev else ""
    except OSError:
        pass
    brd = ""
    for a in _ip("-4", "addr", "show", "dev", dev) if dev else []:
        for i in a.get("addr_info", []):
            brd = brd or i.get("broadcast", "")
    return {"mac": mac, "broadcast": brd or "255.255.255.255"}
