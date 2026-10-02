"""The whole video pipeline (rtl/video/zm_video_out.v + zm_dvi_out.v) as a LiteX
peripheral, for the board: compositor, plane mixer, scanout, timing, DVI.

What it gives the cart CPU:
- **A bus window** (`bus`, Wishbone slave) onto the compositor's CPU port: the
  video registers, the 4 palettes and the BEAM table at their memmap offsets
  (region offset = window offset). Stores land; loads read the register block.
- **Pass commands** through CSRs (`cmd`, `status`): the HBL sequencer is
  software for now. A write to `cmd` queues one command; `status.ready` says the
  compositor can take another.
- **Interrupts**: HBL (a raster line is about to be shown, `hbl_line`), VBL, and
  pass done. The HBL/VBL strobes come from the pixel clock's domain, synchronised.
- **A memory master** (`dma`, Wishbone): the compositor's line fetches, at
  `mem_base` + the region offset it asks for. One word at a time for now; the
  port is shaped for an AXI HP master to DDR (rtl/video/README.md).
The compositor runs in `cd` (sys), the timing and scanout in `cd_pix`, the
serialisers in `cd_pix5x`.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect import wishbone
from litex.soc.interconnect.csr import CSRField, CSRStatus, CSRStorage
from litex.soc.interconnect.csr_eventmanager import EventManager, EventSourcePulse
from migen import ClockSignal, If, Instance, ResetSignal, Signal

FPGA = Path(__file__).resolve().parent.parent
RTL = FPGA / "rtl" / "video"
# Every RTL file but the testbench-only ones; the top picks what it uses.
SOURCES = sorted(p for p in RTL.glob("zm_*.v"))
WINDOW_BYTES = 1 << 23  # cpu_waddr is 21 bits of words

# LiteX platforms are untyped Python classes with no common base worth naming.
Platform = Any


class ZMVideo(LiteXModule):
    """zm_video_out + zm_dvi_out, with the CPU's bus window, CSRs, IRQs and DMA."""

    def __init__(
        self, platform: Platform, pads: dict[str, Signal], cd_pix: str = "pix", cd_pix5x: str = "pix5x"
    ) -> None:
        self.bus = wishbone.Interface(data_width=32)
        self.dma = wishbone.Interface(data_width=32)
        self._csrs()
        p = self._ports()
        self._cpu_window(p)
        self._command(p)
        self._fetch(p)
        self._events(p)
        self.specials += Instance("zm_video_out", **self._out_ports(p, cd_pix))
        self.specials += Instance(
            "zm_dvi_out",
            i_pix_clk=ClockSignal(cd_pix),
            i_pix5x_clk=ClockSignal(cd_pix5x),
            i_rst=ResetSignal(cd_pix),
            i_r=p["r"], i_g=p["g"], i_b=p["b"], i_de=p["de"], i_hsync=p["hsync"], i_vsync=p["vsync"],
            o_tmds_p=pads["p"], o_tmds_n=pads["n"],
        )  # fmt: skip
        for src in SOURCES:
            platform.add_source(str(src))
        platform.add_verilog_include_path(str(FPGA / "gen"))
        platform.add_verilog_include_path(str(RTL))

    def _csrs(self) -> None:
        self.cmd = CSRStorage(
            fields=[
                CSRField("op", size=2, description="0 BG, 1 PLANE, 2 LATCH"),
                CSRField("plane", size=2),
                CSRField("line", size=9),
                CSRField("mix", size=1, description="fold this pass into the picture"),
                CSRField("last", size=1, description="the line's last pass"),
            ],
            description="Writing queues one pass command (rtl/video/zm_video_comp.v).",
        )
        self.status = CSRStatus(
            fields=[
                CSRField("ready", size=1, description="a command may be written"),
                CSRField("mix_busy", size=1),
                CSRField("overflow", size=1),
                CSRField("hazard", size=1),
                CSRField("underrun", size=1, description="the scanout showed a line not ready"),
            ]
        )
        self.mem_base = CSRStorage(32, description="Bus address of region offset 0 (HW_VIDEO_BASE).")
        self.hbl_line = CSRStatus(9, description="The raster line the last HBL announced.")
        self.frame = CSRStatus(32, description="VBLs since reset.")

    def _ports(self) -> dict[str, Signal]:
        widths = {
            "cpu_we": 1, "cpu_waddr": 21, "cpu_be": 4, "cpu_wdata": 32, "cpu_rword": 5, "cpu_rdata": 32,
            "cmd_valid": 1, "cmd_ready": 1, "pass_done": 1, "mem_req_valid": 1, "mem_req_ready": 1,
            "mem_req_addr": 32, "mem_rsp_valid": 1, "mem_rsp_data": 32, "overflow": 1, "mix_busy": 1,
            "mix_hazard": 1, "underrun": 1, "hbl": 1, "hbl_line": 9, "vbl": 1,
            "r": 8, "g": 8, "b": 8, "de": 1, "hsync": 1, "vsync": 1,
        }  # fmt: skip
        return {name: Signal(w, name=f"zmv_{name}") for name, w in widths.items()}

    def _cpu_window(self, p: dict[str, Signal]) -> None:
        """Wishbone slave -> the CPU port: one-clock writes, combinational register reads."""
        bus, ack = self.bus, Signal()
        self.comb += [
            p["cpu_we"].eq(bus.cyc & bus.stb & bus.we & ~ack),
            p["cpu_waddr"].eq(bus.adr[:21]),
            p["cpu_be"].eq(bus.sel),
            p["cpu_wdata"].eq(bus.dat_w),
            p["cpu_rword"].eq(bus.adr[:5]),
            bus.ack.eq(ack),
        ]
        self.sync += [ack.eq(bus.cyc & bus.stb & ~ack), bus.dat_r.eq(p["cpu_rdata"])]

    def _command(self, p: dict[str, Signal]) -> None:
        valid = Signal()
        self.sync += If(self.cmd.re, valid.eq(1)).Elif(p["cmd_ready"], valid.eq(0))
        self.comb += [
            p["cmd_valid"].eq(valid),
            self.status.fields.ready.eq(~valid & p["cmd_ready"]),
            self.status.fields.mix_busy.eq(p["mix_busy"]),
            self.status.fields.overflow.eq(p["overflow"]),
            self.status.fields.hazard.eq(p["mix_hazard"]),
            self.status.fields.underrun.eq(p["underrun"]),
        ]

    def _fetch(self, p: dict[str, Signal]) -> None:
        """The compositor's read port over Wishbone, one request in flight."""
        dma, busy = self.dma, Signal()
        self.comb += [
            p["mem_req_ready"].eq(~busy),
            dma.cyc.eq(busy),
            dma.stb.eq(busy),
            dma.we.eq(0),
            dma.sel.eq(0xF),
            p["mem_rsp_valid"].eq(busy & dma.ack),
            p["mem_rsp_data"].eq(dma.dat_r),
        ]
        self.sync += [
            If(p["mem_req_valid"] & ~busy, busy.eq(1), dma.adr.eq((self.mem_base.storage + p["mem_req_addr"])[2:])),
            If(busy & dma.ack, busy.eq(0)),
        ]

    def _events(self, p: dict[str, Signal]) -> None:
        self.ev = EventManager()
        self.ev.hbl = EventSourcePulse(description="HBL: a raster line is about to be shown.")
        self.ev.vbl = EventSourcePulse(description="VBL: the raster is complete.")
        self.ev.pass_done = EventSourcePulse(description="A BG or PLANE pass has finished.")
        self.ev.finalize()
        frame = Signal(32)
        self.sync += If(p["vbl"], frame.eq(frame + 1))
        self.comb += [
            self.hbl_line.status.eq(p["hbl_line"]),
            self.frame.status.eq(frame),
            self.ev.hbl.trigger.eq(p["hbl"]),
            self.ev.vbl.trigger.eq(p["vbl"]),
            self.ev.pass_done.trigger.eq(p["pass_done"]),
        ]

    def _out_ports(self, p: dict[str, Signal], cd_pix: str) -> dict[str, object]:
        f = self.cmd.fields
        ports: dict[str, object] = {
            "i_clk": ClockSignal("sys"), "i_rst": ResetSignal("sys"),
            "i_pix_clk": ClockSignal(cd_pix), "i_pix_rst": ResetSignal(cd_pix),
            "i_cmd_op": f.op, "i_cmd_plane": f.plane, "i_cmd_line": f.line, "i_cmd_mix": f.mix, "i_cmd_last": f.last,
            "i_lb_raddr": 0, "o_lb_rdata": Signal(64), "o_line_ready": Signal(), "o_ready_line": Signal(9),
        }  # fmt: skip
        inputs = {"cpu_we", "cpu_waddr", "cpu_be", "cpu_wdata", "cpu_rword", "cmd_valid", "mem_req_ready"}
        inputs |= {"mem_rsp_valid", "mem_rsp_data"}
        for name, sig in p.items():
            ports[("i_" if name in inputs else "o_") + name] = sig
        return ports
