"""Обновление приложения на устройствах: APK лежит рядом со службой (rexlink/rexlink.apk) вместе с apk.json (версия, контрольная сумма)."""
import hashlib
import json
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _candidates():
    env = os.environ.get("REXLINK_APK")
    if env:
        yield Path(env)
    yield Path("/usr/share/rexlink/rexlink.apk")
    yield HERE.parents[3] / "share" / "rexlink" / "rexlink.apk"   # nix: $out/lib/pythonX/site-packages/rexlink
    yield HERE.parent / "rexlink.apk"                              # дотфайлы: ~/my-dotfiles/rexlink/rexlink.apk
    yield HERE.parents[1] / "dist" / "rexlink.apk"                 # запуск из исходников


def bundled_apk():
    """{path, versionCode, versionName, sha256, size} или None."""
    for apk in _candidates():
        meta = apk.with_name("apk.json")
        if apk.is_file() and meta.is_file():
            try:
                info = json.loads(meta.read_text())
                if not info.get("sha256"):
                    info["sha256"] = hashlib.sha256(apk.read_bytes()).hexdigest()
                return dict(info, path=str(apk), size=apk.stat().st_size)
            except (OSError, ValueError):
                continue
    return None


def version_tuple(name):
    try:
        return tuple(int(x) for x in str(name).split(".")[:3])
    except ValueError:
        return (0,)


def is_outdated(device_info, apk):
    """Старее ли приложение на устройстве, чем APK в пакете."""
    if not apk:
        return False
    code = device_info.get("versionCode")
    if code:
        return int(code) < int(apk["versionCode"])
    if device_info.get("version"):
        return version_tuple(device_info["version"]) < version_tuple(apk["versionName"])
    return False
