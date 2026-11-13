"""Next-line prefetch for WishboneHP's line buffer (soc/zm_hp_read.py; WishboneHP `prefetch`):
review/ZIGGY_BIG_READS_STUDY.md.

ZIGGY's D$ is blocking: a sequential read pays the whole DDR round trip (~22 of a refill's ~43
clocks) on every 32-byte line. Here, when a refill ends and its line is the one after the
previous refill's (or was itself prefetched), the bridge reads the NEXT line into the same line
buffer at once, while the CPU works through the line it just got. When the CPU asks for that
line, its words go out of the buffer without an AXI read: a sequential refill costs the bridge
and the core's own clocks only. Random reads never trigger it (no DDR bandwidth spent).

**Why a prefetched line is never stale.** Its data is a DDR read made after the refill that
triggered it. Serving it later is the same as the CPU having made that refill at the prefetch's
time, which is correct as long as the CPU learned nothing newer in between. The CPU learns about
other masters (CHISEL, the video DMA, BARD, the ARM) only through the bus or an interrupt, so the
prefetched line is dropped (`kill`) on:
- a store to its line (the bridge's own posted store: the buffer would miss it). That is the line
  buffer's own rule (zm_hp_read.line_buffer: a store's ack closes the buffer of its line; before
  the AR, the AR waits for the store to drain), `nostore` mutant;
- any other read reaching the bridge (a refill of another line, a single read): that read may be
  a flag another master set after writing this line. With ONE line buffer this rule is the
  buffer's own: that read's AR takes the buffer (and clears `want`), so no extra logic;
- any CPU access to the IO space (`io_kill`: CHISEL's start and status, every CSR, the mailboxes;
  `noio` mutant) and any pending interrupt (wired into `io_kill` by zm_board_mem.py).
The AR waits for the posted stores to drain (`rwait`), like any read, so it sees every store
made before it; stores pushed after it are the store rule above.

Needs posted stores (only that store path keeps the buffer over other lines' stores) and `fast_burst` is advised
(the buffer then answers a word a clock). A prefetch in flight when another read comes is let
finish (its beats are dropped, the buffer is no longer live) before that read's AR.
"""

from __future__ import annotations

from typing import Any

from migen import Cat, If, Signal
from migen import Constant as Const

from soc.zm_hp_bypass import LINE_TAG
from soc.zm_hp_read import CTI_END, LINE_BEATS

BREAKS = ("", "noadvance", "nostore", "noio")  # the first two: zm_hp_read.line_buffer's
Bridge = Any  # a WishboneHP (soc/zm_hp.py); its signals are attributes


def prefetch(m: Bridge, ddr_addr: Any, start: Any, break_: str = "") -> None:  # Any: Migen expressions
    """Adds the prefetch to bridge `m`; `start` is axi_read's demand AR condition."""
    if break_ not in BREAKS:
        raise ValueError(f"zm_hp_prefetch: unknown break {break_!r}")
    bus, hp = m.bus, m.hp
    m.io_kill = Signal()  # the CPU touches the IO space, or an interrupt is pending (zm_board_mem.py)
    m.pf = Signal(name="hp_pf")  # the buffer holds (or is fetching) a line nobody asked for yet
    want = Signal(name="hp_pf_want")  # a prefetch of line `tag` is due, its AR not out yet
    after = Signal(LINE_TAG, name="hp_pf_after")  # the line after the last refill's (in the window)
    from_pf = Signal(name="hp_pf_used")  # the refill in progress is served from a prefetch
    on_tag = m.tag == m.line
    io = m.io_kill if break_ != "noio" else 0
    kill = io
    end = m.ack & (bus.cti == CTI_END)  # a refill's last word is taken this clock
    following = Signal(len(m.line))  # the line after this one: one incrementer for both uses
    m.comb += following.eq(m.line + 1)
    sequential = from_pf | (m.line[:LINE_TAG] == after)
    go = want & ~kill & ~m.req & ~m.rbusy & ~m.rwait
    m.sync += [
        If(m.req & ~bus.we & m.pf & m.live & on_tag, m.pf.eq(0), from_pf.eq(1)),  # the CPU wants it
        If(end,
           after.eq(following[:LINE_TAG]), from_pf.eq(0),
           If(sequential, m.tag.eq(following), want.eq(1))),
        If(go,
           hp.ar.valid.eq(1), hp.ar.addr.eq(ddr_addr(Cat(Const(0, 2), m.tag))), hp.ar.len.eq(LINE_BEATS - 1),
           m.rbusy.eq(1), m.fill.eq(0), m.valid.eq(0), m.live.eq(1), m.pf.eq(1), want.eq(0)),
        # A demand AR this clock owns the buffer: the kill must not undo its `live`.
        If(kill & ~start, want.eq(0), If(m.pf, m.pf.eq(0), m.live.eq(0))),
        If(start, want.eq(0), m.pf.eq(0)),
    ]  # fmt: skip
