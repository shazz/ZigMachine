"""Board-build timing knobs for the z7 SoC (fpga/README.md, "Timing under openXC7").

- `add_cdc_constraints`: the crossings between sys, comp and pix as XDC. Every crossing in
  rtl/video and rtl/glass is a toggle synchroniser (ASYNC_REG) or a buffer held
  stable until its toggle lands, so a datapath-only bound of one destination
  period is the honest constraint, not a blanket false path. Vivado honours it.
  openXC7's nextpnr-xilinx reads only set_property, create_clock and
  set_multicycle_path: it warns and skips these lines. It never puts a
  cross-domain path into a clock's fmax anyway (it reports them as "Max delay").
- `use_core`: build around a vexgen netlist (vexgen/gen.sh). A sealed core
  (`:seal`) instantiates rtl/seal/zm_seal.v, so that source comes too.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

FPGA = Path(__file__).resolve().parent.parent
SEAL = FPGA / "rtl/seal"

# LiteX platforms and SoCs are untyped Python classes with no common base worth naming.
LiteX = Any


def add_cdc_constraints(platform: LiteX, clocks: dict[str, tuple[object, int]], pairs: list[tuple[str, str]]) -> None:
    """set_max_delay -datapath_only both ways between each pair of `clocks` (name ->
    (clock net, Hz)), one destination period each."""
    for a, b in pairs:
        for (src, _), (dst, hz) in ((clocks[a], clocks[b]), (clocks[b], clocks[a])):
            sel = "-from [get_clocks -of_objects [get_nets {src}]] -to [get_clocks -of_objects [get_nets {dst}]]"
            platform.add_platform_command(f"set_max_delay -datapath_only {sel} {1e9 / hz:.3f}", src=src, dst=dst)


def is_sealed(netlist: Path) -> bool:
    return "zm_seal " in netlist.read_text()


def use_core(soc: LiteX, platform: LiteX, netlist: Path) -> None:
    """Replace LiteX's VexRiscv with a vexgen netlist (same ports)."""
    if not netlist.exists():
        raise FileNotFoundError(f"{netlist}: generate it with vexgen/gen.sh")
    soc.cpu.use_external_variant(str(netlist))
    if is_sealed(netlist):
        platform.add_source(str(SEAL / "zm_seal.v"))
        platform.add_verilog_include_path(str(SEAL))
