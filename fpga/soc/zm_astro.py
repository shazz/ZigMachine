"""ASTROLABE's mailbox (SPIKE, docs/ARM_FPU_COPROC.md): rtl/glass/zm_astro_mbox.v on the SoC.

One 4 KiB block RAM with two ports: ZIGGY's, a Wishbone slave at ASTRO_WINDOW (uncached, so a
store to it is held until ZIGGY's posted DDR stores have drained: soc/zm_io_fence.py, which
is what lets the ARM read a cart's arrays in DDR once SEQ is rung); and the ARM's, behind the
glass block on M_AXI_GP0 at glass/src/map.zig OFF_ASTRO (zm_glass_regs.v forwards the page).

The firmware (cycles/bastro.c) uses the window only when the video STATUS reads ASTRO = 1,
which add_astro sets: a bitstream without the mailbox reads 0 and the window is never touched.
No register logic, no DSP: the RAM, its ack, the decoder's slot.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from litex.gen import LiteXModule
from litex.soc.integration.soc import SoCRegion
from litex.soc.interconnect import wishbone
from migen import ClockSignal, Instance, ResetSignal

FPGA = Path(__file__).resolve().parent.parent
ASTRO_WINDOW = 0x94000000  # uncached (bit 31), next to SOUND_WINDOW 0x9300_0000, outside the seal's windows
ASTRO_WINDOW_BYTES = 0x1000
WORD_BITS = 10  # 1024 words

# LiteX platforms and SoCs are untyped Python classes.
Platform = Any
SoC = Any


class ZMAstro(LiteXModule):
    """`bus`: ZIGGY's port; `arm`: the glass's mailbox signals (soc/zm_glass.py ZMGlass.astro)."""

    def __init__(self, platform: Platform, arm: dict[str, Any]) -> None:
        self.bus = bus = wishbone.Interface(data_width=32, adr_width=30)
        self.specials += Instance(
            "zm_astro_mbox",
            p_AW=WORD_BITS,
            i_clk=ClockSignal("sys"), i_rst=ResetSignal("sys"),
            i_wb_cyc=bus.cyc, i_wb_stb=bus.stb, i_wb_we=bus.we, i_wb_adr=bus.adr[:WORD_BITS],
            i_wb_dat_w=bus.dat_w, i_wb_sel=bus.sel, o_wb_ack=bus.ack, o_wb_dat_r=bus.dat_r,
            i_arm_we=arm["we"], i_arm_waddr=arm["waddr"], i_arm_wdata=arm["wdata"], i_arm_wstrb=arm["wstrb"],
            i_arm_re=arm["re"], i_arm_raddr=arm["raddr"], o_arm_rdata=arm["rdata"],
        )  # fmt: skip
        platform.add_source(str(FPGA / "rtl/glass/zm_astro_mbox.v"))


def add_astro(soc: SoC, platform: Platform) -> None:
    """The mailbox between the glass's GP0 page and ZIGGY's ASTRO_WINDOW; STATUS.ASTRO = 1."""
    soc.zm_astro = ZMAstro(platform, soc.glass.astro)
    region = SoCRegion(origin=ASTRO_WINDOW, size=ASTRO_WINDOW_BYTES, cached=False)
    soc.bus.add_slave("zm_astro", soc.zm_astro.bus, region)
    soc.comb += soc.video.astro_cap.eq(1)
