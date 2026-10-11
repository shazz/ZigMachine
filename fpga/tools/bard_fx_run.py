"""A cart's zg.requestSndhMode carried from the cart CPU to the sound CPU (BARD) and applied
there, on the board SoC sim with the sound CPU (soc/hp_sim.py --sound-cpu), held against the
native players (host/sndh_oracle.c) switching at the same sample.

    flock <build.lock> uv run python tools/bard_fx_run.py --build-only     # the image (make snd-fx)
    flock <sim.lock>   uv run python tools/bard_fx_run.py --skip-build     # the sim, then the check
    ... --drop                                                              # the mutant: bsound.c drops it

The image is cycles/sound/sfx_cart.c (a scripted cart: SONG at frame 1, the mode at FX_AT) over the
real cart-side path (host/audio_bridge.c, cycles/bsound.c, the mailbox) and the sound CPU's play
image. BARD says where it applied the switch ("ZM SNDH mode asked m got g at ts"); the oracle
replays the song with the switch at that sample from the song's start, and once without it.
The core's writes (the audio tap) must be the oracle's with the switch, and must differ from
the oracle's without it (the switch changed something). Exit 0 when both hold.
The mutant never reaches BARD: it is checked against the switch at FX_AT's frame and must fail.
Writes build/hcycles/audio/bard_fx[_drop]/: uart.txt, audio_tap.txt, the oracle's logs.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import audio_sim_compare as cmp

SONG, TUNE, FX_AT, FX_MODE, FRAMES = "union/beat_dis.sndh", 1, 4, 3, 10
MODEL = FPGA / "build/soc_hp_snd"
ORACLE = FPGA / "build/host/oracle/sndh_oracle"
FRAME = 735
MODE_AT = re.compile(r"^ZM SNDH mode asked (\d+) got (\d+) at (\d+)$", re.MULTILINE)


def image_dir(drop: bool) -> Path:
    return FPGA / f"build/hcycles/snd/fx{'_drop' if drop else ''}"


def build(drop: bool) -> None:
    var = [f"SONG={SONG}", f"TUNE={TUNE}", f"FX_AT={FX_AT}", f"FX_MODE={FX_MODE}", f"ZM_FRAMES={FRAMES}"]
    subprocess.run(
        ["make", "-C", str(FPGA), "snd-fx", "sndh-oracle", *var, *(["FX_DROP=1"] if drop else [])], check=True
    )


def run_sim(drop: bool, out: Path, timeout: int) -> int:
    rundir = Path("/dev/shm") / f"zm_bard_fx{'_drop' if drop else ''}"
    env = dict(os.environ, ZM_SOC=str(MODEL), ZM_INIT="sim_zm_ddr.init")
    scope = ["systemd-run", "--user", "--scope", "-q", "-p", "MemoryMax=6G", "-p", "MemorySwapMax=0"]
    sim = [str(FPGA / "tools/cycles_sim.sh"), str(image_dir(drop) / "zm_ddr.init"), str(rundir), str(timeout)]
    rc = subprocess.run([*scope, *sim], check=False, env=env).returncode
    for name in ("uart.txt", "audio_tap.txt"):
        if (rundir / name).exists():
            shutil.copy(rundir / name, out / name)
    shutil.rmtree(rundir, ignore_errors=True)
    return rc


def oracle(prefix: Path, frames: int, mode_at: int | None) -> str:
    env = {k: v for k, v in os.environ.items() if not k.startswith("ZM_SNDH_")}
    env["ZM_AUDIO_LOG"] = str(prefix)
    if mode_at is not None:
        env["ZM_SNDH_MODE_AT"] = f"{mode_at}:{FX_MODE}"
    r = subprocess.run([str(ORACLE), SONG, str(TUNE), str(frames)], env=env, check=True, capture_output=True, text=True)
    return r.stdout


def differences(prefix: Path, uart: str, tap: str) -> tuple[list[str], int]:
    """audio_sim_compare's write check: the oracle's writes as the board queues them, from the song."""
    nw, ns, _ = cmp.parse_log(Path(f"{prefix}.w").read_text(), "L ")
    _, bs, _ = cmp.parse_log(uart, "ZM SONG ")
    bw, _, samples = cmp.parse_log(tap, "-")
    if ns is None or bs is None:
        return [f"no song started (oracle {ns}, board {bs})"], 0
    nw, ns = cmp.board_queue(nw, ns)
    span = min(len(samples) - bs[0], len(Path(f"{prefix}.pcm").read_bytes()) // 4 - ns[0])
    return cmp.compare_writes(nw, ns, bw, bs, span), span


def check(out: Path, drop: bool) -> int:
    uart = (out / "uart.txt").read_text(errors="replace")
    tap = (out / "audio_tap.txt").read_text()
    song = re.search(r"^ZM SONG (\d+) \d+ (\S+)$", uart, re.MULTILINE)
    switch = MODE_AT.search(uart)
    print(f"bard_fx: song {song.group(0) if song else None}; BARD: {switch.group(0) if switch else 'no mode switch'}")
    if switch and song:
        at = int(switch.group(3)) - int(song.group(1))
    else:  # nothing reached BARD: the switch where the cart asked for it, a frame after the song's
        at = (FX_AT - 1) * FRAME
    said = oracle(out / "with", FRAMES + 8, at)
    oracle(out / "without", FRAMES + 8, None)
    print("bard_fx: oracle: " + " / ".join(line for line in said.splitlines() if "mode" in line))
    with_bad, span = differences(out / "with", uart, tap)
    without_bad, _ = differences(out / "without", uart, tap)
    print(f"bard_fx: switch at +{at} samples from the song; {span} samples compared")
    print(f"bard_fx: against the oracle WITH the switch: {len(with_bad)} differences")
    for line in with_bad[:5]:
        print("  " + line)
    print(f"bard_fx: against the oracle WITHOUT it: {len(without_bad)} differences")
    ok = switch is not None and int(switch.group(2)) == FX_MODE and not with_bad and bool(without_bad)
    print("bard_fx: " + ("ok" if ok else "FAIL") + (" (the mutant)" if drop else ""))
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--drop", action="store_true", help="the mutant: bsound.c drops every effect")
    ap.add_argument("--build-only", action="store_true")
    ap.add_argument("--skip-build", action="store_true")
    ap.add_argument("--skip-sim", action="store_true", help="check the last run's outputs again")
    ap.add_argument("--timeout", type=int, default=3 * 3600)
    a = ap.parse_args()
    out = FPGA / f"build/hcycles/audio/bard_fx{'_drop' if a.drop else ''}"
    out.mkdir(parents=True, exist_ok=True)
    if not a.skip_build:
        build(a.drop)
    if a.build_only:
        return 0
    if not a.skip_sim:
        rc = run_sim(a.drop, out, a.timeout)
        print(f"bard_fx: sim rc={rc}")
    return check(out, a.drop)


if __name__ == "__main__":
    sys.exit(main())
