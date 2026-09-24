#!/usr/bin/env python3
"""Build the game's small, dependency-free synthetic WAV sound bank."""

from __future__ import annotations

import math
import random
import wave
from pathlib import Path


RATE = 22_050
MAX_I16 = 32_767
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "audio"


def _fade(samples: list[float], fade_in: float = 0.008, fade_out: float = 0.02) -> list[float]:
    in_count = max(1, int(RATE * fade_in))
    out_count = max(1, int(RATE * fade_out))
    last = len(samples) - 1
    for index in range(len(samples)):
        gain = 1.0
        if index < in_count:
            gain = index / in_count
        if index > last - out_count:
            gain = min(gain, (last - index) / out_count)
        samples[index] *= max(0.0, gain)
    return samples


def _soft_limit(value: float) -> float:
    return math.tanh(value * 1.25) / math.tanh(1.25)


def _write(name: str, samples: list[float], peak: float = 0.82) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    current_peak = max((abs(value) for value in samples), default=1.0)
    gain = peak / current_peak if current_peak > 0.0 else 1.0
    frames = bytearray()
    for value in samples:
        sample = int(max(-1.0, min(1.0, _soft_limit(value * gain))) * MAX_I16)
        frames.extend(sample.to_bytes(2, "little", signed=True))
    with wave.open(str(OUTPUT_DIR / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(frames)


def _step() -> list[float]:
    rng = random.Random(1107)
    duration = 0.24
    result: list[float] = []
    filtered = 0.0
    for index in range(int(RATE * duration)):
        t = index / RATE
        filtered = filtered * 0.72 + rng.uniform(-1.0, 1.0) * 0.28
        impact = math.exp(-t * 29.0)
        thump = math.sin(2.0 * math.pi * (78.0 - 28.0 * t) * t) * math.exp(-t * 20.0)
        metal = filtered * impact * 0.56
        sole = math.sin(2.0 * math.pi * 180.0 * t) * math.exp(-t * 36.0) * 0.13
        result.append(thump * 0.76 + metal + sole)
    return _fade(result, 0.001, 0.035)


def _ambient() -> list[float]:
    rng = random.Random(2112)
    duration = 4.0
    count = int(RATE * duration)
    raw_noise = [rng.uniform(-1.0, 1.0) for _ in range(count)]
    # Make the coloured noise periodic before filtering so the loop join remains quiet.
    blend = int(RATE * 0.35)
    for index in range(blend):
        amount = index / blend
        mixed = raw_noise[index] * amount + raw_noise[count - blend + index] * (1.0 - amount)
        raw_noise[index] = mixed
        raw_noise[count - blend + index] = mixed
    result: list[float] = []
    filtered = 0.0
    for index, noise in enumerate(raw_noise):
        t = index / RATE
        filtered = filtered * 0.985 + noise * 0.015
        rumble = (
            math.sin(2.0 * math.pi * 33.0 * t) * 0.36
            + math.sin(2.0 * math.pi * 51.0 * t + 0.7) * 0.22
            + math.sin(2.0 * math.pi * 83.0 * t + 1.8) * 0.10
        )
        ventilation = filtered * 1.35
        result.append((rumble + ventilation) * 0.48)
    return result


def _elevator_hum() -> list[float]:
    duration = 3.0
    result: list[float] = []
    for index in range(int(RATE * duration)):
        t = index / RATE
        modulation = 0.88 + 0.07 * math.sin(2.0 * math.pi * 2.0 * t)
        motor = (
            math.sin(2.0 * math.pi * 55.0 * t) * 0.58
            + math.sin(2.0 * math.pi * 110.0 * t + 0.3) * 0.23
            + math.sin(2.0 * math.pi * 330.0 * t) * 0.07
        )
        result.append(motor * modulation)
    return result


def _elevator_transition(starting: bool) -> list[float]:
    rng = random.Random(4101 if starting else 4102)
    duration = 0.72
    result: list[float] = []
    for index in range(int(RATE * duration)):
        t = index / RATE
        position = t / duration
        ramp = position * position if starting else (1.0 - position) ** 1.7
        frequency = 42.0 + 18.0 * position if starting else 60.0 - 21.0 * position
        motor = math.sin(2.0 * math.pi * frequency * t) * ramp * 0.58
        relay_time = 0.045 if starting else 0.54
        click_t = abs(t - relay_time)
        relay = rng.uniform(-1.0, 1.0) * math.exp(-click_t * 105.0) * 0.36 if click_t < 0.06 else 0.0
        result.append(motor + relay)
    return _fade(result, 0.003, 0.028)


def _door_servo() -> list[float]:
    rng = random.Random(5300)
    duration = 1.05
    result: list[float] = []
    for index in range(int(RATE * duration)):
        t = index / RATE
        body = math.sin(2.0 * math.pi * (138.0 - 48.0 * t) * t) * 0.31
        gear = math.sin(2.0 * math.pi * (410.0 + 35.0 * math.sin(t * 17.0)) * t) * 0.12
        chatter = 0.0
        if int(t * 22.0) % 4 == 0:
            chatter = rng.uniform(-1.0, 1.0) * 0.08
        envelope = math.sin(math.pi * min(1.0, t / duration)) ** 0.55
        latch_t = abs(t - 0.93)
        latch = rng.uniform(-1.0, 1.0) * math.exp(-latch_t * 85.0) * 0.55 if latch_t < 0.07 else 0.0
        result.append((body + gear + chatter) * envelope + latch)
    return _fade(result, 0.006, 0.025)


def _button() -> list[float]:
    rng = random.Random(6202)
    duration = 0.16
    result: list[float] = []
    for index in range(int(RATE * duration)):
        t = index / RATE
        click = rng.uniform(-1.0, 1.0) * math.exp(-t * 72.0) * 0.42
        beep = math.sin(2.0 * math.pi * 920.0 * t) * math.exp(-t * 13.0) * 0.52
        result.append(click + beep)
    return _fade(result, 0.001, 0.02)


def _startup() -> list[float]:
    duration = 1.65
    tones = (220.0, 330.0, 494.0)
    result: list[float] = []
    for index in range(int(RATE * duration)):
        t = index / RATE
        value = math.sin(2.0 * math.pi * (48.0 + 18.0 * t) * t) * min(1.0, t * 2.2) * 0.18
        for tone_index, frequency in enumerate(tones):
            local = t - (0.19 + tone_index * 0.35)
            if 0.0 <= local < 0.48:
                envelope = math.sin(math.pi * local / 0.48) ** 1.6
                value += math.sin(2.0 * math.pi * frequency * local) * envelope * 0.32
        result.append(value)
    return _fade(result, 0.006, 0.08)


def _success() -> list[float]:
    duration = 1.22
    notes = ((0.00, 523.25), (0.18, 659.25), (0.36, 783.99))
    result: list[float] = []
    for index in range(int(RATE * duration)):
        t = index / RATE
        value = 0.0
        for onset, frequency in notes:
            local = t - onset
            if local >= 0.0:
                decay = math.exp(-local * 3.9)
                value += math.sin(2.0 * math.pi * frequency * local) * decay * 0.32
                value += math.sin(2.0 * math.pi * frequency * 2.01 * local) * decay * 0.08
        result.append(value)
    return _fade(result, 0.003, 0.07)


def main() -> None:
    bank = {
        "step.wav": _step(),
        "ambient_industrial.wav": _ambient(),
        "elevator_hum.wav": _elevator_hum(),
        "elevator_start.wav": _elevator_transition(True),
        "elevator_stop.wav": _elevator_transition(False),
        "door_servo.wav": _door_servo(),
        "button.wav": _button(),
        "startup.wav": _startup(),
        "success.wav": _success(),
    }
    peaks = {
        "ambient_industrial.wav": 0.45,
        "elevator_hum.wav": 0.52,
        "button.wav": 0.66,
    }
    for name, samples in bank.items():
        _write(name, samples, peaks.get(name, 0.78))
        print(f"built {name}: {len(samples) / RATE:.2f}s")


if __name__ == "__main__":
    main()
