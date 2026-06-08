#!/usr/bin/env python3
"""Generate per-word audio files using offline espeak-ng + ffmpeg → OGG.

Output: apps/codeword/assets/audio/<word_id>.ogg
Reads:  apps/codeword/assets/vocab/*.json

Two-step pipeline:
  1. espeak-ng synthesizes to WAV (American English, slight male variant)
  2. ffmpeg converts WAV → OGG Vorbis (~6× smaller, identical quality for
     speech)

No network, no cloud, no system TTS runtime. Just static assets that
play via audioplayers.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VOCAB_DIR = REPO_ROOT / "apps" / "codeword" / "assets" / "vocab"
AUDIO_DIR = REPO_ROOT / "apps" / "codeword" / "assets" / "audio"

# -v en+m3 = American English, slight male variant (more natural cadence)
# -s 175   = slightly faster than default (175 wpm) — saves bytes
# -p 40    = lower pitch
ESPEAK_ARGS = ["-v", "en+m3", "-s", "175", "-p", "40"]


def synth(text: str) -> bytes:
    """Run espeak-ng and return raw WAV bytes."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        subprocess.run(
            ["espeak-ng", *ESPEAK_ARGS, "-w", str(tmp_path), text],
            check=True, capture_output=True,
        )
        return tmp_path.read_bytes()
    finally:
        tmp_path.unlink(missing_ok=True)


def wav_to_ogg(wav_bytes: bytes) -> bytes:
    """Convert WAV bytes to Opus-in-WebM via ffmpeg pipe (smaller than Vorbis,
    equivalent speech quality)."""
    proc = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", "pipe:0",
         "-c:a", "libopus", "-b:a", "24k", "-f", "ogg", "pipe:1"],
        input=wav_bytes, capture_output=True, check=True,
    )
    return proc.stdout


def generate_one(word_id: str, text: str) -> Path:
    out = AUDIO_DIR / f"{word_id}.ogg"
    if out.exists():
        return out  # skip if already generated
    wav_bytes = synth(text)
    ogg_bytes = wav_to_ogg(wav_bytes)
    out.write_bytes(ogg_bytes)
    return out


def main() -> int:
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    # Wipe any previous WAV artifacts in case this is a re-run.
    for old_wav in AUDIO_DIR.glob("*.wav"):
        old_wav.unlink()

    total = 0
    skipped = 0
    for vocab_file in sorted(VOCAB_DIR.glob("*.json")):
        with vocab_file.open(encoding="utf-8") as f:
            words = json.load(f)
        for w in words:
            wid = w["id"]
            text = w["word"]
            out = AUDIO_DIR / f"{wid}.ogg"
            if out.exists():
                skipped += 1
                continue
            try:
                generate_one(wid, text)
                total += 1
            except subprocess.CalledProcessError as e:
                print(f"FAIL {wid} ({text!r}): {e.stderr.decode(errors='replace')}",
                      file=sys.stderr)
                return 1
    size_mb = sum(f.stat().st_size for f in AUDIO_DIR.glob("*.ogg")) / 1024 / 1024
    print(f"Generated {total} new audio files ({skipped} skipped, "
          f"{total + skipped} total, {size_mb:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
