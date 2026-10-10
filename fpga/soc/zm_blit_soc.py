"""The blitter on the board SoC (docs/BLITTER_HW_SPEC.md 10): rtl/blitter's zm_blit, its
register port fed from the CPU's stores, its memory on HP2 (soc/zm_blit_hp.py).

- **The registers stay memory.** The cart writes the BLIT_* block where the machine
  has it (HW_VIDEO_BASE + OFF_BLIT, in DDR), so every load reads what the wasm
  machine would. zm_blit keeps its own copy: `ZMBlitTap` taps the CPU's data bus as
  soc/zm_video_snoop.py does (the D-cache is write-through, every store crosses it)
  and hands each store to the block to zm_blit's write port, a few clocks later.
- **COMMAND does not start anything from memory.** The machine runs an op when the
  firmware calls hwBlit(), not when COMMAND is stored, so the tap drops the COMMAND
  byte of the region's stores. The start is a store of the command byte to word 0 of
  `BLIT_WINDOW`, made by the firmware's hwBlit (cycles/bblit.c). It goes through the
  SAME tap, so it reaches zm_blit after every register store before it, in program
  order, with no fence. With the CPU's stores POSTED (soc/zm_hp_posted.py, `stores_idle`
  low while any is not yet in DDR), a start waits in the tap until they have drained, so
  an op never reads pixels still in the bridge's buffer; STATUS reads BUSY meanwhile.
- **BLIT_WINDOW is M-only**: it sits outside every seal window (rtl/seal/zm_seal_map.vh),
  so the cart reaches nothing it could not before; it can only ask through hwBlit.
  Reads: word 0 = STATUS (bit 31 BUSY, also while a store is still in the tap), word 24
  = CYCLES. The firmware copies both back to memory, where the cart reads them.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from litex.gen import LiteXModule
from litex.soc.integration.soc import SoCRegion
from litex.soc.interconnect import axi, wishbone
from migen import Cat, ClockSignal, If, Instance, Mux, ResetSignal, Signal

from gen import memmap as mm
from soc.zm_blit_hp import BlitHP

FPGA = Path(__file__).resolve().parent.parent
RTL = FPGA / "rtl/blitter"
BLIT_WINDOW = 0x91000000  # uncached (bit 31), outside the seal's video window (0x9000_0000, 8 MiB)
BLIT_WINDOW_BYTES = 0x1000
REG_W0, REG_WORDS = mm.OFF_BLIT // 4, 24  # the region words zm_blit stores (CYCLES is its own)
assert mm.OFF_BLIT % 128 == 0, "the tap takes the word index as the offset's low 5 bits"

# LiteX buses and SoCs: untyped, their signals and submodules are attributes made at runtime.
Bus = Any
SoC = Any


class ZMBlitTap(LiteXModule):
    """The CPU's stores to the BLIT_* block and to BLIT_WINDOW, as zm_blit's write port.
    `vbase`: the bus byte address of HW_VIDEO_BASE (the video's VBASE CSR); `stores_idle`:
    the CPU's acknowledged stores are all in DDR (WishboneHP.idle)."""

    def __init__(self, dbus: Bus, vbase: Signal, break_: str = "", stores_idle: Signal | int = 1) -> None:
        self.we, self.waddr, self.be, self.wdata = Signal(), Signal(5), Signal(4), Signal(32)
        self.pending = Signal()  # a store is still in the tap: it may be a start
        t_store, t_adr, t_sel, t_dat = Signal(), Signal(30), Signal(4), Signal(32)
        o_store, off, go, o_sel, o_dat = Signal(), Signal(30), Signal(), Signal(4), Signal(32)
        win = (BLIT_WINDOW_BYTES // 4).bit_length() - 1  # word-address bits inside the window
        self.sync += [  # pipelined like the video snoop: bus -> offset -> decode
            t_store.eq(dbus.cyc & dbus.stb & dbus.we & dbus.ack),
            t_adr.eq(dbus.adr), t_sel.eq(dbus.sel), t_dat.eq(dbus.dat_w),
            o_store.eq(t_store), off.eq(t_adr - vbase[2:]), o_sel.eq(t_sel), o_dat.eq(t_dat),
            go.eq((t_adr[win:] == BLIT_WINDOW >> (2 + win)) & (t_adr[:win] == 0)),
        ]  # fmt: skip
        region = (off >= REG_W0) & (off < REG_W0 + REG_WORDS)
        if break_ == "drop":  # the break test: the tap loses the stores to D_STRIDE (word 9)
            region = region & (off != REG_W0 + 9)
        word0 = off[:5] == 0
        held, h_sel, h_dat = Signal(), Signal(4), Signal(32)  # a start waiting for the stores to drain
        start = o_store & go
        fire = held & stores_idle  # nothing reaches the tap while a start is held: hwBlit spins on BUSY
        self.sync += [
            self.we.eq((o_store & region) | (start & stores_idle) | fire),
            self.waddr.eq(Mux(go | fire, 0, off[:5])),
            # A start writes COMMAND only; a region store never writes it.
            self.be.eq(Mux(fire, h_sel & 0b0001, Mux(go, o_sel & 0b0001, Mux(word0, o_sel & 0b1110, o_sel)))),
            self.wdata.eq(Mux(fire, h_dat, o_dat)),
            If(start & ~stores_idle, held.eq(1), h_sel.eq(o_sel), h_dat.eq(o_dat)),
            If(fire, held.eq(0)),
        ]  # fmt: skip
        self.comb += self.pending.eq(t_store | o_store | self.we | held)


class ZMBlit(LiteXModule):
    """zm_blit, its tap, BLIT_WINDOW (`bus`, a Wishbone slave) and its HP2 bridge."""

    def __init__(self, platform: object, dbus: Bus, vbase: Signal, hp: axi.AXIInterface, **kw: Any) -> None:
        enable, break_ = kw.get("enable"), kw.get("break_", "")
        self.bus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.tap = ZMBlitTap(dbus, vbase, break_, kw.get("stores_idle", 1))
        base = Signal(32)  # the bus address of linear 0: VBASE less HW_VIDEO_BASE, registered
        skew = 8 if break_ == "base" else 0  # the break test: the DDR map off by one beat
        self.sync += base.eq(vbase - mm.HW_VIDEO_BASE + skew)
        self.mem = mem = BlitHP(hp, base, enable)
        raddr, rdata, busy = Signal(5), Signal(32), Signal()
        self.specials += Instance(
            "zm_blit", i_clk=ClockSignal("sys"), i_rst=ResetSignal("sys"),
            i_cpu_we=self.tap.we, i_cpu_waddr=self.tap.waddr, i_cpu_be=self.tap.be, i_cpu_wdata=self.tap.wdata,
            i_cpu_raddr=raddr, o_cpu_rdata=rdata, o_busy=busy,
            o_rd_req_valid=mem.rd_req_valid, i_rd_req_ready=mem.rd_req_ready, o_rd_req_addr=mem.rd_req_addr,
            i_rd_rsp_valid=mem.rd_rsp_valid, i_rd_rsp_data=mem.rd_rsp_data,
            o_wr_req_valid=mem.wr_req_valid, i_wr_req_ready=mem.wr_req_ready, o_wr_req_addr=mem.wr_req_addr,
            o_wr_req_data=mem.wr_req_data, o_wr_req_strb=mem.wr_req_strb, i_wr_pending=mem.wr_pending,
        )  # fmt: skip
        self.busy = busy
        self._window(raddr, rdata)
        _add_sources(platform)

    def _window(self, raddr: Signal, rdata: Signal) -> None:
        """BLIT_WINDOW: writes are acked (the tap takes them); reads are STATUS and CYCLES."""
        bus = self.bus
        busy = self.busy | self.tap.pending
        self.comb += raddr.eq(bus.adr[:5])
        self.sync += [
            bus.ack.eq(bus.cyc & bus.stb & ~bus.ack),
            bus.dat_r.eq(rdata | Cat(Signal(31), busy & (raddr == 0))),
        ]


def _add_sources(platform: Any) -> None:  # Any: an untyped LiteX platform
    """rtl/blitter, FIRST in the source list. Its files include memmap.vh at file scope (one
    declaration for every blitter module, behind the include guard), where the video RTL
    `undef`s the guard and includes it inside each module; read after a video module, the
    guard would already be set and the blitter would see no ZM_* constant (Verilator, Yosys)."""
    n = len(platform.sources)
    for src in sorted(RTL.glob("zm_blit*.v")):
        platform.add_source(str(src))
    platform.sources[:] = platform.sources[n:] + platform.sources[:n]
    platform.add_verilog_include_path(str(FPGA / "gen"))
    platform.add_verilog_include_path(str(RTL))


def add_blitter(soc: SoC, platform: object, hp: axi.AXIInterface, break_: str = "") -> None:
    """The blitter on `hp` (HP2), its window on the bus; the video pipe must exist (its VBASE)."""
    enable = soc.glass.cpu_run if hasattr(soc, "glass") else None
    idle = getattr(soc, "stores_idle", 1)  # zm_board_mem.add_cpu_memory's: the bridge's posted stores
    soc.zm_blit = ZMBlit(platform, soc.cpu.dbus, soc.video.vbase.storage, hp, enable=enable, break_=break_,
                         stores_idle=idle)  # fmt: skip
    region = SoCRegion(origin=BLIT_WINDOW, size=BLIT_WINDOW_BYTES, cached=False)
    soc.bus.add_slave("zm_blit", soc.zm_blit.bus, region)
