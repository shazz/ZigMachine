"""CYCLES.md "Memory path": run carts on the cycles sim with the board's memory
latencies (soc/zm_memtiming.py) and other VexRiscv cache geometries (vexgen/).

    uv run python tools/mempath_run.py memory          # the plans of tools/mempath_cfg.py
    uv run python tools/mempath_run.py caches --jobs 2
    uv run python tools/mempath_run.py --report-only   # just tools/mempath_report.py

Per core, one Verilated model (build/soc_mem/<core>, `std` = LiteX's own
VexRiscv.v, the others build/vexgen/VexRiscv_<core>.v from vexgen/gen.sh).
Images are the cycles images (cycles/cycles.mk) built into build/mempath/img
with each cart's frame count (mempath_cfg.FRAMES). Logs land in
build/mempath/uart/<core>/<mem>/<variant>/<cart>.txt; a log that already ended
is not run again (--force does). The hashes are checked against scene_hash.mjs
and the native host exactly as for the cycles table.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA))  # soc.zm_memtiming, for the config word order

import cycles_run  # after the path
import mempath_report
from mempath_cfg import FRAMES, PLANS, memcfg_text

OUT = FPGA / "build/mempath"
IMG = OUT / "img"
SOC_STD = FPGA / "build/soc_mem/std"


def model(core: str) -> Path:
    """build/soc_mem/<core>: the cycles SoC around that core, built once."""
    out = FPGA / "build/soc_mem" / core
    if not (out / "gateware/obj_dir/Vsim").exists():
        cmd = [sys.executable, "-m", "soc.cycles_sim", "--out", str(out)]
        if core != "std":
            cmd += ["--core", str(FPGA / f"build/vexgen/VexRiscv_{core}.v")]
        log = OUT / f"soc_{core}.log"
        with log.open("w") as f:
            if subprocess.run(cmd, cwd=FPGA, stdout=f, stderr=subprocess.STDOUT, check=False).returncode:
                sys.exit(f"mempath_run: model {core} failed, see {log}")
    return out


def image(tag: str, variant: str) -> Path:
    """The cart's firmware image with its frame count, hashed at the last frame."""
    n = FRAMES[tag]
    target = IMG / variant / tag / "main_ram.init"
    stamp = target.parent / f"frames.{n}"
    if not stamp.exists():
        env = dict(os.environ, PATH=f"{FPGA}/.tools/bin:{FPGA}/.tools/wabt/bin:{os.environ['PATH']}")
        cmd = ["make", "-C", str(FPGA), f"CYC={IMG.relative_to(FPGA)}", f"SOC_CYC={SOC_STD.relative_to(FPGA)}",
               f"ZM_FRAMES={n}", f"ZM_EVERY={n}", f"build/host/{tag}/host", str(target.relative_to(FPGA))]  # fmt: skip
        with (OUT / "build.log").open("a") as f:
            if subprocess.run(cmd, env=env, stdout=f, stderr=subprocess.STDOUT, check=False).returncode:
                sys.exit(f"mempath_run: image {variant}/{tag} failed, see {OUT / 'build.log'}")
        stamp.touch()
    cycles_run.references(tag, n, n)
    return target


def run_one(core: str, mem: str, variant: str, tag: str, timeout: int) -> str:
    dst = OUT / "uart" / core / mem / variant / f"{tag}.txt"
    rundir = Path("/dev/shm") / f"zm_mem_{core}_{mem}_{variant}_{tag}"
    cfg = OUT / "cfg" / f"{mem}.init"
    env = dict(os.environ, ZM_SOC=str(FPGA / "build/soc_mem" / core), ZM_MEMCFG=str(cfg))
    sim = [str(FPGA / "tools/cycles_sim.sh"), str(IMG / variant / tag / "main_ram.init"), str(rundir), str(timeout)]
    rc = subprocess.run(sim, env=env, check=False).returncode
    dst.parent.mkdir(parents=True, exist_ok=True)
    uart = rundir / "uart.txt"
    dst.write_bytes(uart.read_bytes() if uart.exists() else b"")
    subprocess.run(["rm", "-rf", str(rundir)], check=False)
    return f"{core:11} {mem:13} {variant:9} {tag:16} rc={rc}"


def done(core: str, mem: str, variant: str, tag: str) -> bool:
    log = OUT / "uart" / core / mem / variant / f"{tag}.txt"
    return log.exists() and b"ZM END" in log.read_bytes()


def jobs_of(plan_names: list[str], force: bool) -> list[tuple[str, str, str, str]]:
    jobs = []
    for name in plan_names:
        for p in PLANS[name]:
            for mem in p.mems:
                for variant in p.variants:
                    jobs += [(p.core, mem, variant, t) for t in p.carts]
    jobs = list(dict.fromkeys(jobs))  # plans overlap: run each once
    return [j for j in jobs if force or not done(*j)]


def prepare(jobs: list[tuple[str, str, str, str]]) -> None:
    (OUT / "cfg").mkdir(parents=True, exist_ok=True)
    model("std")  # the images' CSR header comes from it
    for core, mem, variant, tag in jobs:
        (OUT / "cfg" / f"{mem}.init").write_text(memcfg_text(mem))
        model(core)
        image(tag, variant)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("plans", nargs="*", help=f"plan names: {', '.join(PLANS)} (tools/mempath_cfg.py)")
    ap.add_argument("--jobs", type=int, default=2, help="sims at once")
    ap.add_argument("--timeout", type=int, default=6 * 3600, help="seconds per sim")
    ap.add_argument("--force", action="store_true", help="re-run logs that already ended")
    ap.add_argument("--report-only", action="store_true")
    a = ap.parse_args()
    if unknown := set(a.plans) - set(PLANS):
        ap.error(f"unknown plan(s): {', '.join(sorted(unknown))}")
    if not a.report_only:
        jobs = jobs_of(a.plans, a.force)
        prepare(jobs)
        with ThreadPoolExecutor(a.jobs) as pool:
            for line in pool.map(lambda j: run_one(*j, a.timeout), jobs):
                print(line, flush=True)
    mempath_report.main()


if __name__ == "__main__":
    main()
