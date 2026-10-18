"""Wow Scroller's native replay (libs/zig/players/digi_wow.zig) against Musashi, the oracle:
MAN Cool's tune for the Union Demo's TCB2 WOW!-SCROLLER, a Timer A digi at 7585 Hz. Its
audio-core writes, digested a frame at a time (host/sndh_oracle.c), must be the same over the
whole tune, past its wrap; mode 3 (sndh_pcm.zig) must follow the YM path and hand back on the
same sample. The helpers are test_sndh_native.py's. Needs `make sndh-oracle` and
docs/demo-audio.wasm."""

from __future__ import annotations

import os
import re
import statistics
import subprocess
from pathlib import Path

import pytest
from test_sndh_native import FPGA, MUSIC, correlation, first_difference, left, modes_run, native_status, run

WOW = "union/wow_scroller.sndh"
# 15 segments, 253,473 bytes at 7585.19 Hz = 33.4 s = ~2,005 frames: twice round and more.
WHOLE = 4_500


@pytest.fixture(scope="module", autouse=True)
def oracle() -> None:
    subprocess.run(["make", "-s", "sndh-oracle"], cwd=FPGA, check=True, capture_output=True)


def test_wow_native_writes_the_same_as_musashi_over_the_whole_tune(tmp_path: Path) -> None:
    ref, ref_out = run(tmp_path, WOW, WHOLE, musashi=True)
    got, out = run(tmp_path, WOW, WHOLE)
    assert native_status(ref_out) == 4 and native_status(out) == 6  # off, then Wow Scroller
    assert "ZM SNDH native wow_scroller" in out
    assert sum(int(x.split()[1]) for x in got) > 300 * WHOLE  # ~3 writes an interrupt, 126 a frame
    assert first_difference(ref, got) is None


def test_a_sndh_call_mid_tune_reinits_the_same_way(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, WOW, 1_500, musashi=True, call=(777, 1))
    got, _ = run(tmp_path, WOW, 1_500, call=(777, 1))
    assert first_difference(ref, got) is None


def test_the_oracle_catches_beat_dis_handler_reused_for_wow(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, WOW, 300, musashi=True)
    got, _ = run(tmp_path, WOW, 300, mutant=4)
    assert first_difference(ref, got) is not None


def test_switching_1_2_1_2_mid_tune_leaves_the_stream_unbroken(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, WOW, 2_400, musashi=True)
    got, out = modes_run(tmp_path, "500:1,1100:2,1700:1,2000:2", 2_400, song=WOW)
    assert out.count(" got ") == 4 and "asked 1 got 1" in out and "asked 2 got 2" in out
    assert first_difference(ref, got) is None


def test_mode_3_plays_pcm_and_hands_back_on_the_same_sample(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, WOW, 2_400, musashi=True)
    got, out = modes_run(tmp_path, "1200:3,1800:2", 2_400, song=WOW)
    assert "asked 3 got 3" in out
    differ = [i for i, (r, g) in enumerate(zip(ref, got, strict=True)) if r != g]
    assert differ[0] == 1_200 and differ[-1] <= 1_800  # only while in mode 3


def sound(tmp: Path, name: str, plan: str | None, frames: int, mutant: int = 0) -> list[int]:
    env = {k: v for k, v in os.environ.items() if not k.startswith("ZM_SNDH_")}
    env.update({"ZM_AUDIO_LOG": str(tmp / name), "ZM_MUSIC_DIR": str(MUSIC)})
    if plan:
        env["ZM_SNDH_MODES"] = plan
    if mutant:
        env["ZM_SNDH_MUTANT"] = str(mutant)
    subprocess.run([str(FPGA / "build/host/oracle/sndh_oracle"), WOW, "0", str(frames)], env=env, check=True)
    return left((tmp / f"{name}.pcm").read_bytes())[10 * 735 :]


def test_mode_3_sounds_like_the_ym_and_the_raw_bytes_would_not(tmp_path: Path) -> None:
    ym = sound(tmp_path, "ym", None, 600)
    pcm = sound(tmp_path, "pcm", "1:3", 600)
    raw = sound(tmp_path, "raw", "1:3", 600, mutant=2)
    assert correlation(ym, pcm) > 0.8
    assert correlation(ym, raw) < 0.6
    assert 0.8 < statistics.pstdev(pcm) / statistics.pstdev(ym) < 1.2  # Beat Dis's table: its level


def test_the_board_queue_never_fills_at_the_lead_over_the_whole_tune(tmp_path: Path) -> None:
    _, out = run(tmp_path, WOW, WHOLE, queue=True)
    m = re.search(r"^ZM QUEUE max (\d+) of (\d+), lead (\d+), dropped (\d+) of (\d+)$", out, re.MULTILINE)
    assert m, out
    most, depth, _, _, _ = map(int, m.groups())
    assert most < depth, f"the queue would fill: {most} writes in flight"


def test_a_changed_byte_of_its_code_plays_on_musashi(tmp_path: Path) -> None:
    music = tmp_path / "music"
    (music / "union").mkdir(parents=True)
    data = bytearray((MUSIC / WOW).read_bytes())
    data[0x212] ^= 1  # the handler's lsl.l #3
    (music / WOW).write_bytes(bytes(data))
    got, out = run(tmp_path, WOW, 120, music=music)
    assert native_status(out) == 0
    ref, _ = run(tmp_path, WOW, 120, musashi=True, music=music)
    assert got == ref
