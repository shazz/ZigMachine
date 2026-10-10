"""Posted stores in Migen's simulator (soc/zm_hp_posted.py, WishboneHP `posted=N`): a
store is acknowledged once it is buffered, and every consumer of "an acknowledged store
is in DDR" waits for the bridge's `idle` instead: its own reads, the video's `drained`
(soc/zm_video_snoop.py) and the blitter's start (soc/zm_blit_soc.py). Each guard has a
mutant here that the test catches."""

from __future__ import annotations

from collections.abc import Generator

import pytest
from litex.soc.interconnect import wishbone
from migen import Memory, Module, Mux, Signal, run_simulation

from soc import zm_video_snoop
from soc.zm_blit_soc import BLIT_WINDOW, ZMBlitTap
from soc.zm_hp import CPU_BASE, WishboneHP, hp_interface
from soc.zm_simaxi import ZMSimAXIRAM
from soc.zm_video_snoop import ZMVideoSnoop

Sim = Generator[object, None, None]
SIZE = 1 << 16
LATENCY = 8  # the model's first-beat latency
SLOW = 6  # the write channel takes a store every SLOW cycles: a burst of stores backs up
VBASE = CPU_BASE + 0x8000  # where this bench puts HW_VIDEO_BASE


class Bench(Module):
    """The bridge on a DDR model whose write channel takes a store only one cycle in `SLOW`, so
    a burst of stores backs up in the buffer, as it does behind a busy DDR."""

    def __init__(self, posted: int = 8) -> None:
        self.cpu = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.hp, ddr = hp_interface(), hp_interface()
        self.submodules.bridge = WishboneHP(self.cpu, self.hp, posted)
        self.submodules.ram = ZMSimAXIRAM(SIZE, [ddr], latency=LATENCY, wr32=True)
        tick, slot = Signal(max=SLOW), Signal()
        self.sync += tick.eq(Mux(tick == SLOW - 1, 0, tick + 1))
        self.comb += [
            slot.eq(tick == 0),
            self.hp.connect(ddr),
            ddr.aw.valid.eq(self.hp.aw.valid & slot), self.hp.aw.ready.eq(ddr.aw.ready & slot),
            ddr.w.valid.eq(self.hp.w.valid & slot), self.hp.w.ready.eq(ddr.w.ready & slot),
        ]  # fmt: skip
        self.submodules.snoop = ZMVideoSnoop(self.cpu, None, Signal(32, reset=VBASE), Signal(16, reset=1))
        self.comb += self.snoop.hold.eq(0)
        self.drained = Signal()
        self.comb += self.drained.eq(zm_video_snoop.drained(self.snoop, self.bridge.idle))
        self.acks = 0  # stores acknowledged


def access(b: Bench, addr: int, value: int | None = None, cti: int = 0) -> Sim:
    """One Wishbone beat; returns (read data, cycles until the acknowledge)."""
    bus = b.cpu
    yield bus.adr.eq(addr >> 2)
    yield bus.cti.eq(cti)
    yield bus.we.eq(value is not None)
    yield bus.dat_w.eq(value or 0)
    yield bus.sel.eq(0xF)
    yield bus.cyc.eq(1)
    yield bus.stb.eq(1)
    yield
    n = 1
    while not (yield bus.ack):
        yield
        n += 1
    data = yield bus.dat_r
    yield bus.cyc.eq(0)
    yield bus.stb.eq(0)
    if value is not None:
        b.acks += 1
    yield
    return data, n


def ddr_word(b: Bench, addr: int) -> Sim:
    mem = next(x for x in b.ram._fragment.specials if isinstance(x, Memory))  # the model keeps no handle
    off = addr - CPU_BASE
    word = yield mem[off // 8]
    return (word >> (32 * ((off // 4) % 2))) & 0xFFFFFFFF


def test_a_posted_store_is_acknowledged_before_its_write_response_and_a_blocking_one_after() -> None:
    cycles = {}
    for posted in (8, 0):
        b = Bench(posted)

        def cpu(b: Bench = b, posted: int = posted) -> Sim:
            _, cycles[posted] = yield from access(b, CPU_BASE + 0x100, 0x1234)

        run_simulation(b, [cpu()])
    assert cycles[8] <= 2 < SLOW <= cycles[0]


def test_loads_after_a_backlog_of_stores_see_every_one_of_them() -> None:
    b, got = Bench(), []
    addrs = [CPU_BASE + 0x200 + 4 * i for i in range(12)]  # more than the buffer: some wait for room

    def cpu() -> Sim:
        for i, a in enumerate(addrs):
            yield from access(b, a, 0xA000 + i)
        for a in reversed(addrs):  # the last store first: still buffered when the load comes
            got.append((yield from access(b, a))[0])

    run_simulation(b, [cpu()])
    assert got == [0xA000 + i for i in reversed(range(12))]


def test_a_line_refill_after_stores_to_that_line_returns_them() -> None:
    b, got = Bench(), []
    line = CPU_BASE + 0x400

    def cpu() -> Sim:
        for i in range(8):
            yield from access(b, line + 4 * i, 0xB0 + i)
        for i in range(8):  # VexRiscv's refill: an incrementing burst, the last beat cti 111
            got.append((yield from access(b, line + 4 * i, cti=0b111 if i == 7 else 0b010))[0])

    run_simulation(b, [cpu()])
    assert got == [0xB0 + i for i in range(8)]


def test_idle_stays_low_until_every_buffered_store_is_in_ddr() -> None:
    b, bad = Bench(), []
    addrs = [CPU_BASE + 0x600 + 4 * i for i in range(10)]

    def cpu() -> Sim:
        for i, a in enumerate(addrs):
            yield from access(b, a, 0xC00 + i)

    def check() -> Sim:
        for _ in range(400):
            if (yield b.bridge.idle):
                for i, a in enumerate(addrs[: b.acks]):
                    if (yield from ddr_word(b, a)) != 0xC00 + i:
                        bad.append(a)
            yield

    run_simulation(b, [cpu(), check()])
    assert bad == [] and b.acks == len(addrs)


def _reads_do_not_wait(self: WishboneHP, depth: int) -> None:  # the mutant: no `wbusy` from the buffer
    from soc.zm_hp import AW_CACHE, SIZE_4, PostedStores, ddr_word_addr
    from migen import If

    self.stores = PostedStores(self.bus, self.hp, self.req, depth, word_addr=ddr_word_addr, size=SIZE_4,
                               cache=AW_CACHE)  # fmt: skip
    self.comb += self.idle.eq(self.stores.idle)
    self.sync += If(self.stores.push, self.ack.eq(1))


def test_board_bug_reads_that_overtake_the_buffer_return_stale_ddr(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(WishboneHP, "_posted", _reads_do_not_wait)
    b, got = Bench(), []
    addrs = [CPU_BASE + 0x200 + 4 * i for i in range(6)]

    def cpu() -> Sim:
        for i, a in enumerate(addrs):
            yield from access(b, a, 0xA000 + i)
        got.append((yield from access(b, addrs[-1]))[0])

    run_simulation(b, [cpu()])
    assert got != [0xA005]  # the guard in WishboneHP._posted is what makes the load right


def _drained_cases(b: Bench, out: list[int]) -> Sim:
    """Every cycle `drained` is high, each acknowledged store to the video region is in DDR."""
    addrs = [VBASE + 4 * i for i in range(6)]

    def cpu() -> Sim:
        for i, a in enumerate(addrs):
            yield from access(b, a, 0xD00 + i)

    def check() -> Sim:
        for _ in range(300):
            if (yield b.drained):
                for i, a in enumerate(addrs[: b.acks]):
                    if (yield from ddr_word(b, a)) != 0xD00 + i:
                        out.append(a)
            yield

    return cpu(), check()


def test_drained_waits_for_posted_stores_to_reach_ddr() -> None:
    b, stale = Bench(), []
    run_simulation(b, [*_drained_cases(b, stale)])
    assert stale == []


def test_board_bug_drained_on_the_snoop_alone_lets_the_compositor_read_stale_ddr(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(zm_video_snoop, "drained", lambda snoop, idle: snoop.empty)  # the old term
    b, stale = Bench(), []
    run_simulation(b, [*_drained_cases(b, stale)])
    assert stale != []


class Tap(Module):
    def __init__(self) -> None:
        self.dbus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.idle = Signal()
        self.submodules.tap = ZMBlitTap(self.dbus, Signal(32, reset=VBASE), stores_idle=self.idle)


def test_a_blitter_start_waits_in_the_tap_until_the_stores_have_drained() -> None:
    t, seen = Tap(), {"early": 0, "fired": 0, "pending": 0}

    def cpu() -> Sim:
        d = t.dbus
        for sig, v in ((d.adr, BLIT_WINDOW >> 2), (d.dat_w, 0x02), (d.sel, 1), (d.we, 1), (d.cyc, 1), (d.stb, 1),
                       (d.ack, 1)):  # fmt: skip
            yield sig.eq(v)
        yield
        for sig in (d.cyc, d.stb, d.ack):
            yield sig.eq(0)
        for _ in range(20):  # the bridge still has stores in flight
            seen["early"] += yield t.tap.we
            seen["pending"] += yield t.tap.pending
            yield
        yield t.idle.eq(1)
        for _ in range(5):
            if (yield t.tap.we):
                seen["fired"] = ((yield t.tap.waddr), (yield t.tap.be), (yield t.tap.wdata))
            yield

    run_simulation(t, [cpu()])
    assert seen["early"] == 0 and seen["pending"] >= 19 and seen["fired"] == (0, 0b0001, 0x02)
