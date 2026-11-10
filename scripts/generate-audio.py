#!/usr/bin/env python3
"""Reproducible original audio, no samples, downloads, or third-party instruments.

PCM mono 22050 Hz. Ambient beds and wrapped notes are periodic over 16 seconds;
quantized harmonic frequencies and circular note tails keep loop seams continuous.
"""
import array
import math
from pathlib import Path
import random
import wave

RATE = 22050
TAU = math.tau
ROOT = Path(__file__).resolve().parent.parent / 'Resources' / 'Audio'
ROOT.mkdir(parents=True, exist_ok=True)


def write(name, samples, peak):
    scale = peak / max(max(abs(x) for x in samples), 0.0001)
    pcm = array.array('h', (round(x * scale * 32767) for x in samples))
    import sys
    if sys.byteorder != 'little':
        pcm.byteswap()
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as out:
        out.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(pcm.tobytes())


def note(t, frequency, decay=1.2, color=0, attack=0.012):
    if t < 0:
        return 0.0
    env = (1 - math.exp(-t / attack)) * math.exp(-t * decay)
    # Each timbre has a different harmonic balance, not just a different pitch.
    if color == 1:
        tone = math.sin(TAU*frequency*t) + .55*math.sin(TAU*frequency*2.76*t)*math.exp(-t*10)
    elif color == 2:
        tone = math.sin(TAU*frequency*t) + .32*math.sin(TAU*frequency*2.01*t) + .17*math.sin(TAU*frequency*4.08*t)
    elif color == 3:
        tone = math.sin(TAU*(frequency*t + 22*t*t*math.exp(-t*4))) + .24*math.sin(TAU*frequency*3*t)
    else:
        tone = math.sin(TAU*frequency*t) + .16*math.sin(TAU*frequency*2*t)*math.exp(-t*2)
    return env*tone


alerts = [
    ('dew', [(0,880),(.18,1320)], 3.1, 0),
    ('wood', [(0,330),(.14,440)], 11, 1),
    ('bowl', [(0,220)], 1.1, 2),
    ('pebble', [(0,620),(.12,470),(.27,350)], 8, 3),
    ('windbell', [(0,1046),(.22,1318),(.46,1568)], 2.6, 2),
    ('sprout', [(0,392),(.13,494),(.29,659)], 4.2, 0),
    ('ripple', [(0,523),(.21,523),(.42,784)], 5.5, 3),
    ('starlight', [(0,1568),(.16,2093)], 3, 2),
    ('bamboo', [(0,440),(.23,587)], 4, 1),
    ('dawn', [(0,262),(.18,330),(.37,392),(.55,524)], 2.5, 0),
    ('hush', [(0,196),(.08,294)], 2.4, 0),
]
for name, notes, decay, color in alerts:
    duration = 2.8 if name == 'bowl' else 2.0
    count = round(duration*RATE)
    samples = []
    for i in range(count):
        t = i/RATE
        v = sum(note(t-start, f, decay, color, .045 if name == 'hush' else .006) for start,f in notes)
        v *= min(1, (duration-t)/.20)  # smooth final silence, no cut-off clicks
        samples.append(v)
    write('alert-'+name, samples, .44)

scenes = [
    ('rings', 196, [0,7,12], 0), ('orbit', 220, [0,7,14], 1),
    ('waves', 146.832, [0,7,12], 2), ('rain', 261.626, [0,5,12], 3),
    ('sunrise', 174.614, [0,4,7,12], 4), ('mountains', 130.813, [0,7,19], 5),
    ('forest', 196, [0,7,14], 6), ('lotus', 220, [0,5,12], 7),
    ('stars', 261.626, [0,7,16], 8), ('clouds', 164.814, [0,7,12], 9),
    ('bamboo', 174.614, [0,5,10], 10), ('fireflies', 293.665, [0,7,12], 11),
]
duration=16
for name, base, intervals, style in scenes:
    randomizer=random.Random(1300+style)
    freqs=[round(base*2**(n/12)*duration)/duration for n in intervals]
    notes=[]
    spacing = [4,2,4,1,4,8,2,4,2,8,2,1][style]
    for index in range(int(duration/spacing)):
        start=index*spacing
        f=freqs[index%len(freqs)]*(2 if style in [1,3,6,8,11] else 1)
        notes.append((start,f,1.1 if style in [3,8,10,11] else .55))
    # Deterministic periodic airy texture; no white-noise discontinuity at the seam.
    air=[(randomizer.randrange(700,9000)/duration,randomizer.random()*TAU) for _ in range(7)]
    samples=[]
    for i in range(duration*RATE):
        t=i/RATE
        breath=(.65+.35*math.sin(TAU*t/(8 if style==0 else 16)))
        bed=sum(math.sin(TAU*f*t+.16*math.sin(TAU*t/16+j))* (.16 if j else .26) for j,f in enumerate(freqs))*breath
        melody=0
        for start,f,decay in notes:
            age=(t-start)%duration
            if style==6: # gentle synthetic birds over a low woodland chord
                if age<.65:
                    melody+=.17*math.sin(TAU*(f*age+170*age*age))*math.sin(math.pi*age/.65)**2
            else:
                melody+=.24*note(age,f,decay,2 if style in [7,8] else (1 if style==10 else 0),.045)
        air_level=.04 if style in [2,3,5,10] else .006
        texture=sum(math.sin(TAU*f*t+p) for f,p in air)*air_level
        if style==2: texture*=.5+.5*math.sin(TAU*t/8)
        samples.append(bed+melody+texture)
    write('ambient-'+name,samples,.32)
    print(name, flush=True)
