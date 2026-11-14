"""The read side of WishboneHP (soc/zm_hp.py): its line buffer and its AXI reads.

A miss is one AXI read: the whole line (a 4-beat burst) for a Wishbone burst beat (a cache-line
refill: VexRiscv's 8-beat incrementing burst, `cti` 010...111), the one beat for a single read.
The beats land in the line buffer, which serves the burst's words as they arrive and lives only
until the burst ends, so nothing goes stale behind the video DMA or CHISEL.

These are functions on the bridge (`m`, a WishboneHP), not a submodule: `ack` and `dat_r` are
the bridge's registers, and its store side sets `ack` too.
"""

from __future__ import annotations

from typing import Any

from migen import Array, Cat, If, Mux, Signal
from migen import Constant as Const

CTI_CLASSIC, CTI_INCR, CTI_END = 0b000, 0b010, 0b111
LINE_BEATS = 4  # VexRiscv's 32-byte lines (vexgen GenZm.scala bytePerLine) in 64-bit beats

# The bridge: a WishboneHP, whose signals these functions read and drive (an import cycle otherwise).
Bridge = Any


def line_buffer(m: Bridge, fast_burst: bool = False, break_: str = "") -> None:
    """The beats of the line being refilled, valid until its burst ends.

    `fast_burst`: a burst's words go out one a clock instead of one every two. The ack is a
    register, so without it every word costs a request cycle and an ack cycle (`req` drops while
    `ack` is high). With it, the cycle a burst beat is acknowledged with `cti` 010 (more to come)
    the bridge already answers the NEXT word: VexRiscv's D$ and I$ masters advance their
    address on ACK (DataCache/InstructionCache.toWishbone), so it is on the bus the cycle after,
    within the same line. 7 clocks off every refill (BENCH's 48-cycle miss). The masters must not
    pause a burst (VexRiscv's never do). `break_`: "noadvance" answers the same word twice,
    "nostore" keeps the buffer over a store to its line (tests/test_hp_prefetch.py)."""
    bus = m.bus
    m.buf = Array(Signal(64, name=f"hp_line{i}") for i in range(LINE_BEATS))
    m.valid, m.tag = Signal(LINE_BEATS, name="hp_valid"), Signal(len(m.line), name="hp_tag")
    m.live = Signal(name="hp_live")
    word_in_line = m.bus.adr[:3]
    if fast_burst:
        cont = m.ack & (bus.cti == CTI_INCR)  # this beat is taken and the burst goes on
        word_in_line = Mux(cont, word_in_line + (break_ != "noadvance"), word_in_line)
        ask = bus.cyc & bus.stb & ~bus.we & (~m.ack | cont)
    else:
        ask = m.req & ~bus.we
    idx, hi = word_in_line[1:3], word_in_line[0]
    m.hit = m.live & (m.tag == m.line) & (m.valid >> m.beat[:2])[0]  # the word on the bus now
    ready = m.live & (m.tag == m.line) & (m.valid >> idx)[0]  # the word answered next clock
    word = m.buf[idx]
    last = (bus.cti == CTI_CLASSIC) | (bus.cti == CTI_END)
    m.sync += [
        m.ack.eq(ask & ready),
        If(ask & ready, bus.dat_r.eq(Mux(hi, word[32:], word[:32]))),
        # A refill's last beat (or a single read) closes the buffer: the next one refetches. So does
        # a store to the buffered line (a burst the master abandoned: tests/test_io_fence.py); a store
        # to another line does not, so a prefetched line survives the stores of a copy.
        If(m.ack & last & (~bus.we | ((m.tag == m.line) & (break_ != "nostore"))), m.live.eq(0)),
    ]


def axi_read(m: Bridge, ddr_addr: Any) -> Any:  # Any: zm_hp.ddr_addr builds Migen expressions; returns one
    """A miss: one AXI read, the whole line for a burst beat, the one beat otherwise. Returns its
    start condition (the prefetch yields to it: soc/zm_hp_prefetch.py)."""
    bus, hp = m.bus, m.hp
    m.fill = Signal(2, name="hp_fill")
    busy, fill = m.rbusy, m.fill
    burst = bus.cti != CTI_CLASSIC
    start = m.req & ~bus.we & ~m.hit & ~busy & ~m.rwait
    first = Mux(burst, Cat(Const(0, 2), m.line), m.beat)
    m.sync += [
        If(start,
           hp.ar.valid.eq(1), hp.ar.addr.eq(ddr_addr(first)), hp.ar.len.eq(Mux(burst, LINE_BEATS - 1, 0)),
           busy.eq(1), fill.eq(Mux(burst, 0, m.beat[:2])),
           m.tag.eq(m.line), m.valid.eq(0), m.live.eq(1)),
        If(hp.ar.valid & hp.ar.ready, hp.ar.valid.eq(0)),
        If(hp.r.valid & hp.r.ready,
           m.buf[fill].eq(hp.r.data), m.valid.eq(m.valid | (1 << fill)), fill.eq(fill + 1),
           If(hp.r.last, busy.eq(0))),
    ]  # fmt: skip
    m.comb += hp.r.ready.eq(1)
    return start
