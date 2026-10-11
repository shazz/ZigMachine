"""The cart's effects queue (libs/zig/sfx_queue.zig: zg.requestSndhMode, sfxPlay, ymWrite,
requestModVolume) off the board's song bridge (host/audio_bridge.c) and into the players, as the
browser's worklet applies it (docs/FPGA_SOUND_CPU.md "Effects").

- Natively: union_beatdis's own key 3 (through the glass's router, ZM_GLASS_KEYS) switches Beat Dis
  to mode 3 exactly as the oracle's direct switch at the same sample does, write for write; key 2
  (the default mode) changes nothing.
- On the sound CPU (BARD), in the board SoC sim: tools/bard_fx_run.py. The switch crosses the
  mailbox and the core's writes are the oracle's with it; the mutant that drops it must fail. The
  sim takes tens of minutes: ZM_BARD_SIM=1 runs it, else the last run's outputs are checked again
  (skipped when there are none).
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
HOST = FPGA / "build/host/union_beatdis/host_audio"
ORACLE = FPGA / "build/host/oracle/sndh_oracle"
SONG = "union/beat_dis.sndh"
SPACE = "200:1000020,201:20"  # the 1 MB version (Beat Dis), once the pictures have depacked
FRAMES = 420
SPAN = 190  # frames of the song compared
Write = tuple[int, str, str]


@pytest.fixture(scope="module", autouse=True)
def built() -> None:
    subprocess.run(
        ["make", "-s", "memmap", str(HOST.relative_to(FPGA)), "sndh-oracle"], cwd=FPGA, check=True, capture_output=True
    )


def song_writes(log: Path) -> list[Write]:
    """The writes from the song's first ("L"), stamped from it, over SPAN frames."""
    out, t0 = [], None
    for line in log.read_text().splitlines():
        f = line.split()
        if f[0] == "L" and t0 is None:
            t0 = int(f[1])
        elif f[0] == "W" and t0 is not None and int(f[1]) - t0 < SPAN * 735:
            out.append((int(f[1]) - t0, f[2], f[3]))
    return out


def host(tmp: Path, keys: str) -> tuple[list[Write], str, int]:
    """host_audio on union_beatdis with a key script: its song's writes, its console, the song's stamp."""
    env = {**os.environ, "ZM_AUDIO_LOG": str(tmp / "h"), "ZM_GLASS_KEYS": keys}
    out = subprocess.run(
        [str(HOST), "union_beatdis", str(FRAMES), str(FRAMES)], env=env, check=True, capture_output=True, text=True
    ).stdout
    song = re.search(rf"^L (\d+) \d+ {SONG}$", (tmp / "h.w").read_text(), re.MULTILINE)
    assert song, "the cart never started Beat Dis"
    return song_writes(tmp / "h.w"), out, int(song.group(1))


def oracle(tmp: Path, mode_at: str | None) -> list[Write]:
    env = {k: v for k, v in os.environ.items() if not k.startswith("ZM_SNDH_")}
    env["ZM_AUDIO_LOG"] = str(tmp / "o")
    if mode_at:
        env["ZM_SNDH_MODE_AT"] = mode_at
    subprocess.run([str(ORACLE), SONG, "1", str(SPAN + 10)], env=env, check=True, capture_output=True)
    return song_writes(tmp / "o.w")


def test_key_3_on_the_screen_switches_the_players_as_the_oracle_does(tmp_path: Path) -> None:
    got, out, song = host(tmp_path, f"{SPACE},300:1000033,301:33")
    m = re.search(r"^ZM SNDH mode asked 3 got 3 at (\d+)$", out, re.MULTILINE)
    assert m, out
    at = int(m.group(1)) - song
    assert got == oracle(tmp_path, f"{at}:3")
    assert got != oracle(tmp_path, None)  # mode 3 left the YM's volumes to the PCM channel


def test_key_2_the_default_mode_changes_no_write(tmp_path: Path) -> None:
    got, out, _ = host(tmp_path, f"{SPACE},300:1000032,301:32")
    assert re.search(r"^ZM SNDH mode asked 2 got 2 at \d+$", out, re.MULTILINE), out
    assert got == oracle(tmp_path, None)


def bard(drop: bool) -> subprocess.CompletedProcess[str]:
    out = FPGA / f"build/hcycles/audio/bard_fx{'_drop' if drop else ''}"
    args = ["uv", "run", "python", "tools/bard_fx_run.py", *(["--drop"] if drop else [])]
    if not os.environ.get("ZM_BARD_SIM"):
        if not (out / "audio_tap.txt").exists():
            pytest.skip("no BARD sim run (ZM_BARD_SIM=1 runs it: tens of minutes)")
        args += ["--skip-build", "--skip-sim"]
    return subprocess.run(args, cwd=FPGA, check=False, capture_output=True, text=True)


def test_the_mode_switch_crosses_the_mailbox_and_bard_plays_the_oracles_writes() -> None:
    r = bard(drop=False)
    assert r.returncode == 0, r.stdout + r.stderr
    assert re.search(r"against the oracle WITH the switch: 0 differences", r.stdout), r.stdout


def test_a_dropped_request_never_reaches_bard_and_the_check_fails() -> None:
    r = bard(drop=True)
    assert r.returncode == 1, r.stdout + r.stderr
    assert "no mode switch" in r.stdout and "bard_fx: FAIL" in r.stdout, r.stdout
