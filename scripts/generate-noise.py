#!/usr/bin/env python3
"""Deterministic synthetic ambient noise, no recordings, notes, or external dependencies."""
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'Resources' / 'Audio'
RATE = 22050
SECONDS = 16
IDS = ['white', 'pink', 'brown', 'lightRain', 'heavyRain', 'ocean', 'wind', 'stream', 'fan', 'leaves', 'fire', 'night']

def generate(name, seed):
    rng = random.Random(seed)
    b = [0.0] * 7
    low = slow = brown = crackle = chirp = 0.0
    values = []
    for i in range(RATE * (SECONDS + 1)):
        t = i / RATE
        white = rng.uniform(-1, 1)
        # Paul Kellet's pink-noise filter and a leaky integrated brown spectrum.
        b[0] = .99886*b[0] + white*.0555179
        b[1] = .99332*b[1] + white*.0750759
        b[2] = .969*b[2] + white*.153852
        b[3] = .8665*b[3] + white*.3104856
        b[4] = .55*b[4] + white*.5329522
        b[5] = -.7616*b[5] - white*.016898
        pink = (sum(b) + white*.5362)*.11
        b[6] = white*.115926
        brown = .998*brown + white*.035
        low += .07*(white-low)
        slow += .004*(white-slow)
        high = white-low
        crackle *= .975
        if rng.random() < .0012: crackle += rng.uniform(.2, .8)
        if name == 'white': value = white*.3
        elif name == 'pink': value = pink
        elif name == 'brown': value = brown
        elif name == 'lightRain': value = high*.12 + low*.15 + crackle*high*.5
        elif name == 'heavyRain': value = pink*.8 + high*.15 + crackle*high*.1
        elif name == 'ocean': value = (pink*.6 + low*.8) * (.55+.4*math.sin(2*math.pi*t/8))
        elif name == 'wind': value = brown*(.6+.3*math.sin(2*math.pi*t/5.3)) + slow*1.2
        elif name == 'stream': value = low*.8 + high*.12*(.65+.35*math.sin(2*math.pi*t*3.1))
        elif name == 'fan': value = low*.8 + brown*.3 + pink*.12*(1+.1*math.sin(2*math.pi*t*24))
        elif name == 'leaves': value = high*.2*(.5+.4*math.sin(2*math.pi*t/3.8)) + low*.12
        elif name == 'fire': value = brown*.3 + crackle*high*.8 + low*.1
        else:
            # Noise-band insect texture rather than pitched musical notes.
            chirp += .65*(white-chirp)
            value = (white-chirp)*(.12+.7*max(0, math.sin(2*math.pi*t*2.3))**6) + pink*.04
        values.append(value)
    # Overlap the final second with the initial second, leaving an exact 16 s loop.
    overlap = RATE
    for i in range(overlap):
        weight = .5-.5*math.cos(math.pi*i/(overlap-1))
        values[i] = values[RATE*SECONDS+i]*(1-weight) + values[i]*weight
    values = values[:RATE*SECONDS]
    mean = sum(values)/len(values)
    values = [v-mean for v in values]
    scale = .45/max(abs(v) for v in values)
    with wave.open(str(ROOT / f'noise-{name}.wav'), 'wb') as out:
        out.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(struct.pack('<%dh' % len(values), *(round(v*scale*32767) for v in values)))

if __name__ == '__main__':
    ROOT.mkdir(parents=True, exist_ok=True)
    for index, name in enumerate(IDS): generate(name, 20261110+index)
