#!/usr/bin/env python3
"""Reproducible focus soundscapes. Three licensed recordings; nine local syntheses.

Python standard library plus ffmpeg. See Resources/Audio/README.md for provenance.
"""
import math
import random
import struct
import wave
import sys
from pathlib import Path
from audio_sources import SOURCES, recorded_values

ROOT = Path(__file__).resolve().parents[1] / 'Resources' / 'Audio'
RATE = 22050
SECONDS = 16
IDS = ['train', 'aircraft', 'lightRain', 'ocean', 'wind', 'stream', 'fire', 'night', 'thunder', 'birds', 'cafe', 'keyboard']
TARGET_RMS = .24


def generate(name, seed):
    rng = random.Random(seed)
    if name in SOURCES:
        return write_loop(name, recorded_values(name, rng, RATE, SECONDS))
    b = [0.0] * 7
    low = slow = brown = crackle = band = fire_burst = 0.0
    thunder_body = thunder_floor = 0.0
    drops = []
    events = []
    next_event = 0
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
        if name == 'train':
            wheel = max(0, math.sin(2*math.pi*t*2.7))**18
            wheel2 = max(0, math.sin(2*math.pi*(t-.065)*2.7))**18
            value = brown*.4 + low*.25 + (wheel+wheel2)*low*1.5
        elif name == 'aircraft':
            value = brown*.9 + slow*.8 + .018*math.sin(2*math.pi*78*t) + low*.07
        elif name == 'lightRain':
            if rng.random() < .006: drops.append([0, rng.uniform(.004, .014), rng.uniform(.04, .18)])
            drop = 0
            for event in drops:
                age, decay, amp = event
                # Tiny broadband impacts: no ringing drips, flowing bed, or low water wash.
                envelope = (1-math.exp(-age/(RATE*.0005)))*math.exp(-age/(RATE*decay))
                drop += amp*envelope*(white-band)
                event[0] += 1
            drops = [e for e in drops if e[0] < RATE*.08]
            value = (white-band)*.006 + drop
        elif name == 'ocean':
            surge = (.5+.5*math.sin(2*math.pi*t/8))**2
            value = (low*.6 + pink*.25)*(0.25+surge) + high*.1*surge
        elif name == 'wind':
            gust = .5+.25*math.sin(2*math.pi*t/5.3)+.2*math.sin(2*math.pi*t/2.1)
            value = brown*.8*gust + .06*math.sin(2*math.pi*(270*t+12*math.sin(t)))*gust + slow*.2
        elif name == 'fire':
            fire_burst *= .997
            if rng.random() < .00010: fire_burst += rng.uniform(.3, 1.0)
            value = brown*.015 + low*.012 + fire_burst*high*.8
        elif name == 'thunder':
            # Two distant rolls: soft arrival, multiple delayed low rumbles, then long decay.
            # There is deliberately no continuous rain/noise bed between thunder events.
            rumble = 0
            for onset, level in [(1.1, .9), (8.6, 1.0)]:
                elapsed = t-onset
                if elapsed > 0:
                    for delay, strength in [(0, 1), (.24, .65), (.71, .48), (1.35, .35)]:
                        age = elapsed-delay
                        if age > 0:
                            rumble += level*strength*(1-math.exp(-age/.11))*math.exp(-age/1.12)
            thunder_body += .035*(white-thunder_body)
            thunder_floor += .006*(white-thunder_floor)
            value = (thunder_body-thunder_floor)*rumble
        elif name == 'birds':
            if i >= next_event:
                events.append([0, rng.uniform(1700, 3400), rng.uniform(.08, .18)])
                next_event = i+int(rng.uniform(.25, 1.1)*RATE)
            chirp = 0
            for event in events:
                age, freq, amp = event; elapsed = age/RATE
                chirp += amp*math.sin(math.pi*min(1, elapsed/.16))**2*math.sin(2*math.pi*(freq*elapsed+2200*elapsed**2))
                event[0] += 1
            events = [e for e in events if e[0] < RATE*.16]
            value = pink*.015 + chirp
        elif name == 'cafe':
            # Filtered, syllable-rate murmur without intelligible speech, plus ceramic taps.
            murmur = sum(math.sin(2*math.pi*f*t + 3*math.sin(t*rate))*(.5+.5*math.sin(t*rate*2)) for f, rate in [(137, 2.1), (213, 2.7), (317, 3.3)])
            value = low*.12 + murmur*.018 + crackle*.025*math.sin(2*math.pi*2300*t)
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
