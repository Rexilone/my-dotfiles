#!/usr/bin/env python3
"""Помощник проводника (files/FilesWindow.qml). Отвечает JSON.

    files.py places                       папки пользователя, закладки GTK, диски
    files.py copy|move <куда> <что…>      по строке JSON на прогресс: {done, total, file}; в конце {ok} или {error}
    files.py trash <что…>                 в корзину (gio trash)
    files.py trashlist                    содержимое корзины: имя, откуда, когда
    files.py restore <имя…>               вернуть из корзины на место
    files.py info <путь>                  размер (с вложенными), число файлов, тип, права, даты
    files.py apps <путь>                  чем открыть: [{id, name, default}]
    files.py search <папка> <строка>      поиск по имени во вложенных папках (fd), до 500
    files.py recent                       недавние файлы (recently-used.xbel), до 200, новые первыми
    files.py stat <путь…>                 сведения о файлах (для «Избранного»)
    files.py thumb <файл> <png> <размер>  миниатюра видео (ffmpegthumbnailer) или PDF (pdftoppm)
    files.py compress <архив> <что…>      zip / tar.gz / 7z — по расширению (bsdtar, 7z)
    files.py extract <архив> <папка>      распаковать в новую папку рядом
"""
import configparser
import json
import os
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

HOME = Path.home()
TRASH = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "Trash"


def out(o):
    print(json.dumps(o, ensure_ascii=False), flush=True)


def user_dir(key, default):
    try:
        p = subprocess.run(["xdg-user-dir", key], capture_output=True, text=True, timeout=2).stdout.strip()
        if p and p != str(HOME):
            return p
    except OSError:
        pass
    return str(HOME / default)


def places():
    dirs = [("home", "Home", str(HOME))]
    for key, name, default, icon in [
        ("DESKTOP", "Desktop", "Desktop", "desktop"), ("DOCUMENTS", "Documents", "Documents", "documents"),
        ("DOWNLOAD", "Downloads", "Downloads", "download"), ("MUSIC", "Music", "Music", "music"),
        ("PICTURES", "Pictures", "Pictures", "pictures"), ("VIDEOS", "Videos", "Videos", "videos"),
    ]:
        p = user_dir(key, default)
        if os.path.isdir(p):
            dirs.append((icon, name, p))
    bookmarks = []
    try:
        for line in (HOME / ".config/gtk-3.0/bookmarks").read_text().splitlines():
            uri, _, label = line.partition(" ")
            if not uri.startswith("file://"):
                continue
            p = unquote(urlparse(uri).path)
            if os.path.isdir(p):
                bookmarks.append({"path": p, "name": label or os.path.basename(p.rstrip("/")) or p})
    except OSError:
        pass
    drives = []
    try:
        mounts = json.loads(subprocess.run(["findmnt", "-J", "-l", "-o", "TARGET,SOURCE,FSTYPE,SIZE,USE%"],
                                           capture_output=True, text=True, timeout=3).stdout)["filesystems"]
    except (OSError, ValueError, KeyError):
        mounts = []
    user = os.environ.get("USER", "")
    for m in mounts:
        t = m.get("target", "")
        if t.startswith((f"/run/media/{user}/", "/media/", "/mnt/")) and m.get("fstype") not in ("fuse.gvfsd-fuse",):
            drives.append({"path": t, "name": os.path.basename(t), "size": m.get("size"), "use%": m.get("use%"), "source": m.get("source")})
    trash_n = len(os.listdir(TRASH / "files")) if (TRASH / "files").is_dir() else 0
    gvfs = Path(f"/run/user/{os.getuid()}/gvfs")
    remote = [str(gvfs / n) for n in os.listdir(gvfs)] if gvfs.is_dir() else []
    out({"dirs": [{"icon": i, "name": n, "path": p} for i, n, p in dirs], "bookmarks": bookmarks,
         "drives": drives, "trash": trash_n, "home": str(HOME),
         "remote": remote})


def free_name(dest: Path) -> Path:
    """name.ext → name (2).ext, если занято."""
    if not dest.exists() and not dest.is_symlink():
        return dest
    stem, suf = (dest.stem, dest.suffix) if dest.is_file() or "." in dest.name[1:] else (dest.name, "")
    n = 2
    while True:
        c = dest.with_name(f"{stem} ({n}){suf}")
        if not c.exists():
            return c
        n += 1


def size_of(p: Path) -> int:
    try:
        if p.is_symlink() or p.is_file():
            return p.lstat().st_size
        total = 0
        for root, _, files in os.walk(p):
            for f in files:
                try:
                    total += os.lstat(os.path.join(root, f)).st_size
                except OSError:
                    pass
        return total
    except OSError:
        return 0


def transfer(mode, dest, srcs):
    dest = Path(dest)
    srcs = [Path(s) for s in srcs]
    total = sum(size_of(s) for s in srcs)
    done = 0
    last = 0.0

    def tick(name, force=False):
        nonlocal last
        now = time.time()
        if force or now - last > 0.15:
            last = now
            out({"done": done, "total": total, "file": name})

    def copy_file(a: Path, b: Path):
        nonlocal done
        if a.is_symlink():
            os.symlink(os.readlink(a), b)
            return
        with open(a, "rb") as fa, open(b, "wb") as fb:
            while True:
                chunk = fa.read(1 << 20)
                if not chunk:
                    break
                fb.write(chunk)
                done += len(chunk)
                tick(a.name)
        try:
            shutil.copystat(a, b)
        except OSError:
            pass

    def copy_any(a: Path, b: Path):
        if a.is_dir() and not a.is_symlink():
            b.mkdir()
            for c in sorted(a.iterdir()):
                copy_any(c, b / c.name)
        else:
            copy_file(a, b)

    try:
        for s in srcs:
            target = dest / s.name
            if mode == "move" and target.resolve() == s.resolve():
                continue
            if s.is_dir() and (dest.resolve() == s.resolve() or s.resolve() in dest.resolve().parents):
                raise OSError(f"{s.name}: нельзя положить папку в саму себя")
            target = free_name(target)
            if mode == "move":
                try:
                    os.rename(s, target)          # тот же диск — мгновенно
                    done += size_of(target)
                    tick(s.name, True)
                    continue
                except OSError:
                    pass
            copy_any(s, target)
            if mode == "move":
                shutil.rmtree(s) if s.is_dir() and not s.is_symlink() else s.unlink()
        out({"done": total, "total": total, "ok": True})
    except Exception as e:  # noqa: BLE001
        out({"error": str(e)})
        sys.exit(1)


def trash(paths):
    p = subprocess.run(["gio", "trash", "--"] + paths, capture_output=True, text=True)
    out({"ok": p.returncode == 0, "error": p.stderr.strip()})


def trashlist():
    items = []
    files = TRASH / "files"
    info = TRASH / "info"
    if files.is_dir():
        for f in files.iterdir():
            ti = configparser.ConfigParser(interpolation=None)
            try:
                ti.read(info / f"{f.name}.trashinfo")
                orig = unquote(ti.get("Trash Info", "Path", fallback=""))
                date = ti.get("Trash Info", "DeletionDate", fallback="")
            except (configparser.Error, OSError):
                orig, date = "", ""
            items.append({"name": f.name, "path": str(f), "orig": orig, "date": date, "dir": f.is_dir()})
    items.sort(key=lambda x: x["date"], reverse=True)
    out(items)


def restore(names):
    for n in names:
        f = TRASH / "files" / n
        ti = configparser.ConfigParser(interpolation=None)
        ti.read(TRASH / "info" / f"{n}.trashinfo")
        orig = Path(unquote(ti.get("Trash Info", "Path", fallback=str(HOME / n))))
        orig.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(f), str(free_name(orig)))
        try:
            (TRASH / "info" / f"{n}.trashinfo").unlink()
        except OSError:
            pass
    out({"ok": True})


def mime(path):
    try:
        return subprocess.run(["file", "-b", "--mime-type", path], capture_output=True, text=True, timeout=3).stdout.strip()
    except OSError:
        return ""


def info(path):
    p = Path(path)
    st = p.lstat()
    count = 0
    if p.is_dir():
        for _, dirs, files in os.walk(p):
            count += len(files) + len(dirs)
    out({"path": str(p), "name": p.name, "size": size_of(p), "count": count, "dir": p.is_dir(),
         "mime": "inode/directory" if p.is_dir() else mime(path), "mode": stat.filemode(st.st_mode),
         "owner": p.owner() if hasattr(p, "owner") else "", "mtime": int(st.st_mtime), "atime": int(st.st_atime),
         "link": os.readlink(p) if p.is_symlink() else ""})


def desktop_name(desktop_id):
    for base in [HOME / ".local/share/applications", Path("/usr/share/applications"),
                 Path("/var/lib/flatpak/exports/share/applications"), HOME / ".local/share/flatpak/exports/share/applications"]:
        f = base / desktop_id
        if f.exists():
            cp = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                cp.read(f, encoding="utf-8")
                e = cp["Desktop Entry"]
                lang = os.environ.get("LANG", "")[:2]
                return e.get(f"Name[{lang}]") or e.get("Name") or desktop_id, e.get("Icon", "")
            except (configparser.Error, KeyError, OSError):
                break
    return desktop_id.removesuffix(".desktop"), ""


def apps(path):
    m = "inode/directory" if os.path.isdir(path) else mime(path)
    try:
        text = subprocess.run(["gio", "mime", m], capture_output=True, text=True, timeout=3).stdout
    except OSError:
        text = ""
    default, ids, section = "", [], ""
    for line in text.splitlines():
        if line.startswith("Default application"):
            default = line.split(":", 1)[1].strip()
        elif line.strip().endswith(":"):
            section = line
        elif line.startswith("\t") and line.strip().endswith(".desktop") and line.strip() not in ids:
            ids.append(line.strip())
    if default and default not in ids:
        ids.insert(0, default)
    res = []
    for i in ids:
        name, icon = desktop_name(i)
        res.append({"id": i, "name": name, "icon": icon, "default": i == default})
    out({"mime": m, "apps": res})


def search(folder, query):
    tool = shutil.which("fd") or shutil.which("fdfind")
    if tool:
        cmd = [tool, "-i", "-H", "--max-results", "500", "--", query, folder]
    else:
        cmd = ["find", folder, "-iname", f"*{query}*"]
    try:
        lines = subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout.splitlines()
    except (OSError, subprocess.TimeoutExpired):
        lines = []
    res = []
    for l in lines[:500]:
        l = l.rstrip("/")
        try:
            st = os.stat(l)
        except OSError:
            continue
        res.append({"name": os.path.basename(l), "path": l, "dir": stat.S_ISDIR(st.st_mode), "size": st.st_size,
                    "mtime": int(st.st_mtime)})
    out(res)


def entry(p):
    try:
        st = os.stat(p)
    except OSError:
        return None
    return {"name": os.path.basename(p.rstrip("/")) or p, "path": p, "dir": stat.S_ISDIR(st.st_mode),
            "size": st.st_size, "mtime": int(st.st_mtime)}


def recent():
    import xml.etree.ElementTree as ET
    f = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "recently-used.xbel"
    try:
        root = ET.parse(f).getroot()
    except (OSError, ET.ParseError):
        out([])
        return
    seen, items = set(), []
    for b in root.iter("bookmark"):
        href = b.get("href", "")
        if not href.startswith("file://"):
            continue
        p = unquote(urlparse(href).path)
        if p in seen:
            continue
        seen.add(p)
        items.append((b.get("visited") or b.get("modified") or b.get("added") or "", p))
    items.sort(reverse=True)
    res = []
    for _, p in items:
        e = entry(p)
        if e:
            res.append(e)
            if len(res) >= 200:
                break
    out(res)


def thumb(src, png, size):
    Path(png).parent.mkdir(parents=True, exist_ok=True)
    m = mime(src)
    try:
        if m.startswith("video/"):
            subprocess.run(["ffmpegthumbnailer", "-i", src, "-o", png, "-s", size, "-t", "15%"], capture_output=True, timeout=30)
        elif m == "application/pdf":
            base = png.removesuffix(".png")
            subprocess.run(["pdftoppm", "-png", "-singlefile", "-scale-to", size, src, base], capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        pass
    out({"ok": os.path.exists(png), "path": png})


def compress(archive, items):
    items = [Path(i) for i in items]
    cwd = items[0].parent
    names = [i.name for i in items]
    if archive.endswith(".7z"):
        cmd = ["7z", "a", "-y", archive] + names
    else:
        cmd = ["bsdtar", "-a", "-cf", archive] + names
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    out({"ok": p.returncode == 0, "error": p.stderr.strip()[-300:]})


def extract(archive, folder):
    a = Path(archive)
    name = a.name
    for ext in (".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2", ".tgz", ".zip", ".7z", ".rar", ".tar"):
        if name.lower().endswith(ext):
            name = name[: -len(ext)]
            break
    dest = free_name(Path(folder) / name)
    dest.mkdir(parents=True)
    if a.suffix.lower() in (".7z", ".rar"):
        cmd = ["7z", "x", "-y", f"-o{dest}", str(a)]
    else:
        cmd = ["bsdtar", "-xf", str(a), "-C", str(dest)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    # одна папка внутри — поднять её на уровень выше
    inner = list(dest.iterdir())
    if p.returncode == 0 and len(inner) == 1 and inner[0].is_dir():
        tmp = dest.with_name(dest.name + ".rexilone-tmp")
        dest.rename(tmp)
        target = free_name(Path(folder) / inner[0].name)
        (tmp / inner[0].name).rename(target)
        tmp.rmdir()
        dest = target
    out({"ok": p.returncode == 0, "path": str(dest), "error": p.stderr.strip()[-300:]})


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "places":
        places()
    elif cmd in ("copy", "move"):
        transfer(cmd, args[0], args[1:])
    elif cmd == "trash":
        trash(args)
    elif cmd == "trashlist":
        trashlist()
    elif cmd == "restore":
        restore(args)
    elif cmd == "info":
        info(args[0])
    elif cmd == "apps":
        apps(args[0])
    elif cmd == "search":
        search(args[0], args[1])
    elif cmd == "recent":
        recent()
    elif cmd == "stat":
        out([e for e in map(entry, args) if e])
    elif cmd == "thumb":
        thumb(args[0], args[1], args[2])
    elif cmd == "compress":
        compress(args[0], args[1:])
    elif cmd == "extract":
        extract(args[0], args[1])
