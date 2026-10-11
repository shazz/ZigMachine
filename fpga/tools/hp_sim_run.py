"""The board SoC's simulation (soc/hp_sim.py, cycles/board.mk): run carts on the
cart CPU with main RAM and the video DMA in a model of the PS's DDR behind HP0
and HP1, and compare the PFB hashes with apps/scene_hash.mjs and the native host
(the verdict is tools/video_sim_report.py's: ran to the end, no underrun, both
references equal).

    uv run python tools/hp_sim_run.py tutorial                 # 10 frames, hashed every 5
    uv run python tools/hp_sim_run.py tutorial --frames 4 --every 2
    uv run python tools/hp_sim_run.py raytrace_f32 --fpu       # hard-float images on the FPU core (make soc-hp-fpu)
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA))
# After the path insert: tools/ is not a package.
import cycles_run
import video_sim_report

HCYC = FPGA / "build/hcycles"
SOC = FPGA / "build/soc_hp"


def run_one(tag: str, timeout: int, fpu: bool = False) -> str:
    rundir = Path("/dev/shm") / f"zm_hp_{tag}{'_fpu' if fpu else ''}"
    env = dict(os.environ, ZM_SOC=f"{SOC}{'_fpu' if fpu else ''}", ZM_INIT="sim_zm_ddr.init")
    image = HCYC / f"sim{'_fpu' if fpu else ''}" / tag / "zm_ddr.init"
    cmd = ["systemd-run", "--user", "--scope", "-q", "-p", "MemoryMax=6G", "-p", "MemorySwapMax=0"]
    cmd += [str(FPGA / "tools/cycles_sim.sh"), str(image), str(rundir), str(timeout)]
    rc = subprocess.run(cmd, env=env, check=False).returncode
    dst = HCYC / "uart" / f"{tag}{'_fpu' if fpu else ''}.txt"
    dst.parent.mkdir(parents=True, exist_ok=True)
    uart = rundir / "uart.txt"
    dst.write_bytes(uart.read_bytes() if uart.exists() else b"")
    subprocess.run(["rm", "-rf", str(rundir)], check=False)
    verdict = video_sim_report.verdict(tag, video_sim_report.parse(dst.read_text()))
    return f"hp {tag:16} rc={rc} {verdict}  ({dst.relative_to(FPGA)})"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("carts", nargs="+")
    ap.add_argument("--frames", type=int, default=10)
    ap.add_argument("--every", type=int, default=5)
    ap.add_argument("--timeout", type=int, default=4 * 3600)
    ap.add_argument("--fpu", action="store_true", help="ZM_FPU=1 images on build/soc_hp_fpu (the f32 FPU core)")
    a = ap.parse_args()
    sim = "sim_fpu" if a.fpu else "sim"
    images = [f"build/hcycles/{sim}/{t}/zm_ddr.init" for t in a.carts]
    cycles_run.make("memmap", *[f"build/host/{t}/host" for t in a.carts], frames=a.frames, every=a.every, jobs=1)
    cycles_run.make(*images, *(["ZM_FPU=1"] if a.fpu else []), frames=a.frames, every=a.every, jobs=1)
    bad = 0
    for tag in a.carts:
        cycles_run.references(tag, a.frames, a.every)
        line = run_one(tag, a.timeout, a.fpu)
        print(line, flush=True)
        bad += not line.split("  (")[0].endswith(" ok")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
