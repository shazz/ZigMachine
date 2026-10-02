"""The ZigMachine SoC: a VexRiscv cart CPU, its RAM, and the machine's blocks as
they are written. Two targets share one SoC class:

    uv run python soc/zigmachine_soc.py --target sim          # generate (and --run with Verilator)
    uv run python soc/zigmachine_soc.py --target z7 --build   # bitstream (needs the board XDC)

Without --run, `sim` elaborates the SoC and writes its CSR map and C headers
(build/soc_sim/csr.json, software/include/generated/) but no gateware, so it
works with no simulator installed: it is what `make soc` checks. --run needs
Verilator.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from litex.build.generic_platform import Pins, Subsignal
from litex.build.sim import SimPlatform
from litex.build.sim.config import SimConfig
from litex.soc.cores.clock import S7PLL
from litex.soc.integration.builder import Builder
from litex.soc.integration.soc_core import SoCCore
from migen import ClockDomain, If, Module, Signal

from soc.zm_video import ZMVideoTiming

FPGA = Path(__file__).resolve().parent.parent
SYS_CLK_SIM = int(1e6)
SYS_CLK_Z7 = int(100e6)
PIX_CLK = int(40e6)  # VESA 800x600 @ 60 Hz, see rtl/video/zm_vtiming.v
SIM_IO = [
    ("sys_clk", 0, Pins(1)),
    ("sys_rst", 0, Pins(1)),
    (
        "serial",
        0,
        Subsignal("source_valid", Pins(1)),
        Subsignal("source_ready", Pins(1)),
        Subsignal("source_data", Pins(8)),
        Subsignal("sink_valid", Pins(1)),
        Subsignal("sink_ready", Pins(1)),
        Subsignal("sink_data", Pins(8)),
    ),
]


class _SimCRG(Module):
    """sys from the sim's clocker, with a power-on reset. Without the reset
    pulse VexRiscv never loads its reset vector and fetches from 0 forever."""

    def __init__(self, clk: object) -> None:
        self.clock_domains.cd_sys = ClockDomain()
        self.clock_domains.cd_por = ClockDomain(reset_less=True)
        por = Signal(4, reset=15)
        self.comb += [self.cd_sys.clk.eq(clk), self.cd_por.clk.eq(clk), self.cd_sys.rst.eq(por != 0)]
        self.sync.por += If(por != 0, por.eq(por - 1))


class _Z7CRG(Module):
    """sys at 100 MHz and the 40 MHz pixel clock from the board's PL oscillator."""

    def __init__(self, platform: object, osc_name: str, osc_hz: int) -> None:
        self.clock_domains.cd_sys = ClockDomain()
        self.clock_domains.cd_pix = ClockDomain()
        self.submodules.pll = pll = S7PLL(speedgrade=-1)
        pll.register_clkin(platform.request(osc_name), osc_hz)  # type: ignore[attr-defined]  # untyped LiteX platform
        pll.create_clkout(self.cd_sys, SYS_CLK_Z7)
        pll.create_clkout(self.cd_pix, PIX_CLK)


class ZigMachineSoC(SoCCore):
    def __init__(
        self,
        platform: object,
        sys_clk: int,
        video_cd: str,
        rom_size: int = 0x8000,
        main_ram_size: int = 0x10000,
        **kwargs: object,
    ) -> None:
        SoCCore.__init__(
            self,
            platform,
            clk_freq=sys_clk,
            ident="ZigMachine",
            cpu_type="vexriscv",
            cpu_variant="standard",
            integrated_rom_size=rom_size,
            integrated_main_ram_size=main_ram_size,
            **kwargs,
        )
        self.video = ZMVideoTiming(platform, cd=video_cd)
        self.irq.add("video", use_loc_if_exists=True)


def build_sim(args: argparse.Namespace) -> None:
    platform = SimPlatform("SIM", SIM_IO)
    soc = ZigMachineSoC(platform, SYS_CLK_SIM, "sys", uart_name="sim")
    soc.crg = _SimCRG(platform.request("sys_clk"))
    sim_config = SimConfig()
    sim_config.add_clocker("sys_clk", freq_hz=SYS_CLK_SIM)
    sim_config.add_module("serial2console", "serial")
    builder = Builder(soc, output_dir=str(FPGA / "build/soc_sim"), compile_software=args.run)
    builder.build(sim_config=sim_config, run=args.run, build=args.run)


def build_z7(args: argparse.Namespace) -> None:
    from soc import litex_compat
    from soc.platform_z7 import Platform

    litex_compat.install()  # Verilog is written here, see soc/litex_compat.py
    platform = Platform(toolchain=args.toolchain)
    # The Z7-Lite UART is on PS MIO (the ARM's), not PL pins: the console runs over USB-JTAG.
    soc = ZigMachineSoC(platform, SYS_CLK_Z7, "pix", uart_name="jtag_uart")
    soc.crg = _Z7CRG(platform, args.osc, args.osc_hz)
    Builder(soc, output_dir=str(FPGA / "build/soc_z7"), compile_software=args.build).build(run=args.build)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--target", choices=["sim", "z7"], required=True)
    p.add_argument("--run", action="store_true", help="sim: compile and run with Verilator")
    p.add_argument("--build", action="store_true", help="z7: run the toolchain to a bitstream")
    p.add_argument("--toolchain", choices=["vivado", "openxc7"], default="openxc7")
    p.add_argument("--osc", default="PL_CLK_50M", help="z7: the XDC port of the PL oscillator (Z7-Lite: 50 MHz on N18)")
    p.add_argument("--osc-hz", type=int, default=int(50e6), help="z7: its frequency (check the schematic)")
    args = p.parse_args()
    (build_sim if args.target == "sim" else build_z7)(args)


if __name__ == "__main__":
    main()
