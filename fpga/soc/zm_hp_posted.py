"""Posted stores for WishboneHP (soc/zm_hp.py, `posted=N`): CYCLES.md "Store path".

The D-cache is write-through, so every store crosses the bridge. Acknowledged on its
AXI write response, a store costs a whole DDR round trip; a CPU that keeps state in
memory (the SNDH player's Musashi: the 68000's registers) then spends half its time
waiting (docs/FPGA_SOUND_CPU.md "Where the cycles go"). Here a store is acknowledged
as soon as it is in an N-entry buffer, and the buffer drains on its own, one 1-beat
write after another, several in flight (the HP port accepts 8 write commands).

**`idle` is the ordering contract.** It is high only while no store is buffered or
unanswered: every store the CPU has had acknowledged is then in DDR. Each consumer
that used to rely on "an acknowledged store is in DDR" must also wait for it:
- the bridge's own reads (a refill or a single read starts only while `idle`, so a
  load sees the stores before it, and so does a refill of their line);
- the video snoop's `drained` (soc/zigmachine_soc.py): the compositor must not read
  a line the CPU's stores have not reached;
- the blitter's start (soc/zm_blit_soc.py): an op must not read pixels still in
  the buffer.
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect import axi
from migen import Cat, If, Memory, Mux, Signal

INFLIGHT = 8  # write commands an HP port accepts (UG585 5.3.1); more only queue in the buffer

# A LiteX wishbone.Interface: untyped, its signals are attributes made at runtime.
Bus = Any


def _next(p: Signal, depth: int) -> Any:  # Any: a Migen expression
    return Mux(p == depth - 1, 0, p + 1)


class PostedStores(LiteXModule):
    """The store half of WishboneHP: `bus` stores into a `depth`-entry buffer, drained to `hp`'s
    AW/W/B. `req` is the bridge's request (a beat not yet acknowledged); `push` is high on the
    cycle a store enters the buffer, and the bridge acknowledges it on the next."""

    def __init__(self, bus: Bus, hp: axi.AXIInterface, req: Signal, depth: int, **kw: Any) -> None:
        word_addr, size, cache = kw["word_addr"], kw["size"], kw["cache"]
        self.idle, self.push = Signal(), Signal()
        # The buffer: a ring in LUTRAM (one write port, the head read combinationally). Not migen's
        # SyncFIFO, whose write-only port has no dat_r and fails migen's own simulator (litex_compat.py).
        width = len(bus.adr) + 32 + 4
        ring = Memory(width, depth)
        wr, head = ring.get_port(write_capable=True), ring.get_port(async_read=True)
        self.specials += ring, wr, head
        w_ptr, r_ptr, level = Signal(max=depth), Signal(max=depth), Signal(max=depth + 1)
        readable, writable = Signal(), Signal()
        inflight = Signal(max=INFLIGHT + 1)
        adr, dat, sel = head.dat_r[: len(bus.adr)], head.dat_r[len(bus.adr) : -4], head.dat_r[-4:]
        push = self.push
        issue = readable & ~hp.aw.valid & ~hp.w.valid & (inflight < INFLIGHT)
        answered = hp.b.valid & hp.b.ready
        self.comb += [
            readable.eq(level != 0), writable.eq(level != depth),
            push.eq(req & bus.we & writable),
            wr.adr.eq(w_ptr), wr.dat_w.eq(Cat(bus.adr, bus.dat_w, bus.sel)), wr.we.eq(push),
            head.adr.eq(r_ptr),
            self.idle.eq(~readable & ~hp.aw.valid & ~hp.w.valid & (inflight == 0)),
            hp.aw.size.eq(size), hp.aw.cache.eq(cache), hp.w.last.eq(1), hp.w.id.eq(0), hp.b.ready.eq(1),
        ]  # fmt: skip
        self.sync += [
            If(issue,
               hp.aw.valid.eq(1), hp.aw.addr.eq(word_addr(adr)), hp.aw.len.eq(0),
               hp.w.valid.eq(1), hp.w.data.eq(Cat(dat, dat)), hp.w.strb.eq(sel)),
            If(hp.aw.valid & hp.aw.ready, hp.aw.valid.eq(0)),
            If(hp.w.valid & hp.w.ready, hp.w.valid.eq(0)),
            inflight.eq(inflight + issue - answered),
            level.eq(level + push - issue),
            If(push, w_ptr.eq(_next(w_ptr, depth))),
            If(issue, r_ptr.eq(_next(r_ptr, depth))),
        ]  # fmt: skip
