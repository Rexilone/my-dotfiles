#!/usr/bin/env python3
"""Длинный скриншот: снимает область по мере прокрутки и склеивает в одну картинку.

    shot-long.py <x> <y> <w> <h> <out.png>

Область — в глобальных логических координатах (как у grim -g). Кадр берётся, только когда картинка
перестала меняться (догрузились картинки, закончилась плавная прокрутка) — как на телефоне.
Новый кадр сравнивается с прошлым: на сколько сдвинулось содержимое, столько строк снизу и добавляется.

Управление — файлами рядом с out.png:
    <out>.auto   листать самому (стрелкой вниз в окне с фокусом), шаг подбирается по ходу; конец страницы — стоп
    <out>.stop   закончить и записать картинку
В stdout: «height <px>», «lost» (прокрутили слишком далеко — вернитесь чуть назад), «auto», «end», «done <путь>».
"""
import os
import subprocess
import sys
import time

import cv2
import numpy as np

MAX_HEIGHT = 30000


def say(*a):
    print(*a, flush=True)


def grab(geom):
    try:
        png = subprocess.run(["grim", "-g", geom, "-t", "png", "-l", "0", "-"], capture_output=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    if not png:
        return None
    return cv2.imdecode(np.frombuffer(png, np.uint8), cv2.IMREAD_COLOR)


def same(a, b):
    return a is not None and b is not None and a.shape == b.shape and cv2.absdiff(a, b).mean() < 0.4


def settled(geom, first=None, timeout=3.0):
    """Кадр, который перестал меняться (два снимка подряд одинаковые), или последний за timeout."""
    cur = first if first is not None else grab(geom)
    end = time.time() + timeout
    while time.time() < end:
        time.sleep(0.15)
        nxt = grab(geom)
        if nxt is None:
            continue
        if same(cur, nxt):
            return nxt
        cur = nxt
    return cur


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


def scroll(n):
    # стрелка вниз в окне с фокусом: плавно и понемногу, перекрытие кадров остаётся
    subprocess.run(["wtype"] + ["-k", "Down"] * n, capture_output=True, timeout=10)


def main():
    x, y, w, h, out = sys.argv[1:6]
    geom = f"{x},{y} {w}x{h}"
    stop, auto_flag = out + ".stop", out + ".auto"
    for f in (stop, auto_flag):
        if os.path.exists(f):
            os.remove(f)

    prev = settled(geom)
    if prev is None:
        sys.exit(1)
    parts = [prev]
    height = prev.shape[0]
    say(f"height {height}")

    auto = False
    step = 6           # нажатий стрелки за шаг (авто)
    still = 0          # шагов подряд без сдвига — конец страницы
    raw = prev
    while not os.path.exists(stop) and height < MAX_HEIGHT:
        if not auto and os.path.exists(auto_flag):
            auto = True
            say("auto")
        if auto:
            scroll(step)
            cur = settled(geom)
        else:
            # сами листают: ждём, пока картинка остановится и догрузится
            time.sleep(0.15)
            cur = grab(geom)
            if cur is None or same(cur, prev):
                raw = cur
                continue
            if not same(cur, raw):
                raw = cur
                continue
            cur = settled(geom, cur, timeout=1.5)
        if cur is None or cur.shape != prev.shape:
            continue

        dy = shift(prev, cur)
        if dy is None:
            if auto:
                step = max(1, step // 2)        # перескочили — дальше шаг меньше
            say("lost")
            continue
        if dy <= 0:
            if auto:
                still += 1
                if still >= 2:
                    say("end")
                    break
            continue
        still = 0
        parts.append(cur[cur.shape[0] - dy:])
        height += dy
        prev = cur
        say(f"height {height}")
        if auto:
            # шаг — так, чтобы сдвиг был около трети кадра
            want = cur.shape[0] / 3
            step = int(max(1, min(30, round(step * want / dy))))

    cv2.imwrite(out, np.vstack(parts))
    for f in (stop, auto_flag):
        if os.path.exists(f):
            os.remove(f)
    say(f"done {out}")


main()
