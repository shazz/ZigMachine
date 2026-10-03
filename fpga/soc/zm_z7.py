"""The Z7-Lite board build of soc/zigmachine_soc.py: its clocks and its CPU core.

    uv run python -m soc.zigmachine_soc --target z7 --build      # bitstream, openXC7 in Docker

- **Clocks** (one PLL off the 50 MHz PL oscillator): `sys` for the CPU and the
  bus, `comp` for the compositor (rtl/video, crossing in soc/zm_video_cdc.py),
  `pix` (40 MHz, 800x600 at 60 Hz) and `pix5x` for the TMDS serialisers. sys and
  comp are separate because the compositor closes timing well above the CPU
  and both share one frame budget (fpga/README.md "Timing under openXC7").
- **CPU**: the board core is VexRiscv with a 16 KiB 2-way I$, the seal and
  static branch prediction (`BOARD_CORE`, made by `make -C fpga vexgen-board`).
  The same core WITHOUT prediction (`NOPRED_CORE`, same target) closes ~8 % more
  sys fmax over a seed sweep but costs 16-25 % more cycles a frame, so it loses
  (fpga/CYCLES.md "Branch prediction and the clock"). `--cpu-netlist <path>`
  takes any vexgen netlist; `--cpu-netlist standard` LiteX's own core.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from litex.soc.cores.clock import S7PLL
from litex.soc.integration.builder import Builder
from migen import ClockDomain, Module

from soc import openxc7, zm_timing
from soc.zigmachine_soc import PIX_CLK, ZigMachineSoC

FPGA = Path(__file__).resolve().parent.parent
SYS_CLK = int(100e6)
COMP_CLK = int(125e6)
BOARD_CORE = FPGA / "build/vexgen/VexRiscv_I16w2D4Seal.v"
NOPRED_CORE = FPGA / "build/vexgen/VexRiscv_I16w2D4SealNopred.v"
STANDARD = "standard"  # --cpu-netlist: LiteX's own VexRiscv


class Z7CRG(Module):
    """sys, comp, the 40 MHz pixel clock and its 5x, from the board's PL oscillator."""

    def __init__(self, platform: object, osc: tuple[str, int], sys_hz: int, comp_hz: int) -> None:
        osc_name, osc_hz = osc
        self.clock_domains.cd_sys = ClockDomain()
        self.clock_domains.cd_comp = ClockDomain()
        self.clock_domains.cd_pix = ClockDomain()
        self.clock_domains.cd_pix5x = ClockDomain()
        self.submodules.pll = pll = S7PLL(speedgrade=-1)
        clkin = platform.request(osc_name)  # type: ignore[attr-defined]  # untyped LiteX platform
        # The input period is what timing analysis derives every PLL output from:
        # without it nextpnr checks all clocks against its 12 MHz default.
        platform.add_period_constraint(clkin, 1e9 / osc_hz)  # type: ignore[attr-defined]  # untyped LiteX platform
        pll.register_clkin(clkin, osc_hz)
        pll.create_clkout(self.cd_sys, sys_hz)
        pll.create_clkout(self.cd_comp, comp_hz)
        pll.create_clkout(self.cd_pix, PIX_CLK)
        pll.create_clkout(self.cd_pix5x, 5 * PIX_CLK)


def core_netlist(choice: str | None) -> Path | None:
    """The VexRiscv netlist to build around, or None for LiteX's `standard`."""
    if choice == STANDARD:
        return None
    netlist = Path(choice).resolve() if choice else BOARD_CORE
    if not netlist.exists():
        hint = "make -C fpga vexgen-board" if netlist in (BOARD_CORE, NOPRED_CORE) else "vexgen/gen.sh"
        raise FileNotFoundError(f"{netlist}: generate it with `{hint}` (or pass --cpu-netlist {STANDARD})")
    return netlist


def make_z7(args: argparse.Namespace) -> tuple[ZigMachineSoC, object]:
    """The board's SoC and its platform (tools/soc_util.py synthesises them)."""
    from soc import litex_compat
    from soc.platform_z7 import Platform

    litex_compat.install()  # Verilog is written here, see soc/litex_compat.py
    platform = Platform(toolchain=args.toolchain)
    # TIMING (fpga/README.md "Timing under openXC7"): --sys-mhz, --comp-mhz, --cpu-netlist, the CDC constraints.
    sys_hz = int(getattr(args, "sys_mhz", SYS_CLK / 1e6) * 1e6)
    comp_hz = int(getattr(args, "comp_mhz", COMP_CLK / 1e6) * 1e6)
    # The Z7-Lite UART is on PS MIO (the ARM's), not PL pins: the console runs over USB-JTAG.
    soc = ZigMachineSoC(platform, sys_hz, "pipe", glass=not args.no_glass, uart_name="jtag_uart")
    soc.crg = crg = Z7CRG(platform, (args.osc, args.osc_hz), sys_hz, comp_hz)
    soc.csr_bridge_register = True
    clocks = {"sys": (crg.cd_sys.clk, sys_hz), "comp": (crg.cd_comp.clk, comp_hz), "pix": (crg.cd_pix.clk, PIX_CLK)}
    zm_timing.add_cdc_constraints(platform, clocks, [("sys", "pix"), ("comp", "pix"), ("sys", "comp")])
    netlist = core_netlist(getattr(args, "cpu_netlist", None))
    if netlist is not None:
        zm_timing.use_core(soc, platform, netlist)
    return soc, platform


def build_z7(args: argparse.Namespace) -> None:
    soc, _ = make_z7(args)
    in_docker = args.toolchain == "openxc7"  # the tools are in a container: soc/openxc7.py
    if in_docker:
        openxc7.prepare_env()
    builder = Builder(soc, output_dir=str(FPGA / "build/soc_z7"), compile_software=args.build)
    builder.build(run=args.build and not in_docker)
    if in_docker and args.build:
        openxc7.run_build(builder.gateware_dir, soc.get_build_name())
