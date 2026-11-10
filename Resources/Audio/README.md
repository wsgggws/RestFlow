# Focus soundscapes

Twelve local soundscapes: eleven use licensed recordings; ocean retains its existing synthesis.
Run `python3 scripts/generate-noise.py` to reproduce all, or pass IDs for a subset.
Requires Python 3 and ffmpeg. Only this development command downloads source audio,
cached under `.build/audio-sources` and verified by SHA-256 on every use.
`FieldRecordings.json` pins the eight new scenes' sources, licenses, hashes and excerpt edits;
`scripts/audio_sources.py` pins the three existing recording inputs.
The app and normal build are entirely offline.

The eight new loops are 25–48 seconds, stereo PCM 16-bit / 44.1 kHz, preserving spatial
information where present in the original recording. Traffic joins two passes with a
half-second overlap, removing the source's silent gap. Fire combines real flame and
crackle recordings. Other scenes use continuous excerpts. Each has a one-second
raised-cosine loop overlap, 30 Hz high-pass / 14 kHz low-pass filtering and DC removal.
A constant gain targets RMS 0.20 (thunder 0.10), followed by a 5 ms look-ahead / 80 ms
release peak limiter at 0.92. Stereo channels share gain; brief transients reduce local
gain without waveshaping the whole waveform. Circular pre-roll/look-ahead preserves the seam.
Natural dynamics mean final RMS varies between scenes. Thunder retains actual cracks,
rolls, rain and quiet gaps; lightning itself has no sound.
Ocean, stream, night and keyboard remain byte-identical to 0.16.0: 16 seconds,
mono PCM 16-bit / 22.05 kHz, original overlap and RMS 0.24 normalization.
Runtime mixes equal power, maps the volume slider through a square-root curve, applies a
2/3 amplitude master gain (−3.52 dB relative to 0.15.0), and uses a shared system peak limiter.
Stereo playback compensates for the shared graph’s mono center-gain restoration.
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

## New field-recording credits (0.17.0)

These are edited HQ preview recordings, redistributed under the licenses below.
All edits are described above and in the bundled manifest. CC0 dedicates to the public
domain; the frogs recording is CC BY 4.0 and requires attribution, a license link and
identification of modifications. No endorsement by the authors is implied.

| Output / input | Original / author | Source | License |
| --- | --- | --- | --- |
| 街头车流 / train | Medium Traffic — **IENBA** | [Original](https://freesound.org/people/IENBA/sounds/865147/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 池塘蛙鸣 / aircraft | lizzie frogs long.wav — **volivieri** | [Original](https://freesound.org/people/volivieri/sounds/634612/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| 庭院落雨 / lightRain | Rain_Falling_On_Ground.wav — **ivolipa** | [Original](https://freesound.org/people/ivolipa/sounds/329113/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 狂风呼啸 / wind | Wind blowing in a field in Texas, USA — **felix.blume** | [Original](https://freesound.org/people/felix.blume/sounds/217506/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 篝火噼啪 / fire (flame bed) | bonfire flames sizzling — **florianreichelt** | [Original](https://freesound.org/people/florianreichelt/sounds/563764/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 篝火噼啪 / fire (crackles) | fire crackles — **florianreichelt** | [Original](https://freesound.org/people/florianreichelt/sounds/563766/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 林间鸟鸣 / birds | Bird ambience. Coniferous forest dawn chorus. — **SamsterBirdies** | [Original](https://freesound.org/people/SamsterBirdies/sounds/745273/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 人声鼎沸 / cafe | 5 min of crowd chatter.  40 people.wav — **Psykophobia** | [Original](https://freesound.org/people/Psykophobia/sounds/608996/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 电闪雷鸣 / thunder | 2016-10-06 Thunder Crack.wav — **kingsrow** | [Original](https://freesound.org/people/kingsrow/sounds/361772/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
