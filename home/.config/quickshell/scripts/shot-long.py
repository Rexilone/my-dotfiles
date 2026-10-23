#!/usr/bin/env python3
"""Длинный скриншот: снимает область, пока её прокручивают, и склеивает в одну картинку.

    shot-long.py <x> <y> <w> <h> <out.png>

Область — в глобальных логических координатах (как у grim -g). Каждые ~0.2 с новый кадр сравнивается с
предыдущим: насколько сдвинулось содержимое, столько новых строк снизу и добавляется. Остановка — файл
<out.png>.stop; тогда картинка пишется в out.png. В stdout — «height <пиксели>» по ходу и «done <путь>» в конце.
"""
import os
import subprocess
import sys
import time

import cv2
import numpy as np

MAX_HEIGHT = 30000


def grab(geom):
    try:
        png = subprocess.run(["grim", "-g", geom, "-t", "png", "-l", "0", "-"], capture_output=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    if not png:
        return None
    return cv2.imdecode(np.frombuffer(png, np.uint8), cv2.IMREAD_COLOR)


def shift(prev, cur):
    """На сколько пикселей вверх уехало содержимое (0 — не двигалось, None — не нашлось).

    Ищем в прошлом кадре несколько полос нового: верхняя ловит большие прокрутки, нижние — когда наверху
    закреплённая шапка (она на месте и даёт 0). Берём наибольший уверенный сдвиг."""
    h = cur.shape[0]
    th = max(16, min(100, h // 6))
    best = None
    for t0 in (h // 10, h // 3, h // 2):
        if t0 + th > h:
            continue
        tpl = cur[t0:t0 + th]
        if float(tpl.std()) < 3:      # однотонная полоса — по ней сдвиг не понять
            continue
        res = cv2.matchTemplate(prev, tpl, cv2.TM_CCOEFF_NORMED)
        _, score, _, loc = cv2.minMaxLoc(res)
        if score >= 0.9:
            dy = loc[1] - t0
            best = dy if best is None else max(best, dy)
    return best


def main():
    x, y, w, h, out = sys.argv[1:6]
    geom = f"{x},{y} {w}x{h}"
    stop = out + ".stop"
    if os.path.exists(stop):
        os.remove(stop)

    first = grab(geom)
    if first is None:
        sys.exit(1)
    parts = [first]
    prev = first
    height = first.shape[0]
    print(f"height {height}", flush=True)
    while not os.path.exists(stop) and height < MAX_HEIGHT:
        time.sleep(0.2)
        cur = grab(geom)
        if cur is None or cur.shape != prev.shape:
            continue
        if cv2.absdiff(cur, prev).mean() < 0.5:
            continue
        dy = shift(prev, cur)
        if dy is None or dy <= 0:
            prev = cur if dy is None else prev
            continue
        parts.append(cur[cur.shape[0] - dy:])
        height += dy
        prev = cur
        print(f"height {height}", flush=True)

    cv2.imwrite(out, np.vstack(parts))
    if os.path.exists(stop):
        os.remove(stop)
    print(f"done {out}", flush=True)


main()
