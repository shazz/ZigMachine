"""A cart that starts its stream in its init (apps/zig/scenes/stream.zig) runs before the players
are up: host/main.c and cycles/bmain.c boot the audio side after the cart. The start used to reach
audio_pcm.c's uninstantiated player and the native host_audio segfaulted (song_pack's run of
`stream`, audio.mk). host/audio_bridge.c now holds the start until audio_live(), as the browser
holds it until its AudioContext is up, and drops the feeds before it."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent


def test_a_stream_started_in_the_carts_init_plays_once_the_players_are_up(tmp_path: Path) -> None:
    subprocess.run(["make", "-s", "memmap", "build/host/stream/host_audio"], cwd=FPGA, check=True, capture_output=True)
    env = dict(os.environ, ZM_AUDIO_LOG=str(tmp_path / "log"))
    run = subprocess.run([str(FPGA / "build/host/stream/host_audio"), "stream", "10", "10"], env=env,
                         capture_output=True, text=True, check=False)  # fmt: skip
    assert run.returncode == 0, run.stderr[-2000:]
    writes = (tmp_path / "log.w").read_text().split("\n")
    # Paula channel 0: TRIGGER (CTRL 2) and the step of 12517 Hz (12517 / 44100 * 65536 = 0x48a9).
    assert any(w.endswith(" 120 00000002") for w in writes) and any(w.endswith(" 110 000048a9") for w in writes)
