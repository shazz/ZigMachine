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
from litex.soc.integration.builder import Builder
from litex.soc.integration.soc import SoCRegion
from litex.soc.integration.soc_core import SoCCore
from migen import Cat, ClockDomain, If, Module, Signal

from soc.zm_glass import ZMGlass, ps7_gp0
from soc.zm_video import ZMVideoTiming
from soc.zm_video_pipe import WINDOW_BYTES, ZMVideo
from soc.zm_video_snoop import ZMVideoSnoop, attach_snoop

FPGA = Path(__file__).resolve().parent.parent
SYS_CLK_SIM = int(1e6)
PIX_CLK = int(40e6)  # VESA 800x600 @ 60 Hz, see rtl/video/zm_vtiming.v
VIDEO_WINDOW = (
    0x90000000  # in the uncached IO region: the video registers, palettes and BEAM table (soc/zm_video_pipe.py)
)
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


class ZigMachineSoC(SoCCore):
    # TIMING: LiteX registers the Wishbone->CSR bridge only when the SoC has SDRAM. Without it the
    # arbiter grant -> decoder -> bridge -> CSR bank `re` cone was the z7's critical path (11 LUTs).
    csr_bridge_register = False

    def add_csr_bridge(self, name: str = "csr", origin: int | None = None, register: bool = False) -> None:
        super().add_csr_bridge(name=name, origin=origin, register=register or self.csr_bridge_register)

    def __init__(
        self,
        platform: object,
        sys_clk: int,
        video_cd: str,
        rom_size: int = 0x8000,
        main_ram_size: int = 0x10000,
        glass: bool = False,
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
        if video_cd == "pipe":  # the board: the whole pipeline, out through HDMI
            self._add_video_pipe(platform, glass)
        else:
            self.video = ZMVideoTiming(platform, cd=video_cd)
        self.irq.add("video", use_loc_if_exists=True)

    def _add_video_pipe(self, platform: object, glass: bool) -> None:
        req = platform.request  # type: ignore[attr-defined]  # untyped LiteX platform
        lanes = ["D0", "D1", "D2", "CLK"]  # zm_dvi_out's {clock, red, green, blue}, low bit first
        pads = {s.lower(): Cat(*[req(f"HDMI1_{lane}_{s}") for lane in lanes]) for s in ("P", "N")}
        overlay = None
        if glass:  # the ARM's front panel (docs/FPGA_GLASS.md): GP0 registers, the OSD, the cart CPU's reset
            self.glass = ZMGlass(platform)
            self.specials += ps7_gp0(self.glass.axi)
            self.comb += self.cpu.reset.eq(~self.glass.cpu_run)
            overlay = self.glass.overlay
        self.video = ZMVideo(platform, pads, overlay=overlay)
        region = SoCRegion(origin=VIDEO_WINDOW, size=WINDOW_BYTES, cached=False)
        self.bus.add_slave("zm_video", self.video.bus, region)
        self.bus.add_master(name="zm_video_dma", master=self.video.dma)
        # VIDEO SNOOP (rtl/video/README.md "The video region"): the cart's stores to its region, tapped
        # off the CPU's data bus until the HP bridge exists, delivered every cycle.
        self.video_snoop = ZMVideoSnoop(self.cpu.dbus, None, self.video.vbase.storage, Signal(16, reset=1))
        self.comb += [*attach_snoop(self.video, self.video_snoop), self.video.drained.eq(self.video_snoop.empty)]


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
    from soc import zm_z7  # the board's clocks and core: soc/zm_z7.py (it imports this module)

    zm_z7.build_z7(args)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--target", choices=["sim", "z7"], required=True)
    p.add_argument("--run", action="store_true", help="sim: compile and run with Verilator")
    p.add_argument("--build", action="store_true", help="z7: run the toolchain to a bitstream")
    p.add_argument("--toolchain", choices=["vivado", "openxc7"], default="openxc7")
    p.add_argument("--osc", default="PL_CLK_50M", help="z7: the XDC port of the PL oscillator (Z7-Lite: 50 MHz on N18)")
    p.add_argument("--osc-hz", type=int, default=int(50e6), help="z7: its frequency (check the schematic)")
    p.add_argument("--no-glass", action="store_true", help="z7: no ARM front panel; the CPU runs from reset (JTAG)")
    p.add_argument("--sys-mhz", type=float, default=100.0, help="z7: the sys clock (CPU, bus)")
    p.add_argument("--comp-mhz", type=float, default=125.0, help="z7: the compositor's clock (soc/zm_video_cdc.py)")
    p.add_argument(
        "--cpu-netlist", help="z7: a vexgen VexRiscv netlist (default soc/zm_z7.py BOARD_CORE), or `standard`"
    )
    args = p.parse_args()
    (build_sim if args.target == "sim" else build_z7)(args)


if __name__ == "__main__":
    main()
