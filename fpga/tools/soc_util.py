"""Synthesise the whole board SoC (soc/zigmachine_soc.py --target z7, video
pipeline included) with Yosys `synth_xilinx` and report what it costs: the
check that stands in for a bitstream until openXC7's chipdb is set up.

    uv run python tools/soc_util.py      # -> build/soc_z7/soc_util.txt, and a one-line summary

LiteX writes the SoC's Verilog, then stops at the missing chipdb (it exits in
its toolchain's finalize); the sources it collected are read from the platform.
"""

import argparse
import os
import sys
from pathlib import Path

import yowasp_yosys
from litex.soc.integration.builder import Builder

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA))
sys.path.insert(0, str(FPGA / "tools"))
# After the path inserts: soc/ is fpga's package and tools/ is not one.
import util

from soc import zigmachine_soc

OUT = FPGA / "build" / "soc_z7"


def elaborate() -> tuple[list[str], list[str]]:
    """Write the SoC's Verilog; return (sources, include dirs)."""
    args = argparse.Namespace(toolchain="openxc7", osc="PL_CLK_50M", osc_hz=int(50e6), build=False)
    soc, platform = zigmachine_soc.make_z7(args)
    try:
        Builder(soc, output_dir=str(OUT), compile_software=False).build(run=False)
    except SystemExit:  # openXC7's toolchain exits on the missing chipdb, after the Verilog is written
        pass
    sources = [str(s[0]) for s in platform.sources] + [str(OUT / "gateware" / "platform_z7.v")]
    return sources, [str(p) for p in platform.verilog_include_paths]


def synth(sources: list[str], includes: list[str]) -> dict[str, int]:
    report = OUT / "soc_util.txt"
    inc = " ".join(f"-I{i}" for i in includes)
    script = (
        f"read_verilog {inc} {' '.join(sources)}; synth_xilinx -family xc7 -top platform_z7 -flatten; "
        f"tee -q -o {report} stat"
    )
    here = Path.cwd()
    os.chdir(OUT / "gateware")  # the RAM .init files are named relative to it
    try:
        rc = yowasp_yosys.run_yosys(["-q", "-p", script])
    finally:
        os.chdir(here)
    if rc != 0:
        raise RuntimeError("yosys failed on the SoC")
    return util.group_cells(report.read_text())


def main() -> int:
    c = synth(*elaborate())
    pct = 100 * c["LUT"] / util.XC7Z010_LUTS
    print(
        f"platform_z7: {c['LUT']} LUT ({pct:.1f} %), {c['FF']} FF, {c['CARRY4']} CARRY4, {c['BRAM']} BRAM, "
        f"{c['LUTRAM']} LUTRAM, {c['DSP']} DSP"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
