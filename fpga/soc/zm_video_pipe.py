"""The whole video pipeline (rtl/video/zm_video_out.v, + zm_dvi_out.v on the board)
as a LiteX peripheral: compositor, double-buffered picture, scanout, timing, DVI.

The video architecture (decisions.md, 2026-10-02): every frame is composited
into a picture in memory, in the machine's own order and at the compositor's
speed, and the scanout shows the previous, completed picture. Around the RTL:

- **The sequencer is the cart CPU's firmware** (fpga/cycles/vseq.c): it writes
  pass commands to `cmd` and calls the HBL handlers between passes as plain
  calls. `status` says when a pass has read the CPU's state (`painted`), when
  the CPU's stores have all reached the compositor (`drained`), and when the
  next command may be written (`ready`).
- **The snoop** (`snoop_*`, from soc/zm_video_snoop.py, wired by the SoC):
  the cart's ordinary stores to its video region, the compositor's only input
  from the CPU. `bus` is a read-only window onto the compositor's register
  block, for the sequencer to copy its write-backs into memory.
- **A memory master** (`dma`, 64-bit Wishbone, soc/zm_video_dma.py): plane
  fetches, PFB and picture rows, and the scanout's reads, in bursts. `vbase`
  is the bus address of HW_VIDEO_BASE, `fb0`/`fb1` the two pictures'.
The compositor (and the scanout fetch) runs in `cd_comp`, its own clock, and
everything between it and the SoC crosses in soc/zm_video_cdc.py; the timing
and scanout run in `cd_pix`, the serialisers in `cd_pix5x`. Without `pads` (the
sims) there is no DVI and the picture is `self.pic`.
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect import wishbone
from litex.soc.interconnect.csr_eventmanager import EventManager, EventSourcePulse
from migen import ClockSignal, If, Instance, ResetSignal, Signal

from soc.zm_video_cdc import ReadPortCross, WritePortCross, ZMVideoCDC
from soc.zm_video_csr import ZMVideoCSRs
from soc.zm_video_dma import ZMVideoDMA, read_port, write_port

FPGA = Path(__file__).resolve().parent.parent
RTL = FPGA / "rtl" / "video"
# Every RTL file but the testbench-only ones; the top picks what it uses.
SOURCES = sorted(p for p in RTL.glob("zm_*.v"))
WINDOW_BYTES = 1 << 7  # the register block: 32 words
# LiteX platforms are untyped Python classes with no common base worth naming.
Platform = Any
Picture = dict[str, Signal]
Overlay = Callable[[LiteXModule, Picture], Picture] | None


class ZMVideo(ZMVideoCSRs, LiteXModule):
    """zm_video_out (+ zm_dvi_out), with the sequencer's CSRs, the snoop port and the DMA."""

    def __init__(
        self,
        platform: Platform,
        pads: dict[str, Signal] | None,
        cd_pix: str = "pix",
        cd_pix5x: str = "pix5x",
        cd_comp: str = "comp",
        overlay: Overlay = None,
        max_burst: int = 16,
    ) -> None:
        self.bus = wishbone.Interface(data_width=32)
        self.drained = Signal()  # the SoC: no CPU store is still on its way to the snoop
        self._csrs()
        p = self._ports()
        self.cdc = x = ZMVideoCDC(p, cd_comp)
        x.window(self.bus, p, cd_comp)
        # The snoop's port (soc/zm_video_snoop.py attach_snoop): stores with their {beam, pal,
        # reg} selects decoded; `snoop_room` holds the delivery back while the crossing is full.
        self.snoop, self.snoop_room, snoop_empty = x.snoop(cd_comp)
        self._command(x, snoop_empty)
        self._memory(cd_comp, max_burst)
        self._events(x)
        self._rtl(platform, p, pads, overlay, (cd_pix, cd_pix5x, cd_comp))

    def _rtl(
        self, platform: Platform, p: Picture, pads: Picture | None, overlay: Overlay, cds: tuple[str, ...]
    ) -> None:
        cd_pix, cd_pix5x, cd_comp = cds
        self.specials += Instance("zm_video_out", **self._out_ports(p, cd_pix, cd_comp))
        # GLASS HOOK (docs/FPGA_GLASS.md): the OSD sits on the finished picture,
        # between the scanout and DVI, so it never touches the machine's pixels.
        self.pic = {k: p[k] for k in ("r", "g", "b", "de", "hsync", "vsync")}
        if overlay is not None:
            self.pic = overlay(self, self.pic)
        if pads is not None:
            self._dvi(pads, cd_pix, cd_pix5x)
        for src in SOURCES:
            platform.add_source(str(src))
        platform.add_verilog_include_path(str(FPGA / "gen"))
        platform.add_verilog_include_path(str(RTL))

    def _dvi(self, pads: dict[str, Signal], cd_pix: str, cd_pix5x: str) -> None:
        pic = self.pic
        self.specials += Instance(
            "zm_dvi_out",
            i_pix_clk=ClockSignal(cd_pix),
            i_pix5x_clk=ClockSignal(cd_pix5x),
            i_rst=ResetSignal(cd_pix),
            i_r=pic["r"], i_g=pic["g"], i_b=pic["b"], i_de=pic["de"], i_hsync=pic["hsync"], i_vsync=pic["vsync"],
            o_tmds_p=pads["p"], o_tmds_n=pads["n"],
        )  # fmt: skip

    def _ports(self) -> dict[str, Signal]:
        widths = {
            "cpu_rword": 5, "cpu_rdata": 32, "cmd_valid": 1, "cmd_ready": 1, "painted": 1, "pass_done": 1,
            "overflow": 1, "underrun": 1, "vbl": 1, "front": 1, "pending": 1, "swaps": 32,
            "r": 8, "g": 8, "b": 8, "de": 1, "hsync": 1, "vsync": 1,
        }  # fmt: skip
        return {name: Signal(w, name=f"zmv_{name}") for name, w in widths.items()}

    def _command(self, x: ZMVideoCDC, snoop_empty: Signal) -> None:
        f = self.status.fields
        self.comb += [
            x.cmd_re.eq(self.cmd.re),
            f.ready.eq(x.ready),
            f.painted.eq(x.painted),
            f.drained.eq(self.drained & snoop_empty),
            f.pending.eq(x.pending),
            f.front.eq(x.front),
            f.underrun.eq(x.underrun),
            f.overflow.eq(x.overflow),
            self.comp_busy.status.eq(x.comp_busy),
        ]

    def _memory(self, cd_comp: str, max_burst: int) -> None:
        """The DMA in sys; the RTL's ports (`*_c`, in cd_comp) cross onto its ports."""
        self.rd, self.wr, self.sc = read_port("zmv_rd"), write_port("zmv_wr"), read_port("zmv_sc")
        self.rd_c, self.wr_c, self.sc_c = read_port("zmv_rd_c"), write_port("zmv_wr_c"), read_port("zmv_sc_c")
        self.rd_x = ReadPortCross(self.rd_c, self.rd, cd_comp)
        self.sc_x = ReadPortCross(self.sc_c, self.sc, cd_comp)
        self.wr_x = WritePortCross(self.wr_c, self.wr, cd_comp)
        self.dma_ctl = ZMVideoDMA([self.sc, self.rd], self.wr, max_burst)
        self.dma = self.dma_ctl.bus
        busy = Signal(32)
        self.sync += If(self.dma_ctl.active, busy.eq(busy + 1))
        self.comb += self.dma_busy.status.eq(busy)

    def _events(self, x: ZMVideoCDC) -> None:
        self.ev = EventManager()
        self.ev.vbl = EventSourcePulse(description="VBL: the raster is complete.")
        self.ev.pass_done = EventSourcePulse(description="A pass's rows are in memory.")
        self.ev.finalize()
        frame = Signal(32)
        self.sync += If(x.vbl, frame.eq(frame + 1))
        self.comb += [
            self.frame.status.eq(frame),
            self.swaps.status.eq(x.swaps),
            self.ev.vbl.trigger.eq(x.vbl),
            self.ev.pass_done.trigger.eq(x.pass_done),
        ]

    def _out_ports(self, p: dict[str, Signal], cd_pix: str, cd_comp: str) -> dict[str, object]:
        f, sn = self.cmd.fields, self.cdc.snoop_out
        ports: dict[str, object] = {
            "i_clk": ClockSignal(cd_comp), "i_rst": ResetSignal(cd_comp),
            "i_pix_clk": ClockSignal(cd_pix), "i_pix_rst": ResetSignal(cd_pix),
            "i_vbase": self.vbase.storage, "i_fb0_base": self.fb0.storage, "i_fb1_base": self.fb1.storage,
            "i_cpu_we": sn["we"], "i_cpu_waddr": sn["waddr"], "i_cpu_be": sn["be"], "i_cpu_wdata": sn["wdata"],
            "i_cpu_sel": sn["sel"], "i_cmd_op": f.op, "i_cmd_plane": f.plane, "i_cmd_line": f.line,
            "i_cmd_mix": f.mix, "i_cmd_first": f.first,
        }  # fmt: skip
        for prefix, port in (("rd", self.rd_c), ("sc", self.sc_c)):
            ports |= {f"o_{prefix}_req_valid": port.req_valid, f"i_{prefix}_req_ready": port.req_ready}
            ports |= {f"o_{prefix}_req_addr": port.req_addr, f"o_{prefix}_req_len": port.req_len}
            ports |= {f"i_{prefix}_rsp_valid": port.rsp_valid, f"i_{prefix}_rsp_data": port.rsp_data}
        w = self.wr_c
        ports |= {"o_wr_req_valid": w.req_valid, "i_wr_req_ready": w.req_ready, "o_wr_req_addr": w.req_addr}
        ports |= {"o_wr_req_len": w.req_len, "o_wr_dat_valid": w.dat_valid, "i_wr_dat_ready": w.dat_ready}
        ports |= {"o_wr_dat": w.dat, "i_wr_busy": w.busy}
        inputs = {"cpu_rword", "cmd_valid"}
        for name, sig in p.items():
            ports[("i_" if name in inputs else "o_") + name] = sig
        return ports
