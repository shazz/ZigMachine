"""How fast a store stream leaves the posted bridge (soc/zm_hp_posted.py): several writes in
flight, the next one issued as soon as the port took the last AW and W, never waiting for its
write response. On the board a blocking store costs 18 cycles, one HP0 write response each
(bench cart, posted=0, 2026-10-18); this pins that the buffer pipelines instead."""

from __future__ import annotations

from litex.soc.interconnect import wishbone
from migen import Module, run_simulation
from test_hp_posted import Sim, access

from soc.zm_hp import CPU_BASE, WishboneHP, hp_interface

B_LATENCY = 18  # issue to write response, the board's measured blocking store


class Pipelined(Module):
    """The bridge on a port that takes an AW and a W every cycle and answers each B_LATENCY
    cycles later, as HP0 does (8 writes in flight): the bridge is then what bounds a stream."""

    def __init__(self, posted: int) -> None:
        self.cpu = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.hp = hp_interface()
        self.submodules.bridge = WishboneHP(self.cpu, self.hp, posted)
        self.comb += [self.hp.aw.ready.eq(1), self.hp.w.ready.eq(1)]
        self.acks = 0


def _port(p: Pipelined, cycles: int, inflight: list[int]) -> Sim:
    """Answers every write B_LATENCY cycles after its AW; records the most in flight at once."""
    due: list[int] = []
    for now in range(cycles):
        if (yield p.hp.aw.valid):
            due.append(now + B_LATENCY)
        inflight[0] = max(inflight[0], len(due))
        answer = bool(due) and due[0] <= now
        yield p.hp.b.valid.eq(answer)
        if answer:
            due.pop(0)
        yield


def _per_store(posted: int, n: int = 64) -> tuple[float, int]:
    p, out, inflight = Pipelined(posted), {}, [0]

    def cpu() -> Sim:
        t = 0
        for i in range(n):
            _, c = yield from access(p, CPU_BASE + 4 * i, i)  # type: ignore[arg-type]  # Bench's duck type
            t += c + 1  # access() spends one more cycle dropping cyc
        out["t"] = t / n

    run_simulation(p, [cpu(), _port(p, n * (B_LATENCY + 8), inflight)])
    return out["t"], inflight[0]


def test_a_posted_store_stream_keeps_several_writes_in_flight_at_a_few_cycles_a_store() -> None:
    per_store, inflight = _per_store(8)
    assert per_store <= 4 and inflight >= 4, (per_store, inflight)


def test_a_blocking_store_stream_pays_one_write_response_a_store() -> None:
    per_store, inflight = _per_store(0)
    assert per_store >= B_LATENCY and inflight == 1, (per_store, inflight)
