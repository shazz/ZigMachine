"""Write bursts for the blitter's HP2 bridge (soc/zm_blit_hp.py `burst=N`, off by default).

Without it every 32-bit word zm_blit writes is its own 1-beat AXI write, and the HP port
holds at most 8 write commands, so the blitter writes at most 8 words per AW-to-B round
trip: ~7 clocks a word once DDR is loaded (latency ~56), where the pixel unit makes one
every ~4. Here consecutive words are coalesced into one INCR burst of up to N 32-bit
beats (WR32, AWCACHE 0: the 32-bit write channel never upsizes), so the 8 commands carry
up to 8N words.

- **The open burst.** A taken word joins it when it is the next word, the burst has
  fewer than N beats and does not end at a 4 KiB page (an AXI burst never crosses one).
  It closes when it is full or ends a page, when a taken word cannot join (that word
  opens the next), after TIMEOUT clocks with no take (the op's last words), or when a
  read waits for one of its words (`flush`). Each beat keeps its own strobes, so a
  keyed or partial word still joins; a keyed-out word is a gap and splits the run.
- **Closed bursts** wait in a ring of BURSTS entries (start word, beats) for their AW,
  then stream their beats from a 2N-beat LUTRAM FIFO, one a clock, WLAST on the last;
  an entry is live until its B. `pending` = an open burst or any live entry, so zm_blit's
  BUSY still means "the pixels are in DDR".
- **Ordering.** `alias(word)`: a read of a word in the open burst or a live one waits,
  whatever the strobes (the 1-beat bridge compares bytes; this one is conservative,
  which only ever delays a read).
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect import axi
from migen import Array, Cat, If, Memory, Mux, Signal
from migen import Constant as Const

from soc.zm_hp import AW_CACHE, DDR_BASE, SIZE_4, WINDOW_LOG2

BURSTS = 8  # write commands the HP port accepts (UG585 5.3.1)
PAGE = 10  # a 4 KiB page, in 32-bit words
TIMEOUT = 8  # clocks with no take before an open burst goes out
WORD = WINDOW_LOG2 - 2  # a 32-bit word inside the 32 MiB window


def _step(p: Signal, depth: int) -> Any:  # Any: a Migen expression
    return Mux(p == depth - 1, 0, p + 1)


class BurstWrites(LiteXModule):
    """`take` with `word`/`data`/`strb`: one write taken (only while `room`). `flush`: a read
    waits for the open burst."""

    def __init__(self, hp: axi.AXIInterface, beats: int) -> None:
        assert beats in (2, 4, 8, 16), "AXI3: at most 16 beats, a power of two keeps the page rule"
        self.hp, self.n = hp, beats
        self.take, self.word, self.data, self.strb = Signal(), Signal(WORD), Signal(32), Signal(4)
        self.flush, self.room, self.pending = Signal(), Signal(), Signal()
        self.o_v, self.o_start, self.o_len = Signal(), Signal(WORD), Signal(max=beats + 1)
        self.t_start = Array(Signal(WORD) for _ in range(BURSTS))
        self.t_len = Array(Signal(max=beats + 1) for _ in range(BURSTS))
        self.live = Signal(BURSTS)
        self.closed = Signal(max=BURSTS + 1)  # entries taken into the ring, no B yet
        close = self._open()
        self._send(close)

    def _open(self) -> Signal:
        n, depth = self.n, 2 * self.n
        idle, nxt, close, join = Signal(max=TIMEOUT + 1), Signal(WORD), Signal(), Signal()
        self.f_wr, self.f_head = self._ring(36, depth)
        self.f_wp, self.f_level = Signal(max=depth), Signal(max=depth + 1)
        self.c_ptr = Signal(max=BURSTS)
        full = (self.o_len == n) | (nxt[:PAGE] == 0)
        self.comb += [
            nxt.eq(self.o_start + self.o_len),
            close.eq(self.o_v & (full | (idle == TIMEOUT) | self.flush | (self.take & (self.word != nxt)))),
            join.eq(self.take & self.o_v & ~close),
            self.room.eq((self.closed + self.o_v < BURSTS) & (self.f_level < depth)),
            self.f_wr.adr.eq(self.f_wp), self.f_wr.we.eq(self.take), self.f_wr.dat_w.eq(Cat(self.data, self.strb)),
        ]  # fmt: skip
        self.sync += [
            If(self.take, self.f_wp.eq(_step(self.f_wp, depth)), idle.eq(0)).Elif(self.o_v, idle.eq(idle + 1)),
            If(close, self.t_start[self.c_ptr].eq(self.o_start), self.t_len[self.c_ptr].eq(self.o_len),
               self.c_ptr.eq(_step(self.c_ptr, BURSTS))),
            If(join, self.o_len.eq(self.o_len + 1))
            .Elif(self.take, self.o_v.eq(1), self.o_start.eq(self.word), self.o_len.eq(1))
            .Elif(close, self.o_v.eq(0)),
        ]  # fmt: skip
        return close

    def _send(self, close: Signal) -> None:
        hp, depth = self.hp, 2 * self.n
        i_ptr, b_ptr, unsent, left = Signal(max=BURSTS), Signal(max=BURSTS), Signal(max=BURSTS + 1), Signal(max=self.n + 1)
        f_rp = Signal(max=depth)
        done, issue, beat = Signal(), Signal(), Signal()
        f_data, f_strb = self.f_head.dat_r[:32], self.f_head.dat_r[32:]
        self.comb += [
            done.eq(hp.b.valid & hp.b.ready),
            issue.eq((unsent != 0) & (left == 0) & (~hp.aw.valid | hp.aw.ready)),
            beat.eq((left != 0) & (~hp.w.valid | hp.w.ready)),
            self.f_head.adr.eq(f_rp),
            hp.aw.size.eq(SIZE_4), hp.aw.cache.eq(AW_CACHE), hp.w.id.eq(0),
            self.pending.eq(self.o_v | (self.closed != 0)),
        ]  # fmt: skip
        self.sync += [
            If(issue,
               hp.aw.valid.eq(1), hp.aw.len.eq(self.t_len[i_ptr] - 1), left.eq(self.t_len[i_ptr]),
               hp.aw.addr.eq(Cat(Const(0, 2), self.t_start[i_ptr], Const(DDR_BASE >> WINDOW_LOG2, 32 - WINDOW_LOG2))),
               i_ptr.eq(_step(i_ptr, BURSTS)))
            .Elif(hp.aw.ready, hp.aw.valid.eq(0)),
            If(beat,
               hp.w.valid.eq(1), hp.w.data.eq(Cat(f_data, f_data)), hp.w.strb.eq(f_strb), hp.w.last.eq(left == 1),
               left.eq(left - 1), f_rp.eq(_step(f_rp, depth)))
            .Elif(hp.w.ready, hp.w.valid.eq(0)),
            self.f_level.eq(self.f_level + self.take - beat),
            unsent.eq(unsent + close - issue),
            self.closed.eq(self.closed + close - done),
            If(done, b_ptr.eq(_step(b_ptr, BURSTS))),
            self.live.eq((self.live | Mux(close, 1 << self.c_ptr, 0)) & ~Mux(done, 1 << b_ptr, 0)),
        ]  # fmt: skip

    def _ring(self, width: int, depth: int) -> tuple[Any, Any]:
        mem = Memory(width, depth)
        wr, rd = mem.get_port(write_capable=True), mem.get_port(async_read=True)
        self.specials += mem, wr, rd
        return wr, rd

    def alias(self, word: Any) -> Any:  # Any: Migen expressions
        """A write in the open burst or a live one covers 32-bit word `word` (strobes ignored)."""
        hit = self._covers(word, self.o_v, self.o_start, self.o_len)
        for k in range(BURSTS):
            hit = hit | self._covers(word, self.live[k], self.t_start[k], self.t_len[k])
        return hit

    def open_alias(self, word: Any) -> Any:  # Any: Migen expressions
        return self._covers(word, self.o_v, self.o_start, self.o_len)

    def _covers(self, word: Any, valid: Any, start: Signal, length: Signal) -> Any:  # Any: Migen expressions
        off = Signal(PAGE)  # word - start inside the page (a burst never leaves its page)
        self.comb += off.eq(word[:PAGE] - start[:PAGE])
        return valid & (word[PAGE:] == start[PAGE:]) & (off < length)
