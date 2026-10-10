"""The native SNDH replays (libs/zig/players/digi.zig) against Musashi, the oracle:
the audio core's writes, (stamp, register, value), digested a frame at a time by
host/sndh_oracle.c, must be the same over the whole tune. Also the board's write
queue (host/audio_queue.h) at the native player's lead, and recognition's refusals.
Needs `make sndh-oracle` (built here) and docs/demo-audio.wasm."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ORACLE = FPGA / "build/host/oracle/sndh_oracle"
MUSIC = FPGA.parent / "docs/music"
BEAT_DIS = "union/beat_dis.sndh"
# 3,154,210 bytes at 15753.85 Hz = 200.2 s = 12,012 frames: past the loop's wrap.
WHOLE = 12_100
PLAY_ADD = 0x64 + 0x146 + 3  # the immediate of play's `addi.w #1,(a2)` (prototypes/beatdis_re)


@pytest.fixture(scope="module", autouse=True)
def oracle() -> None:
    subprocess.run(["make", "-s", "sndh-oracle"], cwd=FPGA, check=True, capture_output=True)


def run(
    tmp: Path,
    song: str,
    frames: int,
    *,
    musashi: bool = False,
    mutant: int = 0,
    call: tuple[int, int] | None = None,
    music: Path = MUSIC,
    queue: bool = False,
) -> tuple[list[str], str]:
    """The frame digests ("frame writes fnv64") and the console."""
    digest = tmp / f"{'m' if musashi else 'n'}{mutant}.d"
    env = {**os.environ, "ZM_AUDIO_DIGEST": str(digest), "ZM_MUSIC_DIR": str(music)}
    env.pop("ZM_SNDH_MUSASHI", None)
    if musashi:
        env["ZM_SNDH_MUSASHI"] = "1"
    if mutant:
        env["ZM_SNDH_MUTANT"] = str(mutant)
    if queue:
        env["ZM_AUDIO_QUEUE"] = "1"
    args = [str(ORACLE), song, "0", str(frames), *(map(str, call) if call else ())]
    out = subprocess.run(args, env=env, check=True, capture_output=True, text=True).stdout
    return digest.read_text().splitlines(), out


def first_difference(ref: list[str], got: list[str]) -> str | None:
    for r, g in zip(ref, got, strict=True):
        if r != g:
            return f"first differing frame: Musashi {r!r}, native {g!r}"
    return None


def native_status(console: str) -> int:
    m = re.search(r"^ZM ORACLE native (\d+)$", console, re.MULTILINE)
    assert m, console
    return int(m.group(1))


def test_beat_dis_native_writes_the_same_as_musashi_over_the_whole_tune(tmp_path: Path) -> None:
    ref, ref_out = run(tmp_path, BEAT_DIS, WHOLE, musashi=True)
    got, out = run(tmp_path, BEAT_DIS, WHOLE)
    assert native_status(ref_out) == 4 and native_status(out) == 1  # off, then Beat Dis
    assert "ZM SNDH native beat_dis" in out
    assert len(got) == WHOLE + 1 and sum(int(x.split()[1]) for x in got) > 9_000_000
    assert first_difference(ref, got) is None


def test_a_sndh_call_mid_tune_reinits_the_same_way(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, BEAT_DIS, 3_000, musashi=True, call=(1_234, 1))
    got, _ = run(tmp_path, BEAT_DIS, 3_000, call=(1_234, 1))
    assert first_difference(ref, got) is None


def test_the_oracle_catches_a_replay_without_the_vbl_overshoot(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, BEAT_DIS, 600, musashi=True)
    got, _ = run(tmp_path, BEAT_DIS, 600, mutant=1)
    assert first_difference(ref, got) is not None


def test_the_board_queue_never_fills_at_the_native_lead_over_the_whole_tune(tmp_path: Path) -> None:
    _, out = run(tmp_path, BEAT_DIS, WHOLE, queue=True)
    m = re.search(r"^ZM QUEUE max (\d+) of (\d+), lead (\d+), dropped (\d+) of (\d+)$", out, re.MULTILINE)
    assert m, out
    most, depth, lead, dropped, writes = map(int, m.groups())
    assert lead == 3 * 735  # the native digi's lead (host/audio_queue.h zma_lead)
    assert most < depth, f"the queue would fill: {most} writes in flight"
    assert dropped > writes // 3  # the unchanged volume writes, ~47 %


def test_a_near_miss_plays_on_musashi_and_says_so(tmp_path: Path) -> None:
    music = tmp_path / "music"
    (music / "union").mkdir(parents=True)
    data = bytearray((MUSIC / BEAT_DIS).read_bytes())
    data[PLAY_ADD] ^= 1
    (music / BEAT_DIS).write_bytes(bytes(data))
    got, out = run(tmp_path, BEAT_DIS, 120, music=music)
    assert native_status(out) == 2
    assert "ZM SNDH near miss: the digi handler with an unknown sequencer, on Musashi" in out
    ref, _ = run(tmp_path, BEAT_DIS, 120, musashi=True, music=music)
    assert got == ref


def test_a_tune_without_the_handler_is_silently_musashi(tmp_path: Path) -> None:
    _, out = run(tmp_path, "sos.sndh", 10)
    assert native_status(out) == 0
    assert "ZM SNDH" not in out


def test_no_two_frames_digest_alike_so_a_shifted_stream_cannot_pass(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, BEAT_DIS, 60, musashi=True)
    assert len(set(ref[1:])) == len(ref) - 1


# --- zg.requestSndhMode (libs/zig/players/sndh_native.zig): 1 st, 2 native, 3 pcm ----------
def modes_run(tmp: Path, plan: str, frames: int, song: str = BEAT_DIS) -> tuple[list[str], str]:
    os.environ["ZM_SNDH_MODES"] = plan
    try:
        return run(tmp, song, frames)
    finally:
        del os.environ["ZM_SNDH_MODES"]


def test_switching_1_2_1_2_mid_tune_leaves_the_stream_unbroken(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, BEAT_DIS, 2_400, musashi=True)
    got, out = modes_run(tmp_path, "500:1,1100:2,1700:1,2000:2", 2_400)
    assert out.count(" got ") == 4 and "asked 1 got 1" in out and "asked 2 got 2" in out
    assert first_difference(ref, got) is None


def test_mode_3_plays_the_samples_on_pcm_and_hands_back_on_the_same_sample(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, BEAT_DIS, 2_400, musashi=True)
    got, out = modes_run(tmp_path, "1200:3,1800:2", 2_400)
    assert "asked 3 got 3" in out
    differ = [i for i, (r, g) in enumerate(zip(ref, got, strict=True)) if r != g]
    assert differ[0] == 1_200 and differ[-1] <= 1_800  # only while in mode 3
    pcm = tmp_path / "p3"
    os.environ["ZM_AUDIO_LOG"] = str(pcm)
    try:
        modes_run(tmp_path, "1:3", 120)
    finally:
        del os.environ["ZM_AUDIO_LOG"]
    writes = [ln.split() for ln in (tmp_path / "p3.w").read_text().splitlines() if ln.startswith("W ")]
    late = [w for w in writes if int(w[1]) > 10 * 735]
    assert late and all(int(w[2], 16) >= 0x100 for w in late)  # PCM channel fields, no YM volumes
    assert len((tmp_path / "p3.pcm").read_bytes()) == 120 * 735 * 4


def test_an_unknown_mode_is_refused_and_changes_nothing(tmp_path: Path) -> None:
    ref, _ = run(tmp_path, BEAT_DIS, 600)
    got, out = modes_run(tmp_path, "300:0,301:7", 600)
    assert "asked 0 got 0" in out and "asked 7 got 0" in out
    assert got == ref


def test_a_tune_without_a_native_driver_stays_in_mode_1_and_says_so(tmp_path: Path) -> None:
    _, out = modes_run(tmp_path, "5:2,6:3", 10, song="sos.sndh")
    assert "asked 2 got 1" in out and "asked 3 got 1" in out
