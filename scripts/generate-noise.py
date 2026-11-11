#!/usr/bin/env python3
"""Reproducible focus soundscapes. Twelve soundscapes from licensed recordings.

Python standard library plus ffmpeg. See Resources/Audio/README.md for provenance.
"""
import math
import random
import sys
from pathlib import Path
from audio_sources import SOURCES, recorded_values
from field_recordings import CATALOG, SCENES, write_recorded_loop, write_pcm_loop

ROOT = Path(__file__).resolve().parents[1] / 'Resources' / 'Audio'
RATE = 22050
SECONDS = 16
IDS = ['train', 'aircraft', 'lightRain', 'ocean', 'wind', 'stream', 'fire', 'night', 'thunder', 'birds', 'cafe', 'keyboard']


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
    profile = CATALOG['legacyProfiles'][name]
    write_pcm_loop(name, values, ROOT, RATE, 1, SECONDS, profile['targetRMS'], profile['filters'])

if __name__ == '__main__':
    ROOT.mkdir(parents=True, exist_ok=True)
    names = sys.argv[1:] or IDS
    if not set(names) <= set(IDS): raise SystemExit('Unknown soundscape ID')
    for name in names:
        generate(name, 20261115+sum((i+1)*ord(c) for i, c in enumerate(name)))
        print(f'Generated {name}', flush=True)
