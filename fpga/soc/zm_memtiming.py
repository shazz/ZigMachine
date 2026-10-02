"""A timing model of the board's memory path, for the cycles sim (CYCLES.md,
"Memory path").

It sits between the SoC interconnect and the one-cycle main RAM and only
withholds `stb`: the data still goes to and from the SRAM, so every cart's
hashes are unchanged, and the CPU's stalls are what the configured path would
cost. All parameters are run-time (rtl/sim/zm_memcfg.v reads zm_memcfg.init),
so one Verilated model runs every configuration. Cycles are cart-CPU cycles,
EXTRA over the sim's own cost (2 cycles a word: LiteX's SRAM without bursts).

- rd_lat: first-word latency of a read access (one word, or a cache-line burst);
  the words after the first come at the sim's own rate.
- wr_lat: latency of a store when there is no store buffer (sb_depth = 0): the
  bridge waits for the AXI write response before acknowledging.
- sb_depth, sb_drain: a posted-write buffer of sb_depth entries; a store is
  acknowledged at once while there is room, and one entry leaves every sb_drain
  cycles. sb_combine: stores to the newest entry's 32-byte line merge into it;
  that entry closes on a store to another line or after wc_timeout idle cycles.
- rd_waits_sb: a read waits until the buffer is empty (a bridge without an
  address check). Otherwise reads overtake buffered writes.
- l2_on, l2_hit_lat: the ACP path: a 512 KiB direct-mapped tag model of the
  PS L2 (reads and writes allocate); a read that hits costs l2_hit_lat, not rd_lat.
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from migen import Cat, If, Instance, Memory, Mux, Signal

# A LiteX wishbone.Interface: untyped, its signals are attributes made at runtime.
Bus = Any
CFG = ["rd_lat", "wr_lat", "sb_depth", "sb_drain", "sb_combine", "rd_waits_sb", "l2_on", "l2_hit_lat", "wc_timeout"]
CTI_INCR = 0b010
L2_INDEX = 14  # 2**14 lines of 32 bytes = 512 KiB


class ZMMemTiming(LiteXModule):
    def __init__(self, master: Bus, slave: Bus, cfg_bits: Signal | None = None) -> None:
        """cfg_bits: the 16 config words, word i at bits 32i (tests drive it; the
        sim reads it from zm_memcfg.init)."""
        if cfg_bits is None:
            cfg_bits = Signal(512)
            self.specials += Instance("zm_memcfg", o_cfg=cfg_bits)
        self.cfg = {name: cfg_bits[32 * i : 32 * i + 16] for i, name in enumerate(CFG)}
        self.m, self.s = master, slave
        self.req = master.cyc & master.stb
        self.line = master.adr[3:]  # word address -> 32-byte line
        self._passthrough()
        self._burst()
        self._store_buffer()
        self._l2()
        self._latency()

    def _passthrough(self) -> None:
        m, s = self.m, self.s
        self.go = Signal()
        self.comb += [
            s.adr.eq(m.adr), s.dat_w.eq(m.dat_w), s.sel.eq(m.sel), s.we.eq(m.we), s.cti.eq(m.cti),
            s.bte.eq(m.bte), s.cyc.eq(m.cyc), s.stb.eq(m.stb & self.go),
            m.dat_r.eq(s.dat_r), m.ack.eq(s.ack), m.err.eq(s.err),
        ]  # fmt: skip

    def _burst(self) -> None:
        """A beat after the first of an incrementing burst carries no new latency."""
        self.in_burst = Signal()
        self.sync += [
            If(self.s.ack, self.in_burst.eq(self.m.cti == CTI_INCR)),
            If(~self.m.cyc, self.in_burst.eq(0)),
        ]

    def _store_buffer(self) -> None:
        c = self.cfg
        self.sb_on = c["sb_depth"] != 0
        self.closed, self.open_v, self.open_line = Signal(16), Signal(), Signal(len(self.line))
        age, drain = Signal(16), Signal(16)
        same = c["sb_combine"][0] & self.open_v & (self.line == self.open_line)
        held = self.closed + self.open_v
        self.sb_room = Mux(c["sb_combine"][0], same | (held < c["sb_depth"]), self.closed < c["sb_depth"])
        self.sb_empty = (self.closed == 0) & ~self.open_v
        self.flush = Signal()  # a waiting read closes the open entry
        stored = self.s.ack & self.m.we & self.sb_on
        opens = stored & c["sb_combine"][0] & ~same
        timeout = self.open_v & ~opens & ((age >= c["wc_timeout"]) | self.flush)
        done = (self.closed != 0) & (drain + 1 >= c["sb_drain"])
        inc = Mux(stored & ~c["sb_combine"][0], 1, 0) + Mux(opens & self.open_v, 1, 0) + Mux(timeout, 1, 0)
        self.sync += [
            self.closed.eq(self.closed + inc - done),
            If(done | (self.closed == 0), drain.eq(0)).Else(drain.eq(drain + 1)),
            If(stored & same, age.eq(0)).Elif(self.open_v, age.eq(age + 1)),
            If(opens, self.open_v.eq(1), self.open_line.eq(self.line), age.eq(0)).Elif(timeout, self.open_v.eq(0)),
        ]

    def _l2(self) -> None:
        """Tag-only model of the PS L2 behind the ACP: no data, just hit or miss."""
        tag_w = len(self.line) - L2_INDEX
        tags = Memory(tag_w + 1, 2**L2_INDEX)
        rd, wr = tags.get_port(async_read=True), tags.get_port(write_capable=True)
        self.specials += tags, rd, wr
        index, tag = self.line[:L2_INDEX], self.line[L2_INDEX:]
        self.l2_hit = Signal()
        self.l2_fill = Signal()  # allocate this access's line
        self.comb += [
            rd.adr.eq(index), self.l2_hit.eq(rd.dat_r == Cat(tag, 1)),
            wr.adr.eq(index), wr.dat_w.eq(Cat(tag, 1)), wr.we.eq(self.l2_fill & self.cfg["l2_on"][0]),
        ]  # fmt: skip

    def _latency(self) -> None:
        """New read (or unbuffered write) access: count its latency, then let it go."""
        c, m = self.cfg, self.m
        waiting, count = Signal(), Signal(16)
        buffered = m.we & self.sb_on
        new = self.req & ~self.in_burst & ~waiting
        rd_lat = Mux(c["l2_on"][0] & self.l2_hit, c["l2_hit_lat"], c["rd_lat"])
        lat = Mux(m.we, c["wr_lat"], rd_lat)
        blocked = ~m.we & c["rd_waits_sb"][0] & ~self.sb_empty
        start = new & ~buffered & ~blocked
        self.comb += [
            self.flush.eq(new & blocked),
            self.l2_fill.eq(start | (new & buffered & self.sb_room)),
            self.go.eq(
                (self.req & self.in_burst)
                | (start & (lat == 0))
                | (waiting & (count == 0))
                | (new & buffered & self.sb_room)
            ),
        ]
        self.sync += [
            If(start & (lat != 0), waiting.eq(1), count.eq(lat - 1)).Elif(waiting & (count != 0), count.eq(count - 1)),
            If(self.s.ack & waiting, waiting.eq(0)),
        ]
