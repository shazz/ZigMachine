"""The stream ring from the host side (host/audio_pcm.c): a whole sample refilled ahead of its
channel (zg.samplePlay: the EXTERNAL replay, on the sound CPU on the board) and the cart's own feed
(zg.audioFeed: the INTERNAL one). tests/audio_pcm_test.c drives it over a plain buffer; the
worklet's refillSample (docs/audio-worklet-sealed.js) is the same algorithm in the browser."""

from __future__ import annotations

import subprocess
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
WORK = FPGA / "build" / "tests" / "audio_pcm"
WABT = FPGA / ".tools/wabt"


def test_the_ring_is_refilled_ahead_looped_fed_and_stopped_as_the_worklet_does() -> None:
    # The headers: wasm2c's aplayer.h, machine.h, rom.h, and a cart's (host.h wants one: tutorial's).
    subprocess.run(["make", "-s", "memmap", "build/host/common/aplayer.h", "build/host/tutorial/cart.h"],
                   cwd=FPGA, check=True, capture_output=True)  # fmt: skip
    WORK.mkdir(parents=True, exist_ok=True)
    exe = WORK / "audio_pcm_test"
    inc = ["-Ihost", "-Ibuild/host/common", "-Ibuild/host/tutorial", f"-I{WABT}/share/wabt/wasm2c", f"-I{WABT}/include"]
    subprocess.run(["cc", "-std=gnu11", "-O1", "-Wall", "-Werror", "-Wno-unused-function", *inc,
                    "tests/audio_pcm_test.c", "host/audio_pcm.c", "-o", str(exe)], cwd=FPGA, check=True)  # fmt: skip
    run = subprocess.run([str(exe)], capture_output=True, text=True, check=False)
    lines = run.stdout.splitlines()
    assert [ln for ln in lines if not ln.startswith("ok ")] == []
    assert len(lines) == 13 and run.returncode == 0
