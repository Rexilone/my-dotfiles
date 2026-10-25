#!/usr/bin/env python3
"""Звуки системы RexOS (assets/sounds/*.wav) — тихие и мягкие, в духе Pixel и iOS: короткие «токи» вместо
щелчков, тёплые колокольчики в средних частотах, плавная атака (без треска в начале), срезанные верха.
Синтез из синусов, без чужих семплов.

    python3 scripts/gen-sounds.py   → assets/sounds/
"""
import wave
from pathlib import Path

import numpy as np

RATE = 48000
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"


def t_axis(dur):
    return np.arange(int(dur * RATE)) / RATE


def envelope(dur, attack, tau):
    """Плавная атака (полуволна косинуса) и экспоненциальное затухание."""
    t = t_axis(dur)
    a = np.where(t < attack, 0.5 - 0.5 * np.cos(np.pi * t / attack), 1.0)
    return a * np.exp(-np.maximum(0, t - attack) / tau)


def glide(f0, f1, dur, glide_time):
    """Тон, скользящий от f0 к f1 (как «бульк» переключателя или «ток» клавиатуры)."""
    t = t_axis(dur)
    k = np.clip(t / glide_time, 0, 1)
    f = f0 + (f1 - f0) * (1 - (1 - k) ** 2)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE)


def note(freq, dur, attack=0.006, tau=0.35, harm=(0.12, 0.04), detune=0.0015):
    """Тёплая нота: основной тон, слабые 2-я и 3-я гармоники, лёгкий хорус."""
    t = t_axis(dur)
    s = np.sin(2 * np.pi * freq * t) + 0.5 * np.sin(2 * np.pi * freq * (1 + detune) * t)
    for i, a in enumerate(harm, start=2):
        s += a * np.sin(2 * np.pi * freq * i * t) * np.exp(-t / (tau / i))
    return s * envelope(dur, attack, tau)


def lowpass(s, cutoff, passes=2):
    a = np.exp(-2 * np.pi * cutoff / RATE)
    for _ in range(passes):
        y = np.empty_like(s)
        acc = 0.0
        for i, v in enumerate(s):
            acc = (1 - a) * v + a * acc
            y[i] = acc
        s = y
    return s


def room(s, taps=((0.031, 0.16), (0.053, 0.11), (0.079, 0.07), (0.113, 0.04))):
    """Немного воздуха: несколько ранних отражений, приглушённых."""
    y = s.copy()
    for d, g in taps:
        n = int(d * RATE)
        if n < len(y):
            y[n:] += lowpass(s[:-n], 2500, 1) * g
    return y


def mix(length, *parts):
    out = np.zeros(int(length * RATE))
    for at, sig in parts:
        i = int(at * RATE)
        j = min(len(out), i + len(sig))
        out[i:j] += sig[: j - i]
    return out


def save(name, s, peak_db):
    s = s / (np.max(np.abs(s)) or 1) * (10 ** (peak_db / 20))
    fade = min(len(s), int(0.015 * RATE))
    s[-fade:] *= np.linspace(1, 0, fade) ** 2
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((s * 32767).astype("<i2").tobytes())


def tock(f0, f1, dur=0.05, tau=0.011):
    """«Ток» — короткий тон с падением высоты и телом снизу (клавиатура iOS, кнопки Pixel)."""
    body = glide(f0, f1, dur, 0.015) + 0.35 * glide(f0 / 2.6, f1 / 2.6, dur, 0.015)
    return lowpass(body * envelope(dur, 0.0015, tau), 3200)


# щелчок кнопки
save("click", tock(1050, 620), -25)
# переключатель: «бульк» вверх и вниз
save("toggle-on", lowpass(glide(480, 820, 0.09, 0.05) * envelope(0.09, 0.003, 0.028), 3000), -23)
save("toggle-off", lowpass(glide(820, 480, 0.09, 0.05) * envelope(0.09, 0.003, 0.028), 3000), -23)
# громкость: еле слышный тик
save("volume", tock(900, 700, 0.035, 0.007), -27)

# уведомление: две тёплые ноты ре–ля, как мягкий колокольчик
save("notify", lowpass(room(mix(1.2, (0, note(587.3, 1.0, tau=0.42)), (0.12, note(880, 1.05, tau=0.48)))), 4200), -13)

# снимок экрана: два мягких «тока», как затвор
save("shutter", room(mix(0.22, (0, tock(760, 430, 0.06, 0.014)), (0.075, tock(640, 380, 0.06, 0.016) * 0.8))), -19)

# флешка вставлена / вынута
save("plug", lowpass(room(mix(0.6, (0, note(659.3, 0.45, tau=0.18)), (0.09, note(880, 0.5, tau=0.22)))), 3800), -17)
save("unplug", lowpass(room(mix(0.6, (0, note(880, 0.45, tau=0.18)), (0.09, note(659.3, 0.5, tau=0.22)))), 3800), -18)

# телефон на связи / пропал
save("connect", lowpass(room(mix(0.9, (0, note(523.3, 0.6, tau=0.25)), (0.085, note(659.3, 0.6, tau=0.25)),
                                  (0.17, note(784, 0.7, tau=0.32)))), 3800), -17)
save("disconnect", lowpass(room(mix(0.8, (0, note(784, 0.55, tau=0.22)), (0.11, note(523.3, 0.65, tau=0.28)))), 3800), -18)

# запись началась / остановилась — короткий мягкий сигнал
save("record", lowpass(room(glide(700, 880, 0.25, 0.04) * envelope(0.25, 0.004, 0.07)), 3500), -19)

# ошибка: низкий мягкий «бом-бом»
save("error", lowpass(mix(0.45, (0, note(330, 0.25, tau=0.09, harm=(0.08,))), (0.14, note(262, 0.3, tau=0.11, harm=(0.08,)))), 1800), -18)

# старые звуки, которых больше нет
for old in ("timer",):
    (OUT / f"{old}.wav").unlink(missing_ok=True)

print("готово:", ", ".join(sorted(p.stem for p in OUT.glob("*.wav"))))
