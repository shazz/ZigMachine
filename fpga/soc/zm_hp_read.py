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

from migen import Array, Cat, Constant as Const, If, Mux, Signal

CTI_CLASSIC, CTI_END = 0b000, 0b111
LINE_BEATS = 4  # VexRiscv's 32-byte lines (vexgen GenZm.scala bytePerLine) in 64-bit beats

# The bridge: a WishboneHP, whose signals these functions read and drive (an import cycle otherwise).
Bridge = Any


def line_buffer(m: Bridge) -> None:
    """The beats of the line being refilled, valid until its burst ends."""
    bus = m.bus
    m.buf = Array(Signal(64, name=f"hp_line{i}") for i in range(LINE_BEATS))
    m.valid, m.tag = Signal(LINE_BEATS, name="hp_valid"), Signal(len(m.line), name="hp_tag")
    m.live = Signal(name="hp_live")
    idx = m.beat[:2]
    m.hit = m.live & (m.tag == m.line) & (m.valid >> idx)[0]
    word = m.buf[idx]
    last = (bus.cti == CTI_CLASSIC) | (bus.cti == CTI_END)
    m.sync += [
        m.ack.eq(m.req & ~bus.we & m.hit),
        If(m.req & ~bus.we & m.hit, bus.dat_r.eq(Mux(m.lane_hi, word[32:], word[:32]))),
        # A burst's last beat (or a single access) closes the buffer: the next one refetches.
        If(m.ack & last, m.live.eq(0)),
    ]


def axi_read(m: Bridge, ddr_addr: Any) -> None:  # Any: soc/zm_hp.py ddr_addr, a Migen expression builder
    """A miss: one AXI read, the whole line for a burst beat, the one beat otherwise."""
    bus, hp = m.bus, m.hp
    busy, fill = m.rbusy, Signal(2, name="hp_fill")
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
