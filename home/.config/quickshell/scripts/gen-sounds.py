#!/usr/bin/env python3
"""Звуки системы RexOS (assets/sounds/*.wav): мягкие щелчки, перезвоны, сигналы устройств.
Синтез — сумма синусов с быстрой атакой и экспоненциальным затуханием, без чужих семплов.

    python3 scripts/gen-sounds.py   → assets/sounds/
"""
import wave
from pathlib import Path

import numpy as np

RATE = 48000
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"


def env(n, attack=0.004, tau=0.15):
    t = np.arange(n) / RATE
    a = np.clip(t / attack, 0, 1)
    return a * np.exp(-t / tau)


def tone(freq, dur, tau=0.15, attack=0.004, partials=((1, 1.0),), detune=0.0):
    """Нота: основной тон и обертоны (множитель, громкость)."""
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    s = np.zeros(n)
    for mult, amp in partials:
        f = freq * mult
        s += amp * np.sin(2 * np.pi * f * t) * np.exp(-t / (tau / max(1.0, mult ** 0.6)))
        if detune:
            s += amp * 0.5 * np.sin(2 * np.pi * f * (1 + detune) * t) * np.exp(-t / (tau / max(1.0, mult ** 0.6)))
    return s * np.clip(t / attack, 0, 1)


BELL = ((1, 1.0), (2, 0.28), (2.76, 0.10), (4.07, 0.05))      # мягкий колокольчик
MARIMBA = ((1, 1.0), (3.9, 0.18), (9.2, 0.04))                 # деревянный перкуссионный


def mix(length, *parts):
    """parts: (сдвиг в секундах, сигнал)."""
    out = np.zeros(int(length * RATE))
    for at, sig in parts:
        i = int(at * RATE)
        j = min(len(out), i + len(sig))
        out[i:j] += sig[: j - i]
    return out


def room(s, delay=0.045, fb=0.25, wet=0.18):
    """Короткое «эхо комнаты» — звук не такой сухой."""
    d = int(delay * RATE)
    y = s.copy()
    for k in range(1, 5):
        sh = d * k
        if sh >= len(y):
            break
        y[sh:] += s[:-sh] * wet * (fb ** (k - 1))
    return y


def lowpass(s, cutoff):
    a = np.exp(-2 * np.pi * cutoff / RATE)
    y = np.zeros_like(s)
    acc = 0.0
    for i, v in enumerate(s):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def save(name, s, peak_db):
    s = s / (np.max(np.abs(s)) or 1) * (10 ** (peak_db / 20))
    fade = min(len(s), int(0.01 * RATE))
    s[-fade:] *= np.linspace(1, 0, fade)
    data = (s * 32767).astype("<i2").tobytes()
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


rng = np.random.default_rng(7)

# щелчок интерфейса: короткий «тик» — высокий тон и щепотка шума
n = int(0.03 * RATE)
click = tone(2100, 0.03, tau=0.006, attack=0.0008) + 0.25 * lowpass(rng.standard_normal(n), 5000) * env(n, 0.0005, 0.003)
save("click", click, -16)

# переключатель: два коротких «тика» вверх (вкл) и вниз (выкл)
save("toggle-on", mix(0.12, (0, tone(1400, 0.05, tau=0.012, attack=0.001)), (0.045, tone(2100, 0.06, tau=0.014, attack=0.001))), -15)
save("toggle-off", mix(0.12, (0, tone(2100, 0.05, tau=0.012, attack=0.001)), (0.045, tone(1400, 0.06, tau=0.014, attack=0.001))), -15)

# громкость: совсем тихий деревянный тик
save("volume", tone(1500, 0.05, tau=0.01, attack=0.001, partials=MARIMBA), -14)

# уведомление: два колокольчика — ми и си
save("notify", room(mix(0.9, (0, tone(1318.5, 0.8, tau=0.22, partials=BELL)), (0.11, tone(1975.5, 0.75, tau=0.26, partials=BELL)))), -8)

# снимок экрана: мягкий затвор — два щелчка шума
n = int(0.03 * RATE)
burst = lowpass(rng.standard_normal(n), 3500) * env(n, 0.0005, 0.006)
save("shutter", room(mix(0.2, (0, burst), (0.07, burst * 0.7), (0.0, tone(900, 0.04, tau=0.008) * 0.3))), -10)

# устройство подключено / отключено: две ноты вверх / вниз
save("plug", room(mix(0.45, (0, tone(784, 0.35, tau=0.12, partials=MARIMBA)), (0.09, tone(1174.7, 0.35, tau=0.14, partials=MARIMBA)))), -10)
save("unplug", room(mix(0.45, (0, tone(1174.7, 0.35, tau=0.12, partials=MARIMBA)), (0.09, tone(784, 0.35, tau=0.14, partials=MARIMBA)))), -11)

# телефон на связи / пропал: арпеджио до-ми-соль и обратно
save("connect", room(mix(0.7, (0, tone(1046.5, 0.5, tau=0.16, partials=BELL)), (0.08, tone(1318.5, 0.5, tau=0.16, partials=BELL)),
                          (0.16, tone(1568, 0.55, tau=0.2, partials=BELL)))), -11)
save("disconnect", room(mix(0.6, (0, tone(1568, 0.45, tau=0.15, partials=BELL)), (0.1, tone(1046.5, 0.5, tau=0.18, partials=BELL)))), -12)

# таймер: трижды «ля-ми», мягко
alarm = []
for k in range(3):
    alarm += [(k * 0.8, tone(880, 0.6, tau=0.2, partials=BELL)), (k * 0.8 + 0.16, tone(1318.5, 0.6, tau=0.24, partials=BELL))]
save("timer", room(mix(2.6, *alarm)), -8)

# ошибка: низкий двойной «дун»
save("error", mix(0.4, (0, tone(330, 0.18, tau=0.06, partials=MARIMBA)), (0.14, tone(247, 0.24, tau=0.08, partials=MARIMBA))), -11)

# запись началась / остановилась
save("record", room(mix(0.35, (0, tone(988, 0.25, tau=0.08, partials=BELL)), (0.07, tone(1480, 0.25, tau=0.09, partials=BELL)))), -12)

print("готово:", ", ".join(sorted(p.stem for p in OUT.glob("*.wav"))))
