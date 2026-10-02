"""The ZigMachine video timing (rtl/video/zm_vtiming.v) as a LiteX peripheral.

What a cart CPU needs from it, today: the HBL and VBL strobes as INTERRUPTS
(an HBL handler is an interrupt handler here, not a host callback), the line the
HBL announces, and a frame counter (memmap REG_FRAME). The pixel pipeline (plane
fetch, palettes, compositor) attaches to the same timing later.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect.csr import CSRStatus
from litex.soc.interconnect.csr_eventmanager import EventManager, EventSourcePulse
from migen import ClockSignal, If, Instance, ResetSignal, Signal

FPGA = Path(__file__).resolve().parent.parent

# LiteX platforms are untyped Python classes with no common base worth naming.
Platform = Any


class ZMVideoTiming(LiteXModule):
    """Instantiates zm_vtiming in clock domain `cd` and exposes its strobes."""

    def __init__(self, platform: Platform, cd: str = "sys") -> None:
        self.hsync = Signal()
        self.vsync = Signal()
        self.de = Signal()
        self.zm_active = Signal()
        self.zm_x = Signal(10)
        self.zm_line = Signal(9)
        hbl, vbl = Signal(), Signal()
        hbl_line = Signal(9)

        self.specials += Instance(
            "zm_vtiming",
            i_clk=ClockSignal(cd),
            i_rst=ResetSignal(cd),
            o_hsync=self.hsync,
            o_vsync=self.vsync,
            o_de=self.de,
            o_out_x=Signal(11),
            o_out_y=Signal(10),
            o_zm_active=self.zm_active,
            o_zm_x=self.zm_x,
            o_zm_line=self.zm_line,
            o_zm_hbl=hbl,
            o_zm_hbl_line=hbl_line,
            o_zm_vbl=vbl,
        )
        platform.add_source(str(FPGA / "rtl/video/zm_vtiming.v"))
        platform.add_verilog_include_path(str(FPGA / "gen"))  # memmap.vh

        self.hbl_line = CSRStatus(9, description="The raster line the last HBL announced.")
        self.frame = CSRStatus(32, description="Frames since reset (memmap REG_FRAME).")
        self.ev = EventManager()
        self.ev.hbl = EventSourcePulse(description="HBL: a raster line is about to be drawn.")
        self.ev.vbl = EventSourcePulse(description="VBL: the raster is complete.")
        self.ev.finalize()

        frame = Signal(32)
        self.sync += [
            If(hbl, self.hbl_line.status.eq(hbl_line)),
            If(vbl, frame.eq(frame + 1)),
        ]
        self.comb += [
            self.frame.status.eq(frame),
            self.ev.hbl.trigger.eq(hbl),
            self.ev.vbl.trigger.eq(vbl),
        ]
