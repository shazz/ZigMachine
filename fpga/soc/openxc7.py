"""LiteX's `--toolchain openxc7`, run through tools/openxc7.sh's container.

LiteX writes the build script on the host (yosys -> nextpnr-xilinx ->
fasm2frames -> xc7frames2bit) and would run it there too, but the tools live
only in the Docker image. So the script is written with `run=False` and then
executed in the container, which mounts the repo at its own path: every path
LiteX wrote stays valid. CHIPDB and PRJXRAY_DB_DIR point at the host caches
`make -C fpga toolchain` fills (fpga/.tools/chipdb, fpga/.tools/prjxray-db).
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

from soc import openxc7_fast

FPGA = Path(__file__).resolve().parent.parent
WRAPPER = FPGA / "tools/openxc7.sh"
DBPART = "xc7z010clg400"


class ToolchainMissingError(FileNotFoundError):
    def __init__(self, what: Path) -> None:
        super().__init__(f"{what} not found: run `make -C fpga toolchain` (builds the openXC7 image and the chipdb)")


def prepare_env() -> None:
    """Point LiteX at the cached chipdb and prjxray-db. Without them LiteX would
    try to generate a chipdb on the host, with tools the host does not have."""
    chipdb = Path(os.environ.setdefault("CHIPDB", str(FPGA / ".tools/chipdb")))
    db = Path(os.environ.setdefault("PRJXRAY_DB_DIR", str(FPGA / ".tools/prjxray-db")))
    for needed in (chipdb / f"{DBPART}.bin", db / "zynq7"):
        if not needed.exists():
            raise ToolchainMissingError(needed)


# nextpnr-xilinx options LiteX has no knob for (fpga/README.md "Timing under openXC7").
# Congestion-driven spreading: without it the glass SoC (PS7 + GP0) packs into a
# hot spot the router never clears (overuse falls to ~150, then grows); the PS7's
# own tie-offs route in 2 iterations on an empty die. OPENXC7_PNR_OPTS overrides.
# The timing weight is TIMING_FABLE.md P1-2 (92.8 -> 100.3 MHz, seed 1).
PNR_OPTS = os.environ.get("OPENXC7_PNR_OPTS", "--placer-heap-congestion-spread --placer-heap-timingweight 30")
# LiteX hardcodes `synth_xilinx ... -abc9`; without it sys gains ~13 % fmax for ~13 % LUTs
# (TIMING_FABLE.md P1-1: 92.8 -> 105.7 MHz). OPENXC7_ABC9=1 restores it.
KEEP_ABC9 = os.environ.get("OPENXC7_ABC9") == "1"
# The placer's seed, pinned: one netlist gives 76-102 MHz on sys over seeds 1-12
# (fpga/README.md "Timing under openXC7"), so the seed is part of the build. Seed 8
# met sys 100 and comp 125 MHz (100.6 / 125.2) on the 2026-10-03 netlist; the ODDR
# serialiser (rtl/video/zm_dvi_out.v) changed the netlist and seed 8 fell to 93.1 / 107.5.
# Re-swept over seeds 1-5 (fpga/build/hdmi_oddr_soc/results.txt): seed 5 is the best,
# sys 102.3 MHz (pass), comp 118.4 MHz (misses 125; no seed of the six met it). The
# same netlist and seed give the same placement, bit for bit. A changed netlist draws
# again: re-sweep. OPENXC7_SEED overrides.
SEED = int(os.environ.get("OPENXC7_SEED", "5"))
# The fast loop (soc/openxc7_fast.py, fpga/README.md "When is a full rebuild needed"), all opt-in:
# OPENXC7_STABLE=1 stable cell names (a REUSE base); OPENXC7_REUSE=<gateware dir> replays that
# build's placement; OPENXC7_FAST=1 adds FAST_OPTS (multi-threaded placement refinement).
STABLE = os.environ.get("OPENXC7_STABLE") == "1"
REUSE = os.environ.get("OPENXC7_REUSE", "")
FAST = os.environ.get("OPENXC7_FAST") == "1"
FAST_OPTS = "--parallel-refine --threads 4"


# A cap on nextpnr's run time in seconds (OPENXC7_PNR_TIMEOUT; 0 = none): a placement that
# stalls (2026-10-03: 52 min looping on "congestion-spread") must not hold the shared lock.
PNR_TIMEOUT = int(os.environ.get("OPENXC7_PNR_TIMEOUT", "1500"))


def add_pnr_opts(script: Path, opts: str = PNR_OPTS) -> None:
    """Splice `opts` (and the PNR_TIMEOUT cap) into the nextpnr-xilinx line of LiteX's build script."""
    text = script.read_text()
    if "nextpnr-xilinx " not in text:
        raise ValueError(f"{script}: no nextpnr-xilinx line to add {opts!r} to")
    if opts and opts not in text:
        text = text.replace("nextpnr-xilinx ", f"nextpnr-xilinx {opts} ", 1)
    if PNR_TIMEOUT and "timeout " not in text:
        text = text.replace("nextpnr-xilinx ", f"timeout {PNR_TIMEOUT} nextpnr-xilinx ", 1)
    script.write_text(text)


def set_seed(script: Path, seed: int = SEED) -> None:
    """Replace the `--seed N` LiteX writes (nextpnr would refuse a second one)."""
    text = script.read_text()
    if not re.search(r"--seed \d+", text):
        raise ValueError(f"{script}: no --seed on the nextpnr-xilinx line")
    script.write_text(re.sub(r"--seed \d+", f"--seed {seed}", text, count=1))


def drop_abc9(ys: Path) -> None:
    """Remove -abc9 from LiteX's synth_xilinx line."""
    text = ys.read_text()
    if "synth_xilinx" not in text:
        raise ValueError(f"{ys}: no synth_xilinx line")
    ys.write_text(text.replace(" -abc9", ""))


def no_srl(ys: Path) -> None:
    """Add -nosrl to LiteX's synth_xilinx line: SRL16E/SRLC32E fail on the board under
    openXC7 (make prim-test, 2026-10-09: srl16e and srlc32e lanes FAIL)."""
    text = ys.read_text()
    if "synth_xilinx" not in text:
        raise ValueError(f"{ys}: no synth_xilinx line")
    if "-nosrl" not in text:
        ys.write_text(text.replace("synth_xilinx", "synth_xilinx -nosrl", 1))


def run_build(gateware_dir: str, build_name: str, gen_s: float = 0.0) -> None:
    """Run LiteX's generated build_<name>.sh inside the openXC7 container, timed stage by
    stage (tools/build_times.py prints them and appends build/build_times.txt). gen_s: the
    seconds LiteX took to elaborate and write the build, recorded as stage `gen`."""
    gw = Path(gateware_dir)
    script, ys = gw / f"build_{build_name}.sh", gw / f"{build_name}.ys"
    fast = FAST_OPTS if FAST else ""
    add_pnr_opts(script, f"{PNR_OPTS} {fast} {openxc7_fast.pnr_outputs(build_name)}".replace("  ", " ").strip())
    set_seed(script)
    no_srl(ys)
    if not KEEP_ABC9:
        drop_abc9(ys)
    openxc7_fast.time_stages(script)
    if REUSE:  # before this directory loses its mark below: REUSE may name it
        openxc7_fast.add_reuse(script, Path(REUSE).resolve(), build_name)
    (gw / openxc7_fast.STABLE_MARK).unlink(missing_ok=True)
    if STABLE or REUSE:
        openxc7_fast.stable_names(ys)
    try:
        subprocess.run([str(WRAPPER), "run", "bash", f"build_{build_name}.sh"], cwd=gateware_dir, check=True)
    finally:
        with (gw / "stages.txt").open("a") as f:
            f.write(f"gen 0 {gen_s:.3f}\n")
        label = f"{build_name} seed={SEED}" + (f" reuse={REUSE}" if REUSE else "") + (" stable" if STABLE else "")
        subprocess.run(
            [sys.executable, str(FPGA / "tools/build_times.py"), gateware_dir, "--label", label], check=False
        )
