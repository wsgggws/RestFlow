#!/usr/bin/env python3
"""Reproducible focus soundscapes. Twelve soundscapes from licensed recordings.

Python standard library plus ffmpeg. See Resources/Audio/README.md for provenance.
"""
import math
import random
import struct
import wave
import sys
from pathlib import Path
from audio_sources import SOURCES, recorded_values
from field_recordings import SCENES, write_recorded_loop

ROOT = Path(__file__).resolve().parents[1] / 'Resources' / 'Audio'
RATE = 22050
SECONDS = 16
IDS = ['train', 'aircraft', 'lightRain', 'ocean', 'wind', 'stream', 'fire', 'night', 'thunder', 'birds', 'cafe', 'keyboard']
TARGET_RMS = .24


def generate(name, seed):
    if name in SCENES:
        return write_recorded_loop(name, ROOT)
    rng = random.Random(seed)
    if name in SOURCES:
        return write_loop(name, recorded_values(name, rng, RATE, SECONDS))
    raise ValueError(f'Missing recording scene: {name}')


def write_loop(name, values):
    for i in range(RATE):
        weight = .5-.5*math.cos(math.pi*i/(RATE-1))
        values[i] = values[RATE*SECONDS+i]*(1-weight) + values[i]*weight
    values = values[:RATE*SECONDS]
    mean = sum(values)/len(values)
    values = [v-mean for v in values]
    # Equal RMS rather than peak-only normalization: transient-rich rain/fire stays audible.
    # Smooth saturation contains sparse transients without hard digital clipping.
    lo, hi = 0.0, 1000.0
    for _ in range(24):
        gain = (lo+hi)/2
        rms = math.sqrt(sum((.92*math.tanh(v*gain/.92))**2 for v in values)/len(values))
        if rms < TARGET_RMS: lo = gain
        else: hi = gain
    samples = [round(.92*math.tanh(v*hi/.92)*32767) for v in values]
    with wave.open(str(ROOT / f'noise-{name}.wav'), 'wb') as out:
        out.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(struct.pack('<%dh' % len(samples), *samples))

if __name__ == '__main__':
    ROOT.mkdir(parents=True, exist_ok=True)
    names = sys.argv[1:] or IDS
    if not set(names) <= set(IDS): raise SystemExit('Unknown soundscape ID')
    for name in names:
        generate(name, 20261115+sum((i+1)*ord(c) for i, c in enumerate(name)))
        print(f'Generated {name}', flush=True)
