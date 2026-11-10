#!/usr/bin/env python3
"""Reproducible focus soundscapes. Eleven recorded soundscapes; one deterministic ocean synthesis.

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
    b = [0.0] * 7
    low = slow = brown = crackle = band = 0.0
    values = []
    for i in range(RATE * (SECONDS + 1)):
        t = i / RATE
        white = rng.uniform(-1, 1)
        b[0] = .99886*b[0] + white*.0555179
        b[1] = .99332*b[1] + white*.0750759
        b[2] = .969*b[2] + white*.153852
        b[3] = .8665*b[3] + white*.3104856
        b[4] = .55*b[4] + white*.5329522
        b[5] = -.7616*b[5] - white*.016898
        pink = (sum(b) + white*.5362)*.11
        b[6] = white*.115926
        brown = .998*brown + white*.035
        low += .08*(white-low)
        slow += .003*(white-slow)
        high = white-low
        band += .6*(white-band)
        crackle *= .95
        if rng.random() < .0008: crackle += rng.uniform(.2, .8)
        surge = (.5+.5*math.sin(2*math.pi*t/8))**2
        value = (low*.6 + pink*.25)*(0.25+surge) + high*.1*surge
        values.append(value)
    write_loop(name, values)


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
