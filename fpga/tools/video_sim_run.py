"""The video integration test (Fable #9): run carts on the cart CPU with the RTL
video pipeline in Verilator (soc/video_sim.py), compare the PFB hashes with
apps/scene_hash.mjs and the native host, and run the sequencer's mutants: the
line-major order must fail on badflicker and equinox; the others (no drain, no
write-back copy) are reported, not required to fail (rtl/video/README.md
"Integration" says why). Then write the report (tools/video_sim_report.py).

    uv run python tools/video_sim_run.py                      # the five carts + the mutants
    uv run python tools/video_sim_run.py tutorial --frames 4 --every 2 --no-mutant
    uv run python tools/video_sim_run.py --report-only

The memory path is the board's recommended one (fpga/CYCLES.md "Memory path"):
the CPU on an HP port with an 8-entry store buffer (`hp_sb`), the video DMA on
an HP port with the same first-beat latency for reads and writes. `--mem` takes
another of tools/mempath_cfg.py's configurations for the CPU.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA))  # soc/, for mempath_cfg's zm_memtiming
# After the path insert: tools/ is not a package.
import cycles_run
import mempath_cfg
import video_sim_report

VCYC = FPGA / "build/vcycles"
SOC = FPGA / "build/soc_video"
CARTS = ["tutorial", "union_main", "badflicker", "equinox", "dhs_0pxl0reg"]
# The sequencer's mutants: no drain (with and without the handler probes, and
# the probe-free control), no copy of the compositor's write-backs, and the
# line-major order a beam-racing compositor would impose.
MUTANTS = ["nodrain", "drain_np", "nodrain_np", "nocopy", "linemajor"]
MUTANT = list(CARTS)  # the mutants run on whichever of these are run
MUST_FAIL = {("linemajor", "badflicker"), ("linemajor", "equinox")}  # tools/video_order_shelf.py's two
DMA_CFG = {"rd_lat": mempath_cfg.HP, "wr_lat": mempath_cfg.HP}  # bursts: the latency once each
# A loaded DDR (CYCLES.md: ~410 ns a read under four saturating HP masters): the
# store buffer drains one single-beat write every 16 cycles. The drain rule must
# hold here too, and here a sequencer without it is caught (see the report).
mempath_cfg.MEM.setdefault("hp_sb_sat", {"rd_lat": mempath_cfg.HP_LOADED, "sb_depth": 8, "sb_drain": 64})
mempath_cfg.MEM.setdefault("hp_sb_loaded", {"rd_lat": mempath_cfg.HP_LOADED, "sb_depth": 8, "sb_drain": 16})


def cfg_file(name: str, params: dict[str, int]) -> Path:
    """A zm_memcfg.init for `params`, in zm_memtiming.CFG order."""
    mempath_cfg.MEM[name] = params
    path = VCYC / "cfg" / f"{name}.init"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(mempath_cfg.memcfg_text(name))
    return path


def build(carts: list[str], variants: list[str], frames: int, every: int, jobs: int) -> None:
    images = [f"build/vcycles/{v}/{t}/main_ram.init" for t in carts for v in variants]
    cycles_run.make("memmap", *[f"build/host/{t}/host" for t in carts], frames=frames, every=every, jobs=jobs)
    cycles_run.make(*images, frames=frames, every=every, jobs=jobs)


def run_one(tag: str, variant: str, mem: str, timeout: int) -> str:
    rundir = Path("/dev/shm") / f"zm_video_{mem}_{variant}_{tag}"
    env = dict(os.environ, ZM_SOC=str(SOC), ZM_INIT="sim_zm_ram.init")
    env |= {"ZM_MEMCFG": str(VCYC / "cfg" / f"{mem}.init"), "ZM_DMACFG": str(VCYC / "cfg" / "dma.init")}
    image = VCYC / variant / tag / "main_ram.init"
    cmd = [str(FPGA / "tools/cycles_sim.sh"), str(image), str(rundir), str(timeout)]
    rc = subprocess.run(cmd, env=env, check=False).returncode
    dst = VCYC / "uart" / mem / variant / f"{tag}.txt"
    dst.parent.mkdir(parents=True, exist_ok=True)
    uart = rundir / "uart.txt"
    dst.write_bytes(uart.read_bytes() if uart.exists() else b"")
    subprocess.run(["rm", "-rf", str(rundir)], check=False)
    verdict = video_sim_report.verdict(tag, video_sim_report.parse(dst.read_text()))
    if variant != "drain":
        verdict += " (caught)" if verdict != "ok" else " (survived)"
    return f"{mem:6} {variant:10} {tag:16} rc={rc} {verdict}"


def run_all(a: argparse.Namespace) -> int:
    """Build, run every (cart, build) one by one; the count of runs that broke the contract."""
    cfg_file(a.mem, mempath_cfg.MEM[a.mem])
    cfg_file("dma", DMA_CFG)
    mutant = [] if a.no_mutant else [t for t in MUTANT if t in a.carts]
    build(a.carts, ["drain"] + (a.mutants.split(",") if mutant else []), a.frames, a.every, a.jobs)
    for tag in a.carts:
        cycles_run.references(tag, a.frames, a.every)
    jobs = [] if a.mutant_only else [(t, "drain") for t in a.carts]
    jobs += [(t, v) for t in mutant for v in a.mutants.split(",")]
    bad = 0
    with ThreadPoolExecutor(a.jobs) as pool:
        for (tag, variant), line in zip(jobs, pool.map(lambda j: run_one(j[0], j[1], a.mem, a.timeout), jobs)):
            print(line, flush=True)
            bad += (variant == "drain" and not line.endswith(" ok")) or (
                (variant, tag) in MUST_FAIL and "(survived)" in line
            )
    return bad


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("carts", nargs="*", default=CARTS)
    ap.add_argument("--frames", type=int, default=60)
    ap.add_argument("--every", type=int, default=60, help="hash period (slow on rv32, untimed)")
    ap.add_argument("--mem", default="hp_sb", choices=sorted(mempath_cfg.MEM))
    ap.add_argument("--jobs", type=int, default=1, help="sims at once (the box takes 1)")
    ap.add_argument("--timeout", type=int, default=4 * 3600)
    ap.add_argument("--no-mutant", action="store_true")
    ap.add_argument("--mutant-only", action="store_true", help="only the mutant builds")
    ap.add_argument("--mutants", default=",".join(MUTANTS), help="which mutant builds")
    ap.add_argument("--report-only", action="store_true")
    a = ap.parse_args()
    bad = 0 if a.report_only else run_all(a)
    video_sim_report.main()
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
