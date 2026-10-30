"""Synthesises the game's sound effects into assets/sounds/*.wav.

    python3 tool/build_sounds.py

Every sound is made here from sine waves and noise, so there is nothing to
license. Short, soft and mono at 22.05 kHz: they play over the map and
should never be louder than the phone's own clicks.
"""

import math
import pathlib
import random
import struct
import wave

RATE = 22050
OUT = pathlib.Path(__file__).resolve().parents[1] / "assets" / "sounds"


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix(base, sound, at=0.0, gain=1.0):
    """Adds [sound] into [base] starting [at] seconds in, growing it."""
    start = int(at * RATE)
    if len(base) < start + len(sound):
        base.extend([0.0] * (start + len(sound) - len(base)))
    for i, s in enumerate(sound):
        base[start + i] += s * gain
    return base


def bell(freq, seconds, decay=6.0):
    """A soft chime: a sine with a quieter octave, a quick attack and a decay."""
    out = []
    for i in range(int(seconds * RATE)):
        t = i / RATE
        env = min(1.0, t / 0.004) * math.exp(-decay * t)
        out.append(
            env
            * (
                math.sin(2 * math.pi * freq * t)
                + 0.3 * math.sin(2 * math.pi * freq * 2 * t)
                + 0.1 * math.sin(2 * math.pi * freq * 3.01 * t)
            )
        )
    return out


def click(rng, seconds=0.012):
    """One flap landing: a burst of filtered noise with a woody knock."""
    out = []
    low = 0.0
    for i in range(int(seconds * RATE)):
        t = i / RATE
        env = math.exp(-t / 0.0025)
        low += 0.35 * (rng.uniform(-1, 1) - low)
        out.append(env * (0.7 * low + 0.5 * math.sin(2 * math.pi * 1800 * t)))
    return out


def clatter(rng, flaps, seconds):
    out = silence(seconds)
    for k in range(flaps):
        at = k * seconds / flaps + rng.uniform(0, 0.006)
        mix(out, click(rng), at, rng.uniform(0.6, 1.0))
    return out


def takeoff(rng):
    """A propeller hum rising in pitch under a swell of wind."""
    seconds = 1.4
    out = []
    low = 0.0
    phase = 0.0
    for i in range(int(seconds * RATE)):
        t = i / RATE
        p = t / seconds
        env = math.sin(math.pi * min(1.0, p * 1.15)) ** 1.5
        freq = 70 + 90 * p * p
        phase += 2 * math.pi * freq / RATE
        hum = math.sin(phase) * (0.55 + 0.45 * math.sin(phase * 0.5))
        low += (0.04 + 0.12 * p) * (rng.uniform(-1, 1) - low)
        out.append(env * (0.5 * hum + 0.9 * low))
    return out


def write(name, samples, peak):
    top = max(abs(s) for s in samples) or 1.0
    fade = int(0.01 * RATE)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for i, s in enumerate(samples):
            tail = min(1.0, (len(samples) - i) / fade)
            frames += struct.pack("<h", int(s / top * peak * tail * 32767))
        w.writeframes(bytes(frames))
    print(f"{name}.wav  {len(samples) / RATE:.2f}s")


def main():
    rng = random.Random(8)
    OUT.mkdir(parents=True, exist_ok=True)

    # A departures board updating.
    write("flap", clatter(rng, 9, 0.32), 0.45)

    # A plane leaves the gate.
    write("takeoff", takeoff(rng), 0.4)

    # A plane lands and its jobs pay out: two quick coins.
    coins = silence(0.6)
    mix(coins, bell(1318.5, 0.5, 9), 0.0, 0.8)
    mix(coins, bell(1975.5, 0.5, 8), 0.08)
    write("coins", coins, 0.5)

    # Airline level up: a rising three-note chime.
    level = silence(0.9)
    for k, f in enumerate([523.3, 659.3, 784.0]):
        mix(level, bell(f, 0.7, 5), k * 0.1)
    write("level", level, 0.5)

    # A new title: the board flaps over, then a four-note fanfare.
    promotion = clatter(rng, 12, 0.42)
    for k, f in enumerate([523.3, 659.3, 784.0, 1046.5]):
        mix(promotion, bell(f, 0.9 if k == 3 else 0.5, 4), 0.38 + k * 0.11, 0.7)
    write("promotion", promotion, 0.55)


if __name__ == "__main__":
    main()
