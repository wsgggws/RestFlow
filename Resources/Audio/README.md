# Focus soundscapes

Twelve local soundscapes: nine deterministic syntheses and three edited recordings.
Run `python3 scripts/generate-noise.py` to reproduce all, or pass IDs to regenerate a subset.
Requires Python 3 and ffmpeg. Recording sources are fetched only by this development script,
cached under `.build/audio-sources`, pinned by revision and SHA-256 in `scripts/audio_sources.py`.
The app and normal build do not download audio.
Each loop is 16 seconds, mono PCM 16-bit / 22.05 kHz. A one-second overlap joins its seam.
RMS is normalized to 0.24 (about -12.4 dBFS) using smooth saturation, with peaks below 0.92.
Fine rain uses small broadband impacts without a flowing-water bed. Distant thunder uses
separated low rumbles without rain. The other seven synthesized environmental names describe textures.
Runtime mixes equal power, maps the volume slider through a square-root curve, applies a
2/3 amplitude master gain (−3.52 dB relative to 0.15.0), and uses a shared system peak limiter.
macOS alert sounds are loaded from the system and are not redistributed.

## Recording credits

| Output | Original | Source / license | Edits |
| --- | --- | --- | --- |
| `noise-stream.wav` | Stream by gluckose | [Freesound 333987](https://freesound.org/people/gluckose/sounds/333987/), CC0 | Excerpt from 12 s, mono/resample, overlap and level normalization |
| `noise-night.wav` | Crickets Chirping At Night by Lisa Redfern | [SoundBible 2083](https://soundbible.com/2083-Crickets-Chirping-At-Night.html), Public Domain | Excerpt from 3 s, mono/resample, overlap and level normalization |
| `noise-keyboard.wav` | CherryMX Blue — ABS keycaps by Mechvibes | [Mechvibes](https://github.com/hainguyents13/mechvibes/tree/56d7135bcdf6ceb7fe2f4e06f8ca0903277a9e68/soundpacks/keyboard/cherrymx-blue-abs), MIT | 19 actual key-down/up pairs assembled into irregular typing phrases, overlap and level normalization |

Stream and summer-night input files are distributed by [Blanket at bbc88ed3](https://github.com/rafaelmardojai/blanket/blob/bbc88ed3b9dfa8b21805d77286f3183abf88f36f/SOUNDS_LICENSING.md),
which documents the recording licenses separately from its application code. No Blanket code is included.
The Mechvibes MIT license is included alongside these files as `Mechvibes-LICENSE.txt`.
