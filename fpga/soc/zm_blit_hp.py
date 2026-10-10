"""The blitter's memory master on HP2 (docs/BLITTER_HW_SPEC.md 10.2-10.3): rtl/blitter's
byte-wide read and write ports -> one 64-bit AXI3 HP port, the way soc/zm_hp.py's
WishboneHP drives HP0.

- **Addresses.** zm_blit speaks the machine's linear byte addresses. `base` is the
  cart CPU's bus address of linear 0 (the SoC derives it from the video's `vbase`), and
  the bus address maps to DDR exactly as the CPU path maps it: its low 25 bits inside
  the 32 MiB window at DDR_BASE (soc/zm_hp.py ddr_addr). Nothing outside that window
  is reachable, whatever the registers say (rtl/seal/README.md "Bound the HP path").
- **Reads**: one 1-beat 64-bit burst per request, up to READS in flight (one AXI ID,
  so they come back in order); the 32-bit half the byte lives in goes back a clock
  after the beat.
- **Writes (WR32)**: one 1-beat 4-byte write per request on WDATA[31:0] / WSTRB[3:0],
  AWCACHE 0, as the board's 32-bit write channel needs. `wr_pending` stays high until
  every taken write has its B response, so zm_blit's BUSY covers "the pixels are in DDR".
- **Ordering**: AXI orders neither a read behind a write nor a write behind a read.
  zm_blit's contract is "a read issued after a write sees it", so a read waits for
  every B, and a write waits for every read's data.
- `enable` (glass CTRL.RUN): no new request is taken while it is low, so a blit cut by
  the ARM stopping the cart finishes its transactions instead of tearing an HP burst.
"""

from __future__ import annotations

from litex.gen import LiteXModule
from litex.soc.interconnect import axi
from migen import Cat, If, Mux, Signal
from migen import Constant as Const

from soc.zm_hp import AW_CACHE, DDR_BASE, SIZE_4, WINDOW_LOG2, fixed_fields

READS = 4  # reads in flight: the pixel unit asks for A, B and C back to back
WRITES = 8  # writes without their B response yet


def ddr_byte(bus: Signal) -> Cat:
    """The DDR byte address of cart-CPU bus address `bus`: its 32 MiB window offset at DDR_BASE."""
    return Cat(bus[:WINDOW_LOG2], Const(DDR_BASE >> WINDOW_LOG2, 32 - WINDOW_LOG2))


class BlitHP(LiteXModule):
    def __init__(self, hp: axi.AXIInterface, base: Signal, enable: Signal | None = None) -> None:
        self.hp, self.base = hp, base
        self.enable = Signal(reset=1) if enable is None else enable
        self.rd_req_valid, self.rd_req_ready, self.rd_req_addr = Signal(), Signal(), Signal(32)
        self.rd_rsp_valid, self.rd_rsp_data = Signal(), Signal(32)
        self.wr_req_valid, self.wr_req_ready, self.wr_req_addr = Signal(), Signal(), Signal(32)
        self.wr_req_data, self.wr_req_strb, self.wr_pending = Signal(32), Signal(4), Signal()
        self.reads = Signal(max=READS + 1)  # ARs taken whose beat has not come back
        self.writes = Signal(max=WRITES + 1)  # AWs taken whose B has not come back
        self.comb += [*fixed_fields(hp.ar), *fixed_fields(hp.aw), hp.r.ready.eq(1), hp.b.ready.eq(1)]
        self._read()
        self._write()

    def _read(self) -> None:
        hp, lanes = self.hp, Signal(READS)  # lanes[i]: the i-th read in flight wants the upper half
        take = self.rd_req_valid & self.rd_req_ready
        back = hp.r.valid & hp.r.ready
        bus = Signal(32)
        self.comb += [
            bus.eq(self.base + self.rd_req_addr),
            self.rd_req_ready.eq(self.enable & ~hp.ar.valid & (self.reads < READS) & (self.writes == 0)
                                 & ~hp.aw.valid & ~hp.w.valid),
        ]  # fmt: skip
        kept = Mux(back, lanes >> 1, lanes)
        self.sync += [
            If(take,
               hp.ar.valid.eq(1), hp.ar.addr.eq(Cat(Const(0, 3), ddr_byte(bus)[3:])), hp.ar.len.eq(0),
               lanes.eq(kept | (bus[2] << (self.reads - back)))).Else(lanes.eq(kept)),
            If(hp.ar.valid & hp.ar.ready, hp.ar.valid.eq(0)),
            self.reads.eq(self.reads + take - back),
            self.rd_rsp_valid.eq(back),
            If(back, self.rd_rsp_data.eq(Mux(lanes[0], hp.r.data[32:], hp.r.data[:32]))),
        ]  # fmt: skip

    def _write(self) -> None:
        hp = self.hp
        take = self.wr_req_valid & self.wr_req_ready
        done = hp.b.valid & hp.b.ready
        bus = Signal(32)
        self.comb += [
            bus.eq(self.base + self.wr_req_addr),
            self.wr_req_ready.eq(self.enable & ~hp.aw.valid & ~hp.w.valid & (self.writes < WRITES)
                                 & (self.reads == 0) & ~hp.ar.valid),
            # WR32: 4-byte beats on WDATA[31:0], AWCACHE[1] clear so the AFI never upsizes.
            hp.aw.size.eq(SIZE_4), hp.aw.cache.eq(AW_CACHE), hp.w.last.eq(1), hp.w.id.eq(0),
            self.wr_pending.eq(self.writes != 0),
        ]  # fmt: skip
        self.sync += [
            If(take,
               hp.aw.valid.eq(1), hp.aw.addr.eq(Cat(Const(0, 2), ddr_byte(bus)[2:])), hp.aw.len.eq(0),
               hp.w.valid.eq(1), hp.w.data.eq(Cat(self.wr_req_data, self.wr_req_data)),
               hp.w.strb.eq(self.wr_req_strb)),
            If(hp.aw.valid & hp.aw.ready, hp.aw.valid.eq(0)),
            If(hp.w.valid & hp.w.ready, hp.w.valid.eq(0)),
            self.writes.eq(self.writes + take - done),
        ]  # fmt: skip
