"""Проверка файрвола без root: открыты ли порты Rexlink в ufw / firewalld."""
import re
import subprocess
from pathlib import Path

from . import DISCOVERY_PORT, PORT

UFW_HINT = "sudo ufw allow Rexlink"
FIREWALLD_HINT = ("sudo firewall-cmd --permanent --add-port=47820/tcp --add-port=47821/udp && "
                  "sudo firewall-cmd --reload")


def _active(unit):
    try:
        return subprocess.run(["systemctl", "is-active", unit], capture_output=True, text=True,
                              timeout=2).stdout.strip() == "active"
    except Exception:
        return False


def check():
    """{"blocked": bool, "tool": "ufw"|"firewalld"|"", "hint": команда} — blocked=None, если не понять."""
    if _active("ufw"):
        try:
            enabled = "ENABLED=yes" in Path("/etc/ufw/ufw.conf").read_text()
        except OSError:
            enabled = True
        if not enabled:
            return {"blocked": False, "tool": "ufw", "hint": ""}
        rules = ""
        for f in ("/etc/ufw/user.rules", "/etc/ufw/user6.rules"):
            try:
                rules += Path(f).read_text()
            except OSError:
                return {"blocked": None, "tool": "ufw", "hint": UFW_HINT}
        tcp = re.search(rf"--dport {PORT}\b.*-j ACCEPT|dport {PORT}\b|### tuple ### allow \S+ {PORT}\b", rules)
        udp = re.search(rf"--dport {DISCOVERY_PORT}\b|### tuple ### allow \S+ {DISCOVERY_PORT}\b", rules)
        app = "Rexlink" in rules
        return {"blocked": not ((tcp and udp) or app), "tool": "ufw", "hint": UFW_HINT}
    if _active("firewalld"):
        return {"blocked": None, "tool": "firewalld", "hint": FIREWALLD_HINT}
    return {"blocked": False, "tool": "", "hint": ""}
