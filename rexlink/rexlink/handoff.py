"""«Продолжить на другом устройстве»: что сейчас открыто на ПК и как открыть пришедшее с телефона.

ПК → устройство: играющее видео или музыка (ссылка с текущей секундой), вкладка браузера в фокусе
или файл. Адрес вкладки берётся из истории браузера по заголовку страницы (MPRIS у браузеров адреса не
отдаёт), базу читаем «только для чтения», не мешая браузеру.

Устройство → ПК: ссылка (из «Поделиться → Открыть на ПК») или то, что играет на телефоне: YouTube —
по id ролика, Spotify — по id трека, остальное — поиском в YouTube Music.
"""
import glob
import json
import os
import re
import shutil
import sqlite3
import subprocess
from pathlib import Path
from urllib.parse import parse_qsl, quote, unquote, urlencode, urlparse, urlunparse

HOME = Path.home()
BROWSERS = ("chromium", "chrome", "brave", "vivaldi", "yandex", "opera", "firefox", "librewolf", "zen", "floorp")
# окончания заголовков окон браузеров: «Страница – Chromium»
TITLE_TAIL = re.compile(r"\s+[–—-]\s+(Chromium|Google Chrome|Brave|Vivaldi|Яндекс Браузер|Yandex Browser|Opera|"
                        r"Mozilla Firefox|Firefox|LibreWolf|Zen Browser|Floorp)\s*$")


def _run(cmd, timeout=3):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


# ── история браузеров
def _chromium_dbs():
    roots = [".config/chromium", ".config/google-chrome", ".config/BraveSoftware/Brave-Browser", ".config/vivaldi",
             ".config/yandex-browser", ".config/opera"]
    out = []
    for r in roots:
        out += glob.glob(str(HOME / r / "*" / "History"))
    return out


def _firefox_dbs():
    out = []
    for r in (".mozilla/firefox", ".librewolf", ".zen", ".floorp"):
        out += glob.glob(str(HOME / r / "*" / "places.sqlite"))
    return out


def _query(db, sql, args):
    try:
        con = sqlite3.connect(f"file:{db}?immutable=1", uri=True, timeout=1)
        try:
            return con.execute(sql, args).fetchall()
        finally:
            con.close()
    except sqlite3.Error:
        return []


def url_for_title(title):
    """Адрес страницы по её заголовку — самое свежее посещение среди всех браузеров."""
    title = (title or "").strip()
    if len(title) < 3:
        return ""
    like = "%" + title.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
    best = (0, "")
    for db in _chromium_dbs():
        # время Chromium — микросекунды с 1601 года
        for url, t in _query(db, "SELECT url, last_visit_time FROM urls WHERE title LIKE ? ESCAPE '\\' "
                                 "ORDER BY last_visit_time DESC LIMIT 1", (like,)):
            best = max(best, ((t or 0) / 1e6 - 11644473600, url))
    for db in _firefox_dbs():
        for url, t in _query(db, "SELECT url, last_visit_date FROM moz_places WHERE title LIKE ? ESCAPE '\\' "
                                 "ORDER BY last_visit_date DESC LIMIT 1", (like,)):
            best = max(best, ((t or 0) / 1e6, url))
    return best[1]


def with_time(url, pos):
    """YouTube: продолжить с той же секунды."""
    if not url or pos < 5:
        return url
    u = urlparse(url)
    if "youtube.com" in u.netloc or "youtu.be" in u.netloc:
        q = [(k, v) for k, v in parse_qsl(u.query) if k != "t"] + [("t", f"{int(pos)}s")]
        return urlunparse(u._replace(query=urlencode(q)))
    return url


# ── что сейчас на ПК
def _players():
    out = []
    for name in _run(["playerctl", "-l"]).split():
        fmt = "{{status}}\t{{xesam:url}}\t{{xesam:title}}\t{{xesam:artist}}\t{{position}}"
        line = _run(["playerctl", "-p", name, "metadata", "--format", fmt]).strip()
        if not line:
            continue
        status, url, title, artist, pos = (line.split("\t") + [""] * 5)[:5]
        try:
            pos = int(pos) / 1e6
        except ValueError:
            pos = 0
        out.append({"name": name, "status": status, "url": url, "title": title, "artist": artist, "pos": pos})
    return out


def _focused():
    try:
        return json.loads(_run(["niri", "msg", "-j", "focused-window"]) or "null") or {}
    except ValueError:
        return {}


def current():
    """{kind: url|file, url|path, title, player?} или None."""
    players = _players()
    playing = [p for p in players if p["status"] == "Playing"]
    for p in playing:
        title = p["title"] or p["artist"]
        if p["url"].startswith(("http://", "https://")):
            return {"kind": "url", "url": with_time(p["url"], p["pos"]), "title": title, "player": p["name"]}
        if p["url"].startswith("file://"):
            path = unquote(urlparse(p["url"]).path)
            if os.path.isfile(path):
                return {"kind": "file", "path": path, "title": title, "pos": p["pos"], "player": p["name"]}
        if p["name"].split(".")[0].lower() in BROWSERS:
            url = url_for_title(p["title"])
            if url:
                return {"kind": "url", "url": with_time(url, p["pos"]), "title": title, "player": p["name"]}
    w = _focused()
    app = (w.get("app_id") or "").lower()
    if any(b in app for b in BROWSERS):
        title = TITLE_TAIL.sub("", w.get("title") or "")
        url = url_for_title(title)
        if url:
            return {"kind": "url", "url": url, "title": title}
    return None


def pause(player):
    if player:
        _run(["playerctl", "-p", player, "pause"])


# ── пришло с телефона
YT_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")


def media_url(m):
    """То, что играет на телефоне → адрес для ПК (YouTube с секундой, Spotify, иначе поиск)."""
    pkg = (m.get("package") or "").lower()
    mid = str(m.get("mediaId") or "")
    pos = float(m.get("pos") or 0) / 1000.0
    title, artist = m.get("title") or "", m.get("artist") or ""
    if "youtube" in pkg and YT_ID.match(mid):
        host = "music.youtube.com" if "music" in pkg else "www.youtube.com"
        return with_time(f"https://{host}/watch?v={mid}", pos)
    if "spotify" in pkg and mid.startswith("spotify:"):
        parts = mid.split(":")
        if len(parts) >= 3:
            return f"https://open.spotify.com/{parts[1]}/{parts[2]}"
    q = " ".join(x for x in (artist, title) if x)
    if not q:
        return ""
    if "youtube" in pkg and "music" not in pkg:
        return "https://www.youtube.com/results?search_query=" + quote(q)
    return "https://music.youtube.com/search?q=" + quote(q)


def open_url(url):
    if not url:
        return False
    opener = shutil.which("xdg-open") or "xdg-open"
    try:
        subprocess.Popen([opener, url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except OSError:
        return False
