# Focus soundscapes

Twelve deterministic, locally synthesized soundscapes; no music, speech, or external recordings.
Run `python3 scripts/generate-noise.py` to reproduce them (Python standard library only).
Each loop is 16 seconds, mono PCM 16-bit / 22.05 kHz. A one-second overlap joins its seam.
RMS is normalized to 0.24 (about -12.4 dBFS) using smooth saturation, with peaks below 0.92.
Environmental names describe synthesized textures rather than field recordings.
Runtime mixes equal power, maps the volume slider through a square-root curve, and uses a shared system peak limiter.
macOS alert sounds are loaded from the system and are not redistributed.
