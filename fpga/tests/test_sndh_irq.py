"""The handler-only native drivers (libs/zig/players/digi_irq.zig) against Musashi, the oracle:
each tune's timer interrupt in Zig, its init and play on Musashi. The audio core's writes,
digested a frame at a time (host/sndh_oracle.c), must be the same over the length given, across
a mid-tune sndhCall and mode switches 1/2; mutant 5 (the steps play patches into the handler
frozen when it was armed) and 6 (the stream handler's registers 9 and 10 swapped) must fail. The helpers are test_sndh_native.py's.
Needs `make sndh-oracle` and docs/demo-audio.wasm."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest
from test_sndh_native import FPGA, MUSIC, first_difference, native_status

ORACLE = FPGA / "build/host/oracle/sndh_oracle"
# song, tune, frames (past each tune's first wrap where it has one), the status it must be.
TUNES = [
    ("union/thalion_forever.sndh", 1, 6_000, 8),  # the Union Demo's TEX tracker screen
    ("digital/Ace_2.sndh", 1, 3_000, 7),  # the B.I.G. Demo's digital screen, and the rest of it
    ("digital/Labello.sndh", 1, 3_000, 7),
    ("digital/Phantom_Of_The_Asteroid.sndh", 1, 3_000, 7),
    ("digital/Phantom_Of_The_Asteroid.sndh", 2, 3_000, 7),
    ("digital/Sanxion.sndh", 1, 3_000, 7),
    ("digital/Starpaws.sndh", 1, 3_000, 7),
    ("big/Labello.sndh", 1, 3_000, 7),
    ("snyd90_f6.sndh", 1, 6_000, 12),  # snyd_90's part 6: a 3-voice mixer on Timer C
    ("tcb_spreadpoint.sndh", 1, 6_000, 13),  # TCB's Spreadpoint screen: three volume streams
]
# song, the mutant that must be caught (sndh_native.zig): 5 = steps frozen at arming, 6 = registers 9/10 swapped.
MUTANTS = [("union/thalion_forever.sndh", 5), ("digital/Ace_2.sndh", 5), ("snyd90_f6.sndh", 5),
           ("tcb_spreadpoint.sndh", 6)]


@pytest.fixture(scope="module", autouse=True)
def oracle() -> None:
    subprocess.run(["make", "-s", "sndh-oracle"], cwd=FPGA, check=True, capture_output=True)


def run(tmp: Path, song: str, tune: int, frames: int, *, musashi: bool = False, mutant: int = 0,
        call: tuple[int, int] | None = None, modes: str = "") -> tuple[list[str], str]:
    """The frame digests and the console, for one subtune."""
    digest = tmp / f"{'m' if musashi else 'n'}{mutant}{tune}.d"
    env = {**os.environ, "ZM_AUDIO_DIGEST": str(digest), "ZM_MUSIC_DIR": str(MUSIC)}
    for k in ("ZM_SNDH_MUSASHI", "ZM_SNDH_MUTANT", "ZM_SNDH_MODES"):
        env.pop(k, None)
    if musashi:
        env["ZM_SNDH_MUSASHI"] = "1"
    if mutant:
        env["ZM_SNDH_MUTANT"] = str(mutant)
    if modes:
        env["ZM_SNDH_MODES"] = modes
    args = [str(ORACLE), song, str(tune), str(frames), *(map(str, call) if call else ())]
    out = subprocess.run(args, env=env, check=True, capture_output=True, text=True).stdout
    return digest.read_text().splitlines(), out


@pytest.mark.parametrize(("song", "tune", "frames", "status"), TUNES)
def test_the_native_handler_writes_the_same_as_musashi(tmp_path: Path, song: str, tune: int, frames: int,
                                                     status: int) -> None:
    ref, ref_out = run(tmp_path, song, tune, frames, musashi=True)
    got, out = run(tmp_path, song, tune, frames)
    assert native_status(ref_out) == 4 and native_status(out) == status
    assert sum(int(x.split()[1]) for x in got) > 100 * frames  # a digi: hundreds of writes a frame
    assert first_difference(ref, got) is None


@pytest.mark.parametrize("song", [m[0] for m in MUTANTS])
def test_a_sndh_call_and_mode_switches_mid_tune_change_nothing(tmp_path: Path, song: str) -> None:
    ref, _ = run(tmp_path, song, 1, 1_600, musashi=True, call=(777, 1))
    got, _ = run(tmp_path, song, 1, 1_600, call=(777, 1))
    assert first_difference(ref, got) is None
    ref, _ = run(tmp_path, song, 1, 1_600, musashi=True)
    got, out = run(tmp_path, song, 1, 1_600, modes="300:1,700:2,1100:1,1300:2")
    assert out.count(" got ") == 4 and "asked 1 got 1" in out and "asked 2 got 2" in out
    assert first_difference(ref, got) is None


@pytest.mark.parametrize(("song", "mutant"), MUTANTS)
def test_the_oracle_catches_a_wrong_handler(tmp_path: Path, song: str, mutant: int) -> None:
    ref, _ = run(tmp_path, song, 1, 600, musashi=True)
    got, _ = run(tmp_path, song, 1, 600, mutant=mutant)
    assert first_difference(ref, got) is not None


def test_one_changed_byte_of_the_handler_plays_on_musashi(tmp_path: Path) -> None:
    data = bytearray((MUSIC / "union/thalion_forever.sndh").read_bytes())
    at = data.find(bytes.fromhex("48e7e0c072007000"))
    data[at + 0x72 + 2] ^= 1  # subi.w #$180 -> #$181
    (tmp_path / "t.sndh").write_bytes(bytes(data))
    env = {**os.environ, "ZM_AUDIO_DIGEST": str(tmp_path / "x.d"), "ZM_MUSIC_DIR": str(tmp_path)}
    out = subprocess.run([str(ORACLE), "t.sndh", "1", "5"], env=env, check=True, capture_output=True,
                         text=True).stdout
    assert native_status(out) == 0
