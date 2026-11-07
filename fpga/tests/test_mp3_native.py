"""The MP3 PLAYER on the native host (host_audio: the cart, KOS GEMDOS on --c-image docs/mp3-c.img, the players
through wasm2c as BARD runs them, the machine's own chips): Down Down Return through the glass's router plays
C:\\MUSIC\\TONES44.MP3, and the machine's 16-bit out is the reference decode >> 1 sample for sample (the pin
apps/mp3_check.mjs holds, fpga/tools/mp3_ref.sh's), as on the page. A cart that is never asked to play is silent.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
HOST = FPGA / "build/host/mp3_player/host_audio"
IMG = FPGA.parent / "docs/mp3-c.img"
PIN44 = "bf403e4f2ee2e764b7a8ce2807f363206f691aad3dc6890b98b2b7d63d2516d9"
SAMPLES = 308 * 1152  # TONES44's frames, a side
LEAD_ZEROS = 140  # the reference's first samples that are 0 after >> 1 (decoder + encoder delay)
KEYS = "30:100e021,31:e021,32:100e021,33:e021,34:100000d,35:d"  # Down, Down, Return (KEY_DOWN = 1 << 24)
FRAMES = 600


@pytest.fixture(scope="module", autouse=True)
def built() -> None:
    subprocess.run(["make", "-s", "memmap", str(HOST.relative_to(FPGA))], cwd=FPGA, check=True, capture_output=True)


def pcm(tmp: Path, keys: str) -> bytes:
    env = {**os.environ, "ZM_AUDIO_LOG": str(tmp / "h"), "ZM_GLASS_KEYS": keys}
    subprocess.run([str(HOST), "mp3_player", str(FRAMES), str(FRAMES), "--c-image", str(IMG)], env=env, check=True,
                   capture_output=True, timeout=600)  # fmt: skip
    return (tmp / "h.pcm").read_bytes()


def test_tones44_off_c_plays_the_reference_decode_shifted_by_one(tmp_path: Path) -> None:
    out = pcm(tmp_path, KEYS)
    first = next(i for i in range(0, len(out), 2) if out[i : i + 2] != b"\0\0")
    first -= first % 4  # a stereo frame's start
    start = first - 4 * LEAD_ZEROS
    span = out[start : start + 4 * SAMPLES]
    assert len(span) == 4 * SAMPLES, "the track did not play to its end inside the run"
    assert hashlib.sha256(span).hexdigest() == PIN44


def test_no_key_no_sound(tmp_path: Path) -> None:
    assert set(pcm(tmp_path, "")) == {0}
