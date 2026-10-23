#!/usr/bin/env python3
"""Разбор снимка экрана для скриншотилки (Screenshot.qml).

    shot-analyze.py objects <png>   { objects: прямоугольники картинок и блоков — клик выделяет их по границам,
                                      codes: QR и штрихкоды с текстом }
    shot-analyze.py text <png>      слова с координатами (tesseract, русский + английский) — их можно выделять мышью

Печатает JSON в пикселях картинки. objects — быстро (доли секунды), text — пара секунд, поэтому раздельно.
"""
import json
import subprocess
import sys


def objects(path):
    import cv2
    import numpy as np

    img = cv2.imread(path)
    if img is None:
        return []
    h, w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    # границы: перепады яркости; затем склеить соседние в сплошные пятна (картинка = много деталей внутри)
    edges = cv2.Canny(gray, 40, 120)
    edges = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1)
    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    rects = []
    for c in contours:
        x, y, cw, ch = cv2.boundingRect(c)
        if cw < 24 or ch < 24 or cw * ch > 0.9 * w * h:
            continue
        # контур должен быть похож на рамку: занимать заметную часть периметра своего прямоугольника
        if cv2.arcLength(c, True) < 1.2 * (cw + ch):
            continue
        rects.append((x, y, cw, ch))

    # картинки: участки с большой «пестротой» (много разных цветов), ограниченные ровным фоном
    var = cv2.Laplacian(gray, cv2.CV_16S, ksize=3)
    var = cv2.convertScaleAbs(var)
    _, busy = cv2.threshold(var, 12, 255, cv2.THRESH_BINARY)
    busy = cv2.morphologyEx(busy, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n, _, stats, _ = cv2.connectedComponentsWithStats(busy, 8)
    for i in range(1, n):
        x, y, cw, ch, area = stats[i]
        if cw >= 48 and ch >= 48 and area > 0.55 * cw * ch and cw * ch < 0.9 * w * h:
            rects.append((int(x), int(y), int(cw), int(ch)))

    # убрать почти одинаковые
    rects.sort(key=lambda r: r[2] * r[3])
    out = []
    for r in rects:
        if any(abs(r[0] - o[0]) < 6 and abs(r[1] - o[1]) < 6 and abs(r[2] - o[2]) < 12 and abs(r[3] - o[3]) < 12 for o in out):
            continue
        out.append(r)
    return [list(map(int, r)) for r in out[:400]]


def codes(path):
    import cv2
    import numpy as np

    img = cv2.imread(path)
    if img is None:
        return []
    out = []

    def box(pts, data, kind):
        pts = np.array(pts).reshape(-1, 2)
        x0, y0 = pts.min(axis=0)
        x1, y1 = pts.max(axis=0)
        out.append({"x": int(x0), "y": int(y0), "w": int(x1 - x0), "h": int(y1 - y0), "text": data, "kind": kind})

    try:
        ok, data, pts, _ = cv2.QRCodeDetector().detectAndDecodeMulti(img)
        if ok:
            for d, p in zip(data, pts):
                if d:
                    box(p, d, "qr")
    except cv2.error:
        pass
    try:
        ok, data, pts, _ = cv2.barcode.BarcodeDetector().detectAndDecodeMulti(img)
        if ok:
            for d, p in zip(data, pts):
                if d:
                    box(p, d, "barcode")
    except cv2.error:
        pass
    return out


def text(path):
    # без пробелов между словами на картинке tesseract склеивает строки — psm 3 (авто) лучше всего для экрана
    try:
        tsv = subprocess.run(["tesseract", path, "-", "-l", "rus+eng", "--psm", "3", "tsv"],
                             capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    words = []
    for line in tsv.splitlines()[1:]:
        f = line.split("\t")
        if len(f) < 12 or f[0] != "5":
            continue
        t = f[11].strip()
        try:
            conf = float(f[10])
        except ValueError:
            conf = -1
        if not t or conf < 30:
            continue
        words.append({"x": int(f[6]), "y": int(f[7]), "w": int(f[8]), "h": int(f[9]), "text": t,
                      # строка = блок.абзац.строка — по ней переносы при копировании
                      "line": f"{f[2]}.{f[3]}.{f[4]}"})
    return words


if __name__ == "__main__":
    mode, path = sys.argv[1], sys.argv[2]
    if mode == "objects":
        print(json.dumps({"objects": objects(path), "codes": codes(path)}, ensure_ascii=False))
    else:
        print(json.dumps(text(path), ensure_ascii=False))
