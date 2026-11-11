"""WishboneHP's next-line prefetch and burst acks (soc/zm_hp_prefetch.py, soc/zm_hp_read.py
`fast_burst`), on a model port whose memory another master rewrites: every word reads
(beat address << 8 | generation), and `gen` moves when the test says the other master wrote.

- a sequential refill is served from the prefetch (no AR of its own, a word a clock);
- random refills never prefetch;
- the rules that keep a prefetched line from going stale: a store to its line, an IO access
  (or a pending interrupt: zm_board_mem.py wires both into `io_kill`), and another refill
  taking the buffer. ZM_RTL_BREAK=1 builds each mutant and requires the stale word.
The core-level proof (the real VexRiscv, the bench loops, the same checksums) is
tests/test_ziggy_reads.py."""

from __future__ import annotations

import os
from collections import deque

import pytest
from litex.soc.interconnect import wishbone
from migen import Module, run_simulation

from soc.zm_hp import CPU_BASE, WishboneHP, hp_interface

Sim = object
R_LAT, B_LAT = 20, 18  # tests/hp_port_model.py: AR to first beat, AW to B
L = CPU_BASE + 0x4000  # a line; L + 32 * k the k-th after it
BREAK = pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")


class Bench(Module):
    def __init__(self, read_break: str = "") -> None:
        self.cpu = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.hp = hp_interface()
        self.submodules.bridge = WishboneHP(self.cpu, self.hp, 8, fast_burst=True, prefetch=True,
                                            read_break=read_break)  # fmt: skip
        self.comb += [self.hp.aw.ready.eq(1), self.hp.w.ready.eq(1), self.hp.ar.ready.eq(1)]
        self.gen, self.ars, self.cycle = 0, [], 0


def port(b: Bench, cycles: int) -> Sim:
    """In-order reads R_LAT after their AR; each beat's two words are (byte address << 8 | gen) as
    the memory holds them when the beat leaves; writes answered B_LAT after their AW."""
    hp, r_due, b_due = b.hp, deque[tuple[int, int, bool]](), deque[int]()
    for now in range(cycles):
        b.cycle = now
        if (yield hp.ar.valid):
            n, a = (yield hp.ar.len), (yield hp.ar.addr)
            b.ars.append(((a - 0x04000000) + CPU_BASE, now))
            r_due.extend((now + R_LAT + i, a + 8 * i, i == n) for i in range(n + 1))
        if (yield hp.aw.valid):
            b_due.append(now + B_LAT)
        beat = bool(r_due) and r_due[0][0] <= now
        if beat:
            _, a, last = r_due.popleft()
            lo, hi = ((a & 0xFFFFFF) << 8) | b.gen, (((a + 4) & 0xFFFFFF) << 8) | b.gen
            yield hp.r.data.eq(lo | hi << 32)
            yield hp.r.last.eq(last)
        yield hp.r.valid.eq(beat)
        answer = bool(b_due) and b_due[0] <= now
        if answer:
            b_due.popleft()
        yield hp.b.valid.eq(answer)
        yield


def put(*assigns: object) -> Sim:
    yield from assigns


def refill(b: Bench, line: int) -> Sim:
    """VexRiscv's refill as DataCache.toWishbone drives it: CYC held, the address advanced the clock
    after each ACK, cti 010 then 111. Returns (the 8 words, clocks from the request to the last ack)."""
    bus, words, n = b.cpu, [], 0
    yield from put(bus.adr.eq(line >> 2), bus.cti.eq(0b010), bus.we.eq(0), bus.sel.eq(0xF))
    yield from put(bus.cyc.eq(1), bus.stb.eq(1))
    while len(words) < 8:
        yield
        n += 1
        if (yield bus.ack):
            words.append((yield bus.dat_r))
            k = len(words)
            yield from put(bus.adr.eq((line >> 2) + k), bus.cti.eq(0b111 if k == 7 else 0b010))
    yield from put(bus.cyc.eq(0), bus.stb.eq(0))
    yield
    return words, n


def store(b: Bench, addr: int, value: int) -> Sim:
    bus = b.cpu
    yield from put(bus.adr.eq(addr >> 2), bus.cti.eq(0), bus.we.eq(1), bus.dat_w.eq(value), bus.sel.eq(0xF))
    yield from put(bus.cyc.eq(1), bus.stb.eq(1))
    yield
    while not (yield bus.ack):
        yield
    yield from put(bus.cyc.eq(0), bus.stb.eq(0), bus.we.eq(0))
    yield


def idle(n: int) -> Sim:
    for _ in range(n):
        yield


def run(b: Bench, cpu: Sim) -> None:
    run_simulation(b, [cpu, port(b, 3000)])


def expected(line: int, gen: int) -> list[int]:
    return [(((line + 4 * i) - CPU_BASE + 0x04000000) & 0xFFFFFF) << 8 | gen for i in range(8)]


def test_a_sequential_refill_comes_from_the_prefetch_a_word_a_clock() -> None:
    b, out = Bench(), {}

    def cpu() -> Sim:
        yield from refill(b, L - 32)
        yield from refill(b, L)  # sequential: the next line goes out now
        yield from idle(40)  # the CPU works through L meanwhile
        ars = len(b.ars)
        out["words"], out["clocks"] = yield from refill(b, L + 32)
        yield from idle(5)
        out["new_ars"] = [a for a, _ in b.ars[ars:]]

    run(b, cpu())
    assert out["words"] == expected(L + 32, 0)
    assert out["new_ars"] == [L + 64], "the line was in the buffer: only the NEXT prefetch goes out"
    assert out["clocks"] <= 9, out["clocks"]  # registered ack + 8 words back to back


def test_random_refills_never_prefetch() -> None:
    b = Bench()

    def cpu() -> Sim:
        for k in (0, 5, 2, 9):
            yield from refill(b, L + 32 * k)
            yield from idle(40)

    run(b, cpu())
    assert [a for a, _ in b.ars] == [L + 32 * k for k in (0, 5, 2, 9)]


def _stale_after(between: str, read_break: str = "") -> list[int]:
    """A stream reaches L+64, prefetched while the other master had not yet written it (gen 0);
    then the other master writes it (gen 1), `between` happens, and the CPU reads L+64."""
    b, out = Bench(read_break), {}

    def cpu() -> Sim:
        yield from refill(b, L)
        yield from refill(b, L + 32)  # L+64 prefetched now
        yield from idle(40)
        b.gen = 1
        if between == "store":
            yield from store(b, L + 64, 0xAB)
            yield from idle(40)  # the store drains
        elif between == "io":
            yield b.bridge.io_kill.eq(1)
            yield
            yield b.bridge.io_kill.eq(0)
        elif between == "other_refill":
            yield from refill(b, L + 32 * 9)
        out["w"], _ = yield from refill(b, L + 64)

    run(b, cpu())
    return out["w"]


@pytest.mark.parametrize("between", ["store", "io", "other_refill"])
def test_a_prefetched_line_is_dropped_when_the_cpu_could_know_better(between: str) -> None:
    assert _stale_after(between) == expected(L + 64, 1)


def test_with_nothing_in_between_the_prefetched_line_is_served() -> None:
    assert _stale_after("none") == expected(L + 64, 0)  # the same as a refill made at the prefetch


@BREAK
def test_break_a_burst_ack_that_does_not_advance_repeats_a_word() -> None:
    b, out = Bench("noadvance"), {}

    def cpu() -> Sim:
        out["w"], _ = yield from refill(b, L)

    run(b, cpu())
    assert out["w"] != expected(L, 0)


@BREAK
@pytest.mark.parametrize(("between", "mutant"), [("store", "nostore"), ("io", "noio")])
def test_break_each_rule_serves_the_stale_line(between: str, mutant: str) -> None:
    assert _stale_after(between, mutant) == expected(L + 64, 0)
