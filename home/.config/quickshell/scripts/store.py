#!/usr/bin/env python3
"""Данные для «Программ» (StoreWindow.qml): каталог приложений, поиск, сведения, обновления.

  store.py catalog            путь к JSON-каталогу приложений (appstream репозиториев Arch, кэш)
  store.py installed          установленное: явно поставленные пакеты, приложения (.desktop), AUR
  store.py search <запрос>    поиск по репозиториям (pacman -Ss) и AUR (RPC), одной строкой JSON
  store.py info <пакет>       подробно о пакете (репозиторий или AUR)
  store.py updates            обновления: репозитории (checkupdates) и AUR (paru/yay -Qua)

Каталог — из archlinux-appstream-data (названия, описания, иконки, категории, скриншоты).
Без него магазин работает по описаниям пакетов из pacman, но без иконок и категорий.
Всё без root.
"""
import glob
import gzip
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "rexilone-store")
AUR_RPC = "https://aur.archlinux.org/rpc/v5"
LANG = (os.environ.get("STORE_LANG") or "en")[:2]
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"


def run(cmd, timeout=60):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                              env=dict(os.environ, LC_ALL="C")).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))
    sys.stdout.write("\n")


# ── каталог (appstream) ───────────────────────────────────────────────

def appstream_files():
    files = []
    for pattern in ("/usr/share/swcatalog/xml/*.xml.gz", "/usr/share/app-info/xmls/*.xml.gz"):
        files += sorted(glob.glob(pattern))
    return files


def icon_dirs(repo):
    return [d for d in (f"/usr/share/swcatalog/icons/archlinux-arch-{repo}", f"/usr/share/app-info/icons/archlinux-arch-{repo}")
            if os.path.isdir(d)]


def localized(el, tag):
    """Текст тега на языке интерфейса, иначе без языка."""
    best = None
    for e in el.findall(tag):
        lang = e.get(XML_LANG)
        if lang and lang.split("_")[0] == LANG:
            return (e.text or "").strip()
        if not lang and best is None:
            best = (e.text or "").strip()
    return best or ""


def description(el):
    """Описание: абзацы и пункты списков текстом (на языке интерфейса, если есть)."""
    descs = el.findall("description")
    pick = next((d for d in descs if (d.get(XML_LANG) or "").split("_")[0] == LANG), None)
    pick = pick if pick is not None else next((d for d in descs if not d.get(XML_LANG)), None)
    if pick is None:
        return ""
    parts = []
    for node in pick:
        if node.tag == "p":
            parts.append(" ".join("".join(node.itertext()).split()))
        elif node.tag in ("ul", "ol"):
            for li in node:
                parts.append("• " + " ".join("".join(li.itertext()).split()))
    return "\n".join(p for p in parts if p)


def parse_component(c, repo, dirs):
    pkg = (c.findtext("pkgname") or "").strip()
    if not pkg:
        return None
    icon = ""
    for ic in sorted(c.findall("icon"), key=lambda i: -int(i.get("width") or 0)):
        if ic.get("type") == "cached":
            name = (ic.text or "").strip()
            for d in dirs:
                for size in (f"{ic.get('width')}x{ic.get('height')}", "128x128", "64x64"):
                    p = os.path.join(d, size, name)
                    if os.path.isfile(p):
                        icon = p
                        break
                if icon:
                    break
        elif ic.get("type") == "stock" and not icon:
            icon = "stock:" + (ic.text or "").strip()
        if icon and not icon.startswith("stock:"):
            break
    shots = []
    for s in c.findall("screenshots/screenshot"):
        imgs = s.findall("image")
        # самая крупная миниатюра до ~1000 px, иначе исходник
        thumbs = sorted((i for i in imgs if i.get("type") == "thumbnail" and int(i.get("width") or 0) <= 1000),
                        key=lambda i: -int(i.get("width") or 0))
        src = thumbs[0] if thumbs else next((i for i in imgs if i.get("type") == "source"), None)
        if src is not None and src.text:
            shots.append(src.text.strip())
        if len(shots) >= 4:
            break
    return {
        "id": (c.findtext("id") or "").strip(),
        "pkg": pkg,
        "repo": repo,
        "name": localized(c, "name") or pkg,
        "summary": localized(c, "summary"),
        "description": description(c),
        "icon": icon,
        "categories": [x.text for x in c.findall("categories/category") if x.text],
        "keywords": " ".join(k.text for k in c.findall("keywords/keyword") if k.text)[:300],
        "homepage": next(((u.text or "").strip() for u in c.findall("url") if u.get("type") == "homepage"), ""),
        "license": (c.findtext("project_license") or "").strip(),
        "developer": localized(c, "developer_name") or localized(c, "developer/name"),
        "screenshots": shots,
    }


def main_score(app):
    """Насколько компонент похож на главное приложение пакета."""
    base = re.sub(r"-(fresh|still|git|bin|nox|qt\d?|gtk\d?)$", "", app["pkg"]).lower()
    ident = app["id"].lower().removesuffix(".desktop")
    name = app["name"].lower()
    score = 0
    if name == base or ident.endswith("." + base) or ident == base:
        score += 4
    elif base in ident or base in name:
        score += 1
    score += bool(app["screenshots"]) + (len(app["description"]) > 120) + bool(app["icon"])
    score -= len(ident) / 100      # при прочих равных — короче id (startcenter, а не base)
    return score


def build_catalog():
    apps = {}
    for f in appstream_files():
        repo = os.path.basename(f).split(".")[0]
        dirs = icon_dirs(repo)
        try:
            with gzip.open(f) as fh:
                for _, el in ET.iterparse(fh):
                    if el.tag != "component":
                        continue
                    if el.get("type") in ("desktop-application", "desktop", "console-application"):
                        app = parse_component(el, repo, dirs)
                        # одно приложение на пакет — главное (LibreOffice, а не LibreOffice Base)
                        if app and (app["pkg"] not in apps or main_score(app) > main_score(apps[app["pkg"]])):
                            apps[app["pkg"]] = app
                    el.clear()
        except (OSError, ET.ParseError, EOFError):
            continue
    return sorted(apps.values(), key=lambda a: a["name"].lower())


def catalog():
    files = appstream_files()
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"catalog-{LANG}.json")
    stamp = ";".join(f"{f}:{os.path.getmtime(f)}" for f in files)
    meta = path + ".stamp"
    try:
        if open(meta).read() == stamp and os.path.isfile(path):
            return out({"path": path, "appstream": bool(files)})
    except OSError:
        pass
    apps = build_catalog()
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(apps, fh, ensure_ascii=False)
    os.replace(tmp, path)
    open(meta, "w").write(stamp)
    out({"path": path, "appstream": bool(files)})


# ── установленное ─────────────────────────────────────────────────────

def parse_info(text):
    """Блоки `pacman -Qi/-Si` → [{поле: значение}]."""
    res, cur, key = [], {}, None
    for line in text.splitlines():
        if not line.strip():
            if cur:
                res.append(cur)
            cur, key = {}, None
            continue
        m = re.match(r"^(\S[^:]*?)\s*:\s?(.*)$", line)
        if m and not line.startswith(" "):
            key = m.group(1).strip()
            cur[key] = m.group(2).strip()
        elif key:
            cur[key] += " " + line.strip()
    if cur:
        res.append(cur)
    return res


def installed():
    explicit = set(run(["pacman", "-Qqe"]).split())
    foreign = set(run(["pacman", "-Qqm"]).split())
    versions = {}
    for line in run(["pacman", "-Q"]).splitlines():
        p = line.split()
        if len(p) == 2:
            versions[p[0]] = p[1]
    # приложения: пакет → .desktop (запуск из магазина)
    apps = {}
    desktop = sorted(glob.glob("/usr/share/applications/*.desktop"))
    if desktop:
        owners = run(["pacman", "-Qo", "--quiet", *desktop]).split("\n")
        for f, owner in zip(desktop, owners):
            owner = owner.strip()
            if owner:
                apps.setdefault(owner, os.path.basename(f)[:-8])
    info = {}
    for blk in parse_info(run(["pacman", "-Qi", *sorted(explicit)])) if explicit else []:
        info[blk.get("Name", "")] = {"desc": blk.get("Description", ""), "size": blk.get("Installed Size", ""),
                                     "date": blk.get("Install Date", "")}
    pkgs = [{"name": n, "version": versions.get(n, ""), "aur": n in foreign, "app": apps.get(n, ""),
             **info.get(n, {})} for n in sorted(explicit)]
    out({"packages": pkgs, "versions": versions, "apps": apps, "foreign": sorted(foreign)})


# ── поиск ─────────────────────────────────────────────────────────────

def aur(params, timeout=8):
    url = f"{AUR_RPC}/{params}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "rexilone-store"}),
                                    timeout=timeout) as r:
            return json.load(r).get("results", [])
    except Exception:  # noqa: BLE001 — нет сети, AUR недоступен
        return None


def search(query):
    words = query.split()
    repo = []
    if words:
        text = run(["pacman", "-Ss", "--", *words])
        lines = text.splitlines()
        for i in range(0, len(lines) - 1, 2):
            m = re.match(r"^(\S+)/(\S+) (\S+)(.*)$", lines[i])
            if not m:
                continue
            repo.append({"name": m.group(2), "repo": m.group(1), "version": m.group(3),
                         "installed": "[installed" in m.group(4), "desc": lines[i + 1].strip()})
    names = {p["name"] for p in repo}
    found = aur("search/" + urllib.parse.quote(query.strip()) + "?by=name-desc") if query.strip() else []
    res_aur = []
    for r in (found or []):
        if r["Name"] in names:
            continue
        res_aur.append({"name": r["Name"], "repo": "aur", "version": r.get("Version", ""),
                        "desc": r.get("Description") or "", "votes": r.get("NumVotes", 0),
                        "popularity": r.get("Popularity", 0), "outOfDate": bool(r.get("OutOfDate"))})
    res_aur.sort(key=lambda r: -r["popularity"])
    out({"repo": repo, "aur": res_aur[:80], "aurError": found is None})


# ── сведения о пакете ─────────────────────────────────────────────────

def info(pkg):
    local = parse_info(run(["pacman", "-Qi", pkg]))
    sync = parse_info(run(["pacman", "-Si", pkg]))
    res = {"name": pkg, "installed": bool(local), "localVersion": local[0].get("Version", "") if local else ""}
    if sync:
        s = sync[0]
        res.update(repo=s.get("Repository", ""), version=s.get("Version", ""), desc=s.get("Description", ""),
                   url=s.get("URL", ""), license=s.get("Licenses", ""), depends=s.get("Depends On", "None"),
                   download=s.get("Download Size", ""), size=s.get("Installed Size", ""),
                   packager=s.get("Packager", ""), date=s.get("Build Date", ""))
    else:
        r = aur("info?arg[]=" + urllib.parse.quote(pkg))
        if r:
            a = r[0]
            res.update(repo="aur", version=a.get("Version", ""), desc=a.get("Description") or "",
                       url=a.get("URL") or "", license=" ".join(a.get("License") or []),
                       depends="  ".join((a.get("Depends") or []) + (a.get("MakeDepends") or [])) or "None",
                       votes=a.get("NumVotes", 0), popularity=a.get("Popularity", 0),
                       maintainer=a.get("Maintainer") or "", outOfDate=bool(a.get("OutOfDate")),
                       aurPage=f"https://aur.archlinux.org/packages/{pkg}",
                       pkgbuild=f"https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h={urllib.parse.quote(pkg)}")
        elif local:
            l = local[0]
            res.update(repo="local", version=l.get("Version", ""), desc=l.get("Description", ""),
                       url=l.get("URL", ""), license=l.get("Licenses", ""), depends=l.get("Depends On", "None"),
                       size=l.get("Installed Size", ""))
    if local:
        res["installedSize"] = local[0].get("Installed Size", "")
        res["installDate"] = local[0].get("Install Date", "")
    out(res)


# ── обновления ────────────────────────────────────────────────────────

def updates():
    res = []
    if shutil.which("checkupdates"):
        for line in run(["checkupdates", "--nocolor"], timeout=120).splitlines():
            m = re.match(r"^(\S+) (\S+) -> (\S+)", line)
            if m:
                res.append({"name": m.group(1), "from": m.group(2), "to": m.group(3), "repo": "repo"})
    helper = shutil.which("paru") or shutil.which("yay")
    if helper:
        for line in run([helper, "-Qua"], timeout=120).splitlines():
            m = re.match(r"^(\S+) (\S+) -> (\S+)", line.strip())
            if m:
                res.append({"name": m.group(1), "from": m.group(2), "to": m.group(3), "repo": "aur"})
    out({"updates": res, "checkupdates": bool(shutil.which("checkupdates")), "helper": os.path.basename(helper or "")})


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "catalog":
        catalog()
    elif cmd == "installed":
        installed()
    elif cmd == "search":
        search(" ".join(sys.argv[2:]))
    elif cmd == "info" and len(sys.argv) > 2:
        info(sys.argv[2])
    elif cmd == "updates":
        updates()
    else:
        print(__doc__)


main()
