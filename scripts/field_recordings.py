"""Verified field recordings, edited offline into stereo focus loops.

Only explicit asset regeneration accesses the network. See the bundled manifest for
source attribution, licenses, exact excerpts and SHA-256 checksums.
"""
import array
import hashlib
import json
import math
import subprocess
import sys
import urllib.request
import wave
from pathlib import Path

MANIFEST = Path(__file__).resolve().parents[1] / 'Resources/Audio/FieldRecordings.json'
CATALOG = json.loads(MANIFEST.read_text())
SCENES = CATALOG['scenes']
CACHE = Path(__file__).resolve().parents[1] / '.build/audio-sources'
RATE = 44100
CHANNELS = 2


def source_file(key):
    source = CATALOG['sources'][key]
    CACHE.mkdir(parents=True, exist_ok=True)
    target = CACHE / source['file']
    if not target.exists():
        request = urllib.request.Request(source['url'], headers={'User-Agent': 'RestFlow-asset-builder'})
        with urllib.request.urlopen(request, timeout=180) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != source['sha256']:
            raise ValueError(f'Unexpected recording digest: {key}')
        target.write_bytes(data)
    if hashlib.sha256(target.read_bytes()).hexdigest() != source['sha256']:
        raise ValueError(f'Cached recording has changed: {target}')
    return target


def decode(key, start, seconds):
    raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-ss', str(start), '-i', str(source_file(key)),
                                  '-t', str(seconds), '-af', 'highpass=f=30,lowpass=f=14000',
                                  '-ar', str(RATE), '-ac', str(CHANNELS), '-f', 'f32le', '-'])
    values = array.array('f'); values.frombytes(raw)
    if sys.byteorder != 'little': values.byteswap()
    if len(values) < round(seconds*RATE)*CHANNELS:
        raise ValueError(f'Recording too short: {key}')
    return values


def blend(tail, head, frames):
    """Raised-cosine overlap preserves stereo position without a hard edit."""
    output = array.array('f')
    for i in range(frames):
        weight = .5-.5*math.cos(math.pi*i/(frames-1))
        for channel in range(CHANNELS):
            index = i*CHANNELS+channel
            output.append(tail[index]*(1-weight)+head[index]*weight)
    return output


def write_recorded_loop(name, root):
    scene = SCENES[name]
    seconds = scene['seconds']
    if 'segments' in scene:
        parts = [decode(scene['source'], start, duration) for start, duration in scene['segments']]
        overlap = round(.5*RATE)*CHANNELS
        values = parts[0][:-overlap] + blend(parts[0][-overlap:], parts[1][:overlap], overlap//CHANNELS) + parts[1][overlap:]
    else:
        values = decode(scene['source'], scene['start'], seconds+1)
    if 'layer' in scene:
        layer = scene['layer']
        extra = decode(layer['source'], layer['start'], seconds+1)
        # Actual flame bed plus actual wood pops, retaining each recording's dynamics.
        bed_rms = math.sqrt(sum(v*v for v in values)/len(values))
        extra_rms = math.sqrt(sum(v*v for v in extra)/len(extra))
        gain = layer['relativeGain']*bed_rms/extra_rms
        values = array.array('f', (a+b*gain for a,b in zip(values, extra)))
    count = round(seconds*RATE)*CHANNELS
    overlap = RATE*CHANNELS
    values[:overlap] = blend(values[count:count+overlap], values[:overlap], RATE)
    values = values[:count]
    # Remove DC, then apply a common stereo gain and a look-ahead peak limiter.
    # Unlike waveshaping, only short loud events attenuate their neighborhood;
    # the original timbre, natural gaps and stereo image are retained.
    means = [sum(values[c::CHANNELS])/(count/CHANNELS) for c in range(CHANNELS)]
    values = array.array('f', (v-means[i%CHANNELS] for i,v in enumerate(values)))
    rms = math.sqrt(sum(v*v for v in values)/count)
    target_rms = .10 if name == 'thunder' else .20
    gain = target_rms/rms
    # Warm up the limiter across the circular seam and provide look-ahead at the end.
    values = values[-overlap:] + values + values[:overlap]
    if sys.byteorder != 'little': values.byteswap()
    pcm = subprocess.check_output([
        'ffmpeg', '-v', 'error', '-f', 'f32le', '-ar', str(RATE), '-ac', str(CHANNELS), '-i', '-',
        '-af', f'volume={gain:.12f},alimiter=limit=0.92:attack=5:release=80:level=false:latency=true,atrim=start=1:duration={seconds}',
        '-f', 's16le', '-'], input=values.tobytes())
    if len(pcm) != count*2:
        raise ValueError(f'Limiter changed loop duration: {name}')
    with wave.open(str(root/f'noise-{name}.wav'), 'wb') as out:
        out.setparams((CHANNELS, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(pcm)
    print(f'  {seconds}s stereo, input RMS={rms:.4f}, gain={gain:.3f}, look-ahead peak limit=0.92')
