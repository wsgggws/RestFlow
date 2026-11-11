# Focus soundscapes

All twelve local soundscapes use licensed real recordings. Run
`python3 scripts/generate-noise.py` to reproduce all, or pass IDs for a subset.
Requires Python 3 and ffmpeg. Only this development command downloads source audio;
inputs are cached under `.build/audio-sources` and SHA-256 verified on every use.
`FieldRecordings.json` pins nine scenes' sources, licenses, hashes and edit parameters;
`scripts/audio_sources.py` pins stream, night and keyboard. The app and normal build
are completely offline.

## Editing and playback

Nine loops use stereo PCM 16-bit / 44.1 kHz, preserving the original spatial image
where present. Most last 48 seconds; traffic lasts 25 seconds and thunder 18 seconds.
The Mandarin crowd lasts 38 seconds. Traffic joins two passes with a 0.5-second overlap, removing the silent gap.
Each scene uses a one-second raised-cosine loop overlap, filtering, DC removal and
constant stereo-linked gain, followed by a 5 ms look-ahead / 80 ms release peak
limiter at 0.92. Circular pre-roll/look-ahead keeps the limiter stable across the seam.
The gain targets RMS 0.20 (thunder 0.22); final RMS varies with natural dynamics.
Stream, night and keyboard use mono 16-second / 22.05 kHz loops with the same
constant-gain / local-limiter pipeline, targeting RMS 0.20. This replaces their old
whole-waveform saturation, retaining transient detail and quiet gaps.

0.19.0 changes:
- **人声鼎沸 / cafe** uses one Beijing restaurant recording explicitly described by
  its recordist as Mandarin conversation. The former overseas park/restaurant
  mixture is removed; no Cantonese or other-language layer is added. Source
  metadata documents language; automated waveform checks do not identify speech.
- All twelve scenes receive mild source-specific EQ to reduce low-frequency boom
  and excessive hiss while retaining rain drops, surf, fire crackles and voices.
  Filter values are pinned in `FieldRecordings.json`, including mono profiles.
- Recordings retain their original speed, pitch and natural pauses. No artificial
  density or accelerated event rhythm is added. Keyboard phrases retain irregular
  real key-down/up recordings; thunder still starts with a strong real strike
  within 300 ms and retains rolling thunder.

Runtime uses equal-power mixing, a square-root volume slider and a 2/3 amplitude
master gain (−3.52 dB relative to 0.15.0), followed by a shared system peak limiter.
Stereo playback compensates the graph's mono center-gain restoration. No system
volume setting is changed. macOS alert sounds are not redistributed.

## Recording credits

| Output | Original | Source / license | Edits |
| --- | --- | --- | --- |
| `noise-stream.wav` | Stream by gluckose | [Freesound 333987](https://freesound.org/people/gluckose/sounds/333987/), CC0 | Excerpt from 12 s, mono/resample, overlap and level normalization |
| `noise-night.wav` | Crickets Chirping At Night by Lisa Redfern | [SoundBible 2083](https://soundbible.com/2083-Crickets-Chirping-At-Night.html), Public Domain | Excerpt from 3 s, mono/resample, overlap and level normalization |
| `noise-keyboard.wav` | CherryMX Blue — ABS keycaps by Mechvibes | [Mechvibes](https://github.com/hainguyents13/mechvibes/tree/56d7135bcdf6ceb7fe2f4e06f8ca0903277a9e68/soundpacks/keyboard/cherrymx-blue-abs), MIT | 19 actual key-down/up pairs assembled into irregular typing phrases, overlap and level normalization |

Stream and summer-night input files are distributed by [Blanket at bbc88ed3](https://github.com/rafaelmardojai/blanket/blob/bbc88ed3b9dfa8b21805d77286f3183abf88f36f/SOUNDS_LICENSING.md),
which documents the recording licenses separately from its application code. No Blanket code is included.
The Mechvibes MIT license is included alongside these files as `Mechvibes-LICENSE.txt`.

## Stereo field-recording credits

The following edited HQ previews are redistributed under their original licenses.
CC0 dedicates to the public domain; CC BY 4.0 requires attribution, license links and
identification of modifications. Edits are documented above and in the manifest.
No endorsement by any author is implied.

| Output | Original / author | Source | License |
| --- | --- | --- | --- |
| 街头车流 / train | Medium Traffic — **IENBA** | [Original](https://freesound.org/people/IENBA/sounds/865147/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 池塘蛙鸣 / aircraft | lizzie frogs long.wav — **volivieri** | [Original](https://freesound.org/people/volivieri/sounds/634612/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| 庭院落雨 / lightRain | Rain_Falling_On_Ground.wav — **ivolipa** | [Original](https://freesound.org/people/ivolipa/sounds/329113/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 狂风呼啸 / wind | Wind blowing in a field in Texas, USA — **felix.blume** | [Original](https://freesound.org/people/felix.blume/sounds/217506/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 林间鸟鸣 / birds | Bird ambience. Coniferous forest dawn chorus. — **SamsterBirdies** | [Original](https://freesound.org/people/SamsterBirdies/sounds/745273/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 电闪雷鸣 / thunder | 2016-10-06 Thunder Crack.wav — **kingsrow** | [Original](https://freesound.org/people/kingsrow/sounds/361772/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 沙滩海浪 / ocean | Sea - Ocean - Beach - Close - MP3 — **nebulousflynn** | [Original](https://freesound.org/people/nebulousflynn/sounds/220531/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| 人声鼎沸 / cafe | restaurant busy full walla mandarin active Beijing, China.flac — **kyles** | [Original](https://freesound.org/people/kyles/sounds/452408/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 柴火燃烧 / fire | Wood Burning Stove — **nebulousflynn** | [Original](https://freesound.org/people/nebulousflynn/sounds/269062/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
