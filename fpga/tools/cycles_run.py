"""Plan step 0b-ii: run carts on the VexRiscv in the cycles sim and keep each
run's UART log, then write the report (tools/cycles_report.py).

    uv run python tools/cycles_run.py union_beatdis blitter       # default variants
    uv run python tools/cycles_run.py --variants nobounds --frames 120 --every 40 stniccc
    uv run python tools/cycles_run.py --report-only                # re-read build/cycles/uart

Every (cart, variant) is one firmware image (cycles/cycles.mk) run once in the
ONE Verilated model; runs are independent, so they go `--jobs` at a time. Each
cart's scene_hash.mjs JSON and native-host JSON for the same frames are written
next to the logs, and the report refuses any run whose hashes differ from them.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import cycles_report

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
CYC = FPGA / "build/cycles"
VARIANTS = ["nobounds", "float", "aligned", "stock"]


def make(*targets: str, frames: int, every: int, jobs: int) -> None:
    env = dict(os.environ, PATH=f"{FPGA}/.tools/bin:{FPGA}/.tools/wabt/bin:{os.environ['PATH']}")
    cmd = ["make", "-C", str(FPGA), f"-j{jobs}", f"ZM_FRAMES={frames}", f"ZM_EVERY={every}", *targets]
    log = CYC / "build.log"
    with log.open("a") as out:
        if subprocess.run(cmd, env=env, stdout=out, stderr=subprocess.STDOUT, check=False).returncode:
            sys.exit(f"cycles_run: build failed, see {log}")


def references(tag: str, frames: int, every: int) -> None:
    """scene_hash.mjs (the oracle) and the native host, for the same frames."""
    ref = CYC / "ref"
    ref.mkdir(parents=True, exist_ok=True)
    args = [f"docs/demo-{tag}.wasm", str(frames), str(every)]
    for name, cmd in (("js", ["node", "apps/scene_hash.mjs"]), ("native", [str(FPGA / f"build/host/{tag}/host")])):
        out = ref / f"{tag}.{frames}.{every}.{name}.json"
        if not out.exists():
            with out.open("w") as f:
                subprocess.run([*cmd, *args], cwd=ROOT, stdout=f, stderr=subprocess.DEVNULL, check=False)


def run_one(tag: str, variant: str, timeout: int) -> str:
    image = CYC / variant / tag / "main_ram.init"
    rundir = Path("/dev/shm") / f"zm_cycles_{variant}_{tag}"  # the sim's working files, off the disk
    rc = subprocess.run(
        [str(FPGA / "tools/cycles_sim.sh"), str(image), str(rundir), str(timeout)], check=False
    ).returncode
    dst = CYC / "uart" / variant / f"{tag}.txt"
    dst.parent.mkdir(parents=True, exist_ok=True)
    uart = rundir / "uart.txt"
    dst.write_bytes(uart.read_bytes() if uart.exists() else b"")
    subprocess.run(["rm", "-rf", str(rundir)], check=False)
    return f"{variant:9} {tag:28} rc={rc}"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("carts", nargs="*", help="cart tags (docs/demo-<tag>.wasm)")
    ap.add_argument("--variants", default=",".join(VARIANTS))
    ap.add_argument("--frames", type=int, default=60)
    ap.add_argument("--every", type=int, default=30, help="hash period; slow on rv32, untimed")
    ap.add_argument("--jobs", type=int, default=4, help="sims at once (each is one core, ~0.2 GB)")
    ap.add_argument("--timeout", type=int, default=6 * 3600, help="seconds per sim")
    ap.add_argument("--report-only", action="store_true")
    a = ap.parse_args()
    variants = a.variants.split(",")
    if not a.report_only:
        CYC.mkdir(parents=True, exist_ok=True)
        make(
            "memmap",
            "cycles-sim",
            *[f"build/host/{t}/host" for t in a.carts],
            frames=a.frames,
            every=a.every,
            jobs=a.jobs,
        )
        images = [f"build/cycles/{v}/{t}/main_ram.init" for t in a.carts for v in variants]
        make(*images, frames=a.frames, every=a.every, jobs=a.jobs)
        for tag in a.carts:
            references(tag, a.frames, a.every)
        jobs = [(t, v) for v in variants for t in a.carts]  # reference figures first
        with ThreadPoolExecutor(a.jobs) as pool:
            for line in pool.map(lambda j: run_one(j[0], j[1], a.timeout), jobs):
                print(line, flush=True)
    cycles_report.main([])


if __name__ == "__main__":
    main()
