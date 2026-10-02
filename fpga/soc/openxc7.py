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


def run_build(gateware_dir: str, build_name: str) -> None:
    """Run LiteX's generated build_<name>.sh inside the openXC7 container."""
    subprocess.run([str(WRAPPER), "run", "bash", f"build_{build_name}.sh"], cwd=gateware_dir, check=True)
