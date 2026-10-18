"""Monty's native replay (libs/zig/players/digi_monty*.zig) against Musashi, the oracle:
Mad Max's "Auf Weidersehen Monty - digidrums" (TEX NEO SHOW's tune), its audio-core writes
digested a frame at a time (host/sndh_oracle.c), must be the same over the whole song, past
its wrap; the drums (Timer D, 10593 Hz) come in at frame ~2,300. The helpers are
test_sndh_native.py's. Needs `make sndh-oracle` and docs/demo-audio.wasm."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest
from test_sndh_native import FPGA, MUSIC, first_difference, modes_run, native_status, run

MONTY = "auf_weidersehen_monty_digi.sndh"
DRUMS = 2_300  # the first drum's frame, about (b848353: 38.4 s)
WHOLE = 23_000  # 6 min 23 s: the song wraps at frame 21,889 (play 18,241: every voice's track at its $FF)
HANDLER_LSR = 0x44C + 0x52  # the Timer D handler's `lsr.w #1,d0` (digi_monty.zig irq)


@pytest.fixture(scope="module", autouse=True)
def oracle() -> None:
    subprocess.run(["make", "-s", "sndh-oracle"], cwd=FPGA, check=True, capture_output=True)


def test_monty_native_writes_the_same_as_musashi_over_the_whole_song(tmp_path: Path) -> None:
    ref, ref_out = run(tmp_path, MONTY, WHOLE, musashi=True)
    got, out = run(tmp_path, MONTY, WHOLE)
    assert native_status(ref_out) == 4 and native_status(out) == 5  # off, then Monty
    assert "ZM SNDH native monty" in out
    drums = [int(x.split()[1]) for x in got[DRUMS : DRUMS + 600]]
    assert max(drums) > 150  # ~176 Timer D writes a frame: the drums are in the comparison
    assert first_difference(ref, got) is None


def test_a_sndh_call_mid_song_reinits_the_same_way(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, MONTY, 3_600, musashi=True, call=(2_500, 1))
    got, _ = run(tmp_path, MONTY, 3_600, call=(2_500, 1))
    assert first_difference(ref, got) is None


def test_the_oracle_catches_volume_c_written_over_the_drums(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, MONTY, 3_000, musashi=True)
    got, _ = run(tmp_path, MONTY, 3_000, mutant=3)
    assert first_difference(ref, got) is not None
    assert ref[:DRUMS - 400] == got[:DRUMS - 400]  # the mutant only acts once the drums own C


def test_switching_1_2_1_2_mid_song_and_mid_drum_leaves_the_stream_unbroken(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, MONTY, 3_600, musashi=True)
    got, out = modes_run(tmp_path, "500:1,1100:2,2700:1,3000:2,3001:3", 3_600, song=MONTY)
    assert out.count(" got ") == 5 and "asked 3 got 2" in out  # no PCM path: mode 3 stays 2
    assert first_difference(ref, got) is None


def test_the_board_queue_never_fills_at_the_lead_over_the_whole_song(tmp_path: Path) -> None:
    _, out = run(tmp_path, MONTY, WHOLE, queue=True)
    m = re.search(r"^ZM QUEUE max (\d+) of (\d+), lead (\d+), dropped (\d+) of (\d+)$", out, re.MULTILINE)
    assert m, out
    most, depth, lead, _, _ = map(int, m.groups())
    assert lead == 4 * 735  # the general lead: Monty writes ~190 a frame, not Beat Dis's 788
    assert most < depth, f"the queue would fill: {most} writes in flight"


def test_one_byte_changed_in_the_driver_plays_on_musashi(tmp_path: Path) -> None:
    music = tmp_path / "music"
    music.mkdir()
    data = bytearray((MUSIC / MONTY).read_bytes())
    data[HANDLER_LSR] ^= 1
    (music / MONTY).write_bytes(bytes(data))
    got, out = run(tmp_path, MONTY, 120, music=music)
    assert native_status(out) == 0
    ref, _ = run(tmp_path, MONTY, 120, musashi=True, music=music)
    assert got == ref
