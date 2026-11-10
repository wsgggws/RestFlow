"""Pinned, licensed recording inputs for the three sample-based focus soundscapes.

Only asset regeneration downloads these inputs; the app and build are entirely offline.
Requires ffmpeg. Cached inputs are verified even on subsequent runs.
"""
import array
import hashlib
import subprocess
import urllib.request
from pathlib import Path

CACHE = Path(__file__).resolve().parents[1] / '.build' / 'audio-sources'
SOURCES = {
    'stream': ('rafaelmardojai/blanket', 'bbc88ed3b9dfa8b21805d77286f3183abf88f36f',
               'data/resources/sounds/stream.ogg', '0c32014af816cbce410634b4c680d4f69b9dba5e',
               'ce372c5db561168636647dd7d4aac39ef1785ae5d415ad0e589186ce1b7c5796'),
    'night': ('rafaelmardojai/blanket', 'bbc88ed3b9dfa8b21805d77286f3183abf88f36f',
              'data/resources/sounds/summer-night.ogg', '303abbe962245dcc1bbb60f1ae3d8e4250d7fd28',
              '2eb2efb8f5c6733e74dc8546f2ecfac40407e8242a9eed96a72e0fc68790ac6f'),
    'keyboard': ('hainguyents13/mechvibes', '56d7135bcdf6ceb7fe2f4e06f8ca0903277a9e68',
                 'soundpacks/keyboard/cherrymx-blue-abs/sound.ogg', '112c361f274b7ee09fdd815473ce4210e899d008',
                 '8cf6f7dc90f869b5544c4ec8d1fdb8d975c057d9383020920b03cf46323b1ca1'),
}

# Down/up boundaries in milliseconds, from the pinned Mechvibes config.json.
KEYS = [(24330, 24428, 24526), (24700, 24801, 24902), (25071, 25168, 25265),
        (25444, 25547, 25650), (26534, 26618, 26702), (26928, 27023, 27118),
        (27347, 27437, 27527), (17700, 17786, 17872), (18054, 18147.5, 18241),
        (18761, 18849, 18937), (18400, 18492, 18584), (19495, 19588, 19681),
        (19876, 19963, 20050), (20238, 20323, 20408), (31891, 31975.5, 32060),
        (32333, 32420.5, 32508), (36804, 36924, 37044), (28558, 28638.5, 28719),
        (14748, 14854, 14960)]


def source_file(name):
    repo, revision, path, blob, digest = SOURCES[name]
    CACHE.mkdir(parents=True, exist_ok=True)
    target = CACHE / f'{name}.ogg'
    if not target.exists():
        urls = [f'https://raw.githubusercontent.com/{repo}/{revision}/{path}',
                f'https://api.github.com/repos/{repo}/git/blobs/{blob}']
        for url in urls:
            try:
                request = urllib.request.Request(url, headers={'Accept': 'application/vnd.github.raw+json', 'User-Agent': 'RestFlow-asset-builder'})
                with urllib.request.urlopen(request, timeout=60) as response:
                    data = response.read()
                if hashlib.sha256(data).hexdigest() != digest:
                    raise ValueError(f'Unexpected recording digest: {name}')
                target.write_bytes(data)
                break
            except (OSError, ValueError):
                if url == urls[-1]:
                    raise
    if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
        raise ValueError(f'Cached recording has changed: {target}')
    return target


def recorded_values(name, rng, rate, seconds):
    start = {'stream': 12, 'night': 3, 'keyboard': 0}[name]
    duration = 43 if name == 'keyboard' else seconds + 1
    raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-ss', str(start), '-i', str(source_file(name)),
                                   '-t', str(duration), '-ac', '1', '-ar', str(rate), '-f', 'f32le', '-'])
    samples = array.array('f'); samples.frombytes(raw)
    if name != 'keyboard':
        if len(samples) < rate * (seconds + 1):
            raise ValueError(f'Recording too short: {name}')
        return list(samples[:rate * (seconds + 1)])
    # Actual Cherry MX Blue key-down and key-up recordings, with varied key/phrase timing.
    values = [0.0] * (rate * (seconds + 1))
    cursor = .15
    phrase_left = rng.randint(8, 22)
    while cursor < seconds + 1:
        down, up, end = rng.choice(KEYS)
        strength = rng.uniform(.72, 1.05)
        for onset, begin, finish, gain in [(cursor, down, up, strength),
                                           (cursor + rng.uniform(.05, .10), up, end, strength*.72)]:
            clip = samples[round(begin*rate/1000):round(finish*rate/1000)]
            offset = round(onset*rate)
            for index, sample in enumerate(clip):
                if offset + index >= len(values): break
                # Sub-millisecond edge taper retains the switch's impact and housing resonance.
                edge = min(1, index/(rate*.0008), (len(clip)-index-1)/(rate*.002))
                values[offset+index] += sample*gain*max(0, edge)
        phrase_left -= 1
        cursor += rng.uniform(.095, .205)
        if phrase_left == 0:
            cursor += rng.uniform(.35, .85)
            phrase_left = rng.randint(8, 22)
    return values
