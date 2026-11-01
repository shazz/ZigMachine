"""An HP port model for the bridge's ordering tests (tests/test_hp_bypass*.py): it takes an AW, a
W and an AR every cycle, answers each write B_LAT cycles after its AW (in order, as one AXI ID
does) and each read's first beat R_LAT cycles after its AR. No memory: these benches check WHEN
the bridge issues, and a monitor records every AR together with the stores still unanswered."""

from __future__ import annotations

from collections import deque
from collections.abc import Generator
from dataclasses import dataclass, field

from litex.soc.interconnect import wishbone
from migen import Module

from soc.zm_hp import WishboneHP, hp_interface

Sim = Generator[object, None, None]
B_LAT = 18  # issue to write response: the board's measured blocking store (BENCH_REPORTS.md)
R_LAT = 20  # AR to first beat (hp_sim HP_LATENCY): with this bench's per-beat overhead a refill takes
# ~47 cycles, the board's ld.miss (48)
LINE_MASK = (1 << 20) - 1  # the 32-byte line within the window


@dataclass
class Seen:
    """Every AR the bridge issued: (cycle, line, len, the lines of the stores still unanswered)."""

    reads: list[tuple[int, int, int, tuple[int, ...]]] = field(default_factory=list)
    most_writes: int = 0  # the most stores unanswered at once


class PortBench(Module):
    """The bridge (posted=8) on the model port."""

    def __init__(self, read_bypass: bool = True, break_: str = "") -> None:
        self.cpu = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.hp = hp_interface()
        self.submodules.bridge = WishboneHP(self.cpu, self.hp, 8, read_bypass, break_)
        self.comb += [self.hp.aw.ready.eq(1), self.hp.w.ready.eq(1), self.hp.ar.ready.eq(1)]
        self.acks = 0


def port(p: PortBench, cycles: int, seen: Seen, b_lat: int = B_LAT) -> Sim:
    """Answers writes (`b_lat` after each AW) and reads; records each AR with the stores pushed and
    not yet answered."""
    hp, b_due, r_due, pending = p.hp, deque[int](), deque[tuple[int, int]](), deque[int]()
    for now in range(cycles):
        if (yield hp.b.valid):  # the B the bridge sees this cycle: that store is answered
            pending.popleft()
        if (yield p.bridge.stores.push):
            pending.append(((yield p.cpu.adr) >> 3) & LINE_MASK)
        if (yield hp.aw.valid):
            b_due.append(now + b_lat)
        if (yield hp.ar.valid):
            n = yield hp.ar.len
            seen.reads.append((now, ((yield hp.ar.addr) >> 5) & LINE_MASK, n, tuple(pending)))
            r_due.extend((now + R_LAT + i, i == n) for i in range(n + 1))
        answer = bool(b_due) and b_due[0] <= now
        if answer:
            b_due.popleft()
        beat = bool(r_due) and r_due[0][0] <= now
        last = r_due.popleft()[1] if beat else False
        seen.most_writes = max(seen.most_writes, len(pending))
        yield hp.b.valid.eq(answer)
        yield hp.r.valid.eq(beat)
        yield hp.r.last.eq(last)
        yield hp.r.data.eq(now)
        yield
