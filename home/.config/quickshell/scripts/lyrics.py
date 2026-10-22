#!/usr/bin/env python3
"""Синхронный текст песни с lrclib.net: lyrics.py <исполнитель> <название> [длительность, с]
Печатает JSON [[секунды, строка], …] или [] (не нашлось / нет синхронного текста)."""
import json
import re
import sys
import urllib.parse
import urllib.request

UA = {"User-Agent": "rexilone-shell (https://github.com/Rexilone)"}


def fetch(path, **params):
    url = f"https://lrclib.net/api/{path}?" + urllib.parse.urlencode({k: v for k, v in params.items() if v})
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=8) as r:
            return json.load(r)
    except Exception:
        return None


def clean(s):
    # «Song (Official Video) [4K]» → «Song», «Artist - Topic» → «Artist»
    s = re.sub(r"\s*[\(\[][^)\]]*(official|video|audio|lyric|visuali[sz]er|4k|hd|remaster)[^)\]]*[\)\]]", "", s, flags=re.I)
    return re.sub(r"\s+-\s+Topic$", "", s).strip()


def parse(lrc):
    out = []
    for line in (lrc or "").splitlines():
        stamps = re.findall(r"\[(\d+):(\d+(?:\.\d+)?)\]", line)
        text = re.sub(r"\[[^\]]*\]", "", line).strip()
        out += [[int(m) * 60 + float(s), text] for m, s in stamps]
    return sorted(out)


def main():
    artist, title = clean(sys.argv[1]), clean(sys.argv[2])
    dur = sys.argv[3] if len(sys.argv) > 3 and float(sys.argv[3] or 0) > 0 else ""
    if " - " in title and not artist:
        artist, title = (x.strip() for x in title.split(" - ", 1))
    hit = fetch("get", artist_name=artist, track_name=title, duration=str(round(float(dur))) if dur else "")
    if not (hit and hit.get("syncedLyrics")):
        found = fetch("search", track_name=title, artist_name=artist) or []
        hit = next((h for h in found if h.get("syncedLyrics")), None)
    print(json.dumps(parse(hit.get("syncedLyrics")) if hit else [], ensure_ascii=False))


main()
