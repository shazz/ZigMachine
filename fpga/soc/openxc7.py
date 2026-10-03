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
from pathlib import Path

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
# is the one of those twelve that meets both sys 100 and comp 125 MHz (100.6 / 125.2)
# on the 2026-10-03 netlist; the same netlist and seed give the same placement,
# bit for bit. A changed netlist draws again: re-sweep. OPENXC7_SEED overrides.
SEED = int(os.environ.get("OPENXC7_SEED", "8"))


def add_pnr_opts(script: Path, opts: str = PNR_OPTS) -> None:
    """Splice `opts` into the nextpnr-xilinx line of LiteX's build script."""
    text = script.read_text()
    if "nextpnr-xilinx " not in text:
        raise ValueError(f"{script}: no nextpnr-xilinx line to add {opts!r} to")
    if opts and opts not in text:
        script.write_text(text.replace("nextpnr-xilinx ", f"nextpnr-xilinx {opts} ", 1))


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


def run_build(gateware_dir: str, build_name: str) -> None:
    """Run LiteX's generated build_<name>.sh inside the openXC7 container."""
    add_pnr_opts(Path(gateware_dir) / f"build_{build_name}.sh")
    set_seed(Path(gateware_dir) / f"build_{build_name}.sh")
    if not KEEP_ABC9:
        drop_abc9(Path(gateware_dir) / f"{build_name}.ys")
    subprocess.run([str(WRAPPER), "run", "bash", f"build_{build_name}.sh"], cwd=gateware_dir, check=True)
