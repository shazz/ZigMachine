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
  after the beat. A request waits in a small queue (RQ) until it may leave.
- **Writes (WR32)**: one 1-beat 4-byte write per request on WDATA[31:0] / WSTRB[3:0]
  (the strobes zm_blit asks for, one or several bytes of the word), AWCACHE 0, as the
  board's 32-bit write channel needs; back to back, up to WRITES without their B.
  `wr_pending` stays high until every taken write has its B response, so zm_blit's
  BUSY covers "the pixels are in DDR".
- **Ordering** (zm_blit's port contract: port order, a read and a write taken in the same
  clock count as the read first). AXI orders neither a read behind a write nor a write
  behind a read, so:
  - a read whose byte a write taken before it still covers (taken, no B yet) waits for
    that B; any other read goes at once, past every write in flight;
  - a write never waits for reads: zm_blit never asks for a write while an earlier read of
    one of its bytes is unanswered (zm_blit_px: a pixel is written after its own reads and
    every earlier pixel's have come back), and tests/tb/blitter_tb.cpp holds it to that.
- `enable` (glass CTRL.RUN): no new request is taken while it is low, so a blit cut by
  the ARM stopping the cart finishes its transactions instead of tearing an HP burst.
- `break_` (tests/test_blit_soc.py only): "alias" lets a read pass the write it must
  wait for, "order" pairs a beat with the newest read's half instead of the oldest's.
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect import axi
from migen import Array, Cat, If, Memory, Mux, Signal
from migen import Constant as Const

from soc.zm_hp import AW_CACHE, DDR_BASE, SIZE_4, WINDOW_LOG2, fixed_fields

READS = 16  # reads in flight on the port (AR sent, beat not back); the AFI takes 8, the rest wait at AR
RQ = 4  # read requests taken, not yet sent
WRITES = 8  # writes taken without their B response yet (the HP port accepts 8 write commands)


def ddr_byte(bus: Signal) -> Cat:
    """The DDR byte address of cart-CPU bus address `bus`: its 32 MiB window offset at DDR_BASE."""
    return Cat(bus[:WINDOW_LOG2], Const(DDR_BASE >> WINDOW_LOG2, 32 - WINDOW_LOG2))


def _step(p: Signal, depth: int) -> Any:  # Any: a Migen expression
    return Mux(p == depth - 1, 0, p + 1)


class BlitHP(LiteXModule):
    def __init__(self, hp: axi.AXIInterface, base: Signal, enable: Signal | None = None, break_: str = "") -> None:
        self.hp, self.base, self.break_ = hp, base, break_
        self.enable = Signal(reset=1) if enable is None else enable
        self.rd_req_valid, self.rd_req_ready, self.rd_req_addr = Signal(), Signal(), Signal(32)
        self.rd_rsp_valid, self.rd_rsp_data = Signal(), Signal(32)
        self.wr_req_valid, self.wr_req_ready, self.wr_req_addr = Signal(), Signal(), Signal(32)
        self.wr_req_data, self.wr_req_strb, self.wr_pending = Signal(32), Signal(4), Signal()
        self.reads = Signal(max=RQ + READS + 1)  # reads taken whose data has not come back
        self.writes = Signal(max=WRITES + 1)  # writes taken whose B has not come back
        self.comb += [*fixed_fields(hp.ar), *fixed_fields(hp.aw), hp.r.ready.eq(1), hp.b.ready.eq(1)]
        self.w_word, self.w_strb, self.w_live = self._write()
        self._read()

    def _ring(self, width: int, depth: int) -> tuple[Any, Any]:
        """A LUTRAM ring: a write port and a combinational read port (soc/zm_hp_posted.py's note)."""
        mem = Memory(width, depth)
        wr, rd = mem.get_port(write_capable=True), mem.get_port(async_read=True)
        self.specials += mem, wr, rd
        return wr, rd

    def _write(self) -> tuple[Array, Array, Signal]:
        hp = self.hp
        bus, take, done = Signal(32), Signal(), Signal()
        t_ptr, i_ptr, b_ptr = Signal(max=WRITES), Signal(max=WRITES), Signal(max=WRITES)
        unsent = Signal(max=WRITES + 1)  # taken, AW/W not yet sent
        word = Array(Signal(WINDOW_LOG2 - 2) for _ in range(WRITES))  # the 32-bit word each covers
        strb = Array(Signal(4) for _ in range(WRITES))
        live = Signal(WRITES)  # taken, no B yet
        wr, head = self._ring(32 + 4 + WINDOW_LOG2 - 2, WRITES)
        h_word, h_data, h_strb = head.dat_r[36:], head.dat_r[:32], head.dat_r[32:36]
        send = (unsent != 0) & (~hp.aw.valid | hp.aw.ready) & (~hp.w.valid | hp.w.ready)
        self.comb += [
            bus.eq(self.base + self.wr_req_addr),
            self.wr_req_ready.eq(self.enable & (self.writes < WRITES)),
            take.eq(self.wr_req_valid & self.wr_req_ready), done.eq(hp.b.valid & hp.b.ready),
            wr.adr.eq(t_ptr), wr.we.eq(take), wr.dat_w.eq(Cat(self.wr_req_data, self.wr_req_strb, bus[2:WINDOW_LOG2])),
            head.adr.eq(i_ptr),
            # WR32: 4-byte beats on WDATA[31:0], AWCACHE[1] clear so the AFI never upsizes.
            hp.aw.size.eq(SIZE_4), hp.aw.cache.eq(AW_CACHE), hp.w.last.eq(1), hp.w.id.eq(0),
            self.wr_pending.eq(self.writes != 0),
        ]  # fmt: skip
        self.sync += [
            If(take, word[t_ptr].eq(bus[2:WINDOW_LOG2]), strb[t_ptr].eq(self.wr_req_strb), t_ptr.eq(_step(t_ptr, WRITES))),
            live.eq((live | Mux(take, 1 << t_ptr, 0)) & ~Mux(done, 1 << b_ptr, 0)),
            If(done, b_ptr.eq(_step(b_ptr, WRITES))),
            If(send,
               hp.aw.valid.eq(1), hp.aw.addr.eq(Cat(Const(0, 2), h_word, Const(DDR_BASE >> WINDOW_LOG2, 32 - WINDOW_LOG2))),
               hp.aw.len.eq(0), hp.w.valid.eq(1), hp.w.data.eq(Cat(h_data, h_data)), hp.w.strb.eq(h_strb),
               i_ptr.eq(_step(i_ptr, WRITES)))
            .Else(
               If(hp.aw.ready, hp.aw.valid.eq(0)),
               If(hp.w.ready, hp.w.valid.eq(0))),
            unsent.eq(unsent + take - send),
            self.writes.eq(self.writes + take - done),
        ]  # fmt: skip
        return word, strb, live

    def _alias(self, addr: Signal) -> Any:  # Any: a Migen expression
        """A write in flight (taken, no B) covers the byte at bus address `addr`."""
        if self.break_ == "alias":
            return 0
        hit = 0
        for k in range(WRITES):
            hit = hit | (self.w_live[k] & (self.w_word[k] == addr[2:WINDOW_LOG2]) & (self.w_strb[k] >> addr[:2])[0])
        return hit

    def _read(self) -> None:
        hp = self.hp
        bus, take, back, send = Signal(32), Signal(), Signal(), Signal()
        q_wr, q_head = self._ring(32, RQ)
        qt, qs, level = Signal(max=RQ), Signal(max=RQ), Signal(max=RQ + 1)
        l_wr, l_head = self._ring(1, READS)  # the half of the beat each read in flight wants
        lt, lb, flight = Signal(max=READS), Signal(max=READS), Signal(max=READS + 1)
        head = q_head.dat_r
        newest = Signal(max=READS)
        self.comb += [
            bus.eq(self.base + self.rd_req_addr),
            self.rd_req_ready.eq(self.enable & (level < RQ)),
            take.eq(self.rd_req_valid & self.rd_req_ready), back.eq(hp.r.valid & hp.r.ready),
            q_wr.adr.eq(qt), q_wr.we.eq(take), q_wr.dat_w.eq(bus), q_head.adr.eq(qs),
            send.eq((level != 0) & (~hp.ar.valid | hp.ar.ready) & (flight < READS) & ~self._alias(head)),
            l_wr.adr.eq(lt), l_wr.we.eq(send), l_wr.dat_w.eq(head[2]),
            newest.eq(Mux(lt == 0, READS - 1, lt - 1)),
            l_head.adr.eq(newest if self.break_ == "order" else lb),
        ]  # fmt: skip
        self.sync += [
            If(take, qt.eq(_step(qt, RQ))),
            If(send,
               hp.ar.valid.eq(1), hp.ar.addr.eq(Cat(Const(0, 3), ddr_byte(head)[3:])), hp.ar.len.eq(0),
               qs.eq(_step(qs, RQ)), lt.eq(_step(lt, READS)))
            .Elif(hp.ar.ready, hp.ar.valid.eq(0)),
            level.eq(level + take - send),
            flight.eq(flight + send - back),
            If(back, lb.eq(_step(lb, READS))),
            self.reads.eq(self.reads + take - back),
            self.rd_rsp_valid.eq(back),
            If(back, self.rd_rsp_data.eq(Mux(l_head.dat_r[0], hp.r.data[32:], hp.r.data[:32]))),
        ]  # fmt: skip
