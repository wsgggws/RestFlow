# Original RestFlow audio

These 23 WAV files are synthesized from scratch by `scripts/generate-audio.py`
and distributed under the repository's MIT license. No recordings, sampled
instruments, downloaded music, or third-party sound packs are used.

- `ambient-*.wav`: twelve 16-second mono loops at 22050 Hz, with periodic chord
  beds, circular note tails and deterministic textures. Their IDs match the twelve
  animated scenes. Peaks are normalized to 0.32 for headroom.
- `alert-*.wav`: eleven short tones (2–2.8 seconds), with different envelopes,
  harmonic balances and note patterns. Peaks are normalized to 0.44.

Glass is loaded by name from macOS; no Apple audio file is redistributed.
The nature-inspired names describe synthesized textures, not field recordings.

Regenerate: `python3 scripts/generate-audio.py` from any working directory.
