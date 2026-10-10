"""Run a cart with music on the board SoC sim (soc/hp_sim.py: the cart CPU, the
players on it, the audio core behind its queue) and hold its sound against the
native host's (tools/audio_sim_compare.py). One hash at the last frame only: a
hashed frame costs ~80 Mcycles of the sim, and the sound would run dry meanwhile.

    uv run python tools/audio_sim_run.py tutorial --frames 120              # YM: music agrees
    uv run python tools/audio_sim_run.py tsl_hybridglenz --mode near        # MOD: every sample, 32 LSB
    uv run python tools/audio_sim_run.py tutorial --model build/soc_hp_drop --tag tutorial_drop  # a mutant

Writes build/hcycles/audio/<cart>/: uart.txt, audio_tap.txt, native.{w,pcm}. The
per-frame cost is in uart.txt ("ZM AF f cart audio", tools/audio_cycles.py).
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
OUT = FPGA / "build/hcycles/audio"


def make(*targets: str, **var: str) -> None:
    args = [f"{k.upper()}={v}" for k, v in var.items()]
    subprocess.run(["make", "-C", str(FPGA), "memmap", *targets, *args], check=True)


def run_sim(image: Path, model: Path, out: Path, timeout: int) -> int:
    rundir = Path("/dev/shm") / f"zm_audio_{out.name}"
    env = dict(os.environ, ZM_SOC=str(model.resolve()), ZM_INIT="sim_zm_ddr.init")
    cmd = ["systemd-run", "--user", "--scope", "-q", "-p", "MemoryMax=6G", "-p", "MemorySwapMax=0"]
    rc = subprocess.run([*cmd, str(FPGA / "tools/cycles_sim.sh"), str(image), str(rundir), str(timeout)], env=env).returncode
    for name in ("uart.txt", "audio_tap.txt"):
        if (rundir / name).exists():
            shutil.copy(rundir / name, out / name)
    shutil.rmtree(rundir, ignore_errors=True)
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("cart")
    ap.add_argument("--frames", type=int, default=120)
    ap.add_argument("--mode", choices=["ym", "exact", "near"], default="ym")
    ap.add_argument("--model", type=Path, default=FPGA / "build/soc_hp", help="the hp_sim build (a mutant's)")
    ap.add_argument("--audio", default="1", help="ZM_AUDIO: 0 builds the firmware without music")
    ap.add_argument("--timeout", type=int, default=6 * 3600)
    ap.add_argument("--tag", help="the output directory's name (default: the cart, + _noaudio)")
    a = ap.parse_args()
    out = OUT / (a.tag or (a.cart if a.audio == "1" else f"{a.cart}_noaudio"))
    out.mkdir(parents=True, exist_ok=True)
    image = f"build/hcycles/sim/{a.cart}/zm_ddr.init"
    make(f"build/host/{a.cart}/host_audio")
    make(image, zm_frames=str(a.frames), zm_every=str(a.frames), zm_audio=a.audio)
    native = out / "native"
    env = dict(os.environ, ZM_AUDIO_LOG=str(native))
    host = FPGA / f"build/host/{a.cart}/host_audio"
    subprocess.run([str(host), a.cart, str(a.frames + 8), str(a.frames + 8)], env=env, check=True, capture_output=True)
    rc = run_sim(FPGA / image, a.model, out, a.timeout)
    print(f"sim rc={rc}: {out.relative_to(FPGA)}")
    if a.audio != "1":
        return rc
    cmp = [sys.executable, str(FPGA / "tools/audio_sim_compare.py"), str(native), str(out / "uart.txt")]
    return subprocess.run([*cmp, str(out / "audio_tap.txt"), "--mode", a.mode]).returncode


if __name__ == "__main__":
    sys.exit(main())
