"""ZIGGY's IO stores wait for its posted DDR stores (soc/zm_io_fence.py), with the mutant
the test catches; and a load never hits a line-buffer beat fetched before a posted store."""

from __future__ import annotations

import pytest
from litex.soc.integration.soc import SoCRegion
from litex.soc.interconnect import wishbone
from migen import Module, Mux, Signal, run_simulation
from test_hp_posted import LATENCY, SIZE, SLOW, Sim, access, ddr_word

from soc.zm_hp import CPU_BASE, WishboneHP, hp_interface
from soc.zm_io_fence import IOFence
from soc.zm_simaxi import ZMSimAXIRAM

IO = 0x93000000  # SOUND_WINDOW: a doorbell another master acts on by reading DDR


def _wb() -> wishbone.Interface:
    return wishbone.Interface(data_width=32, address_width=32, addressing="word")


class Bench(Module):
    """The CPU's D-bus -> IOFence -> a decoder: main RAM (the posted bridge on a DDR whose write
    channel takes a store one cycle in SLOW) and one IO slave that acks in a cycle."""

    def __init__(self, break_: str = "") -> None:
        self.cpu, main, self.io = _wb(), _wb(), _wb()
        self.hp, ddr = hp_interface(), hp_interface()
        self.submodules.bridge = WishboneHP(main, self.hp, 8)
        self.submodules.fence = IOFence(self.cpu, self.bridge.idle, break_)
        slaves = [(lambda a: a[29] == 0, main), (lambda a: a[29] == 1, self.io)]
        self.submodules.decoder = wishbone.Decoder(self.fence.bus, slaves)
        self.sync += self.io.ack.eq(self.io.cyc & self.io.stb & ~self.io.ack)
        self.submodules.ram = ZMSimAXIRAM(SIZE, [ddr], latency=LATENCY, wr32=True)
        tick, slot = Signal(max=SLOW), Signal()
        self.sync += tick.eq(Mux(tick == SLOW - 1, 0, tick + 1))
        self.comb += [
            slot.eq(tick == 0),
            self.hp.connect(ddr),
            ddr.aw.valid.eq(self.hp.aw.valid & slot), self.hp.aw.ready.eq(ddr.aw.ready & slot),
            ddr.w.valid.eq(self.hp.w.valid & slot), self.hp.w.ready.eq(ddr.w.ready & slot),
        ]  # fmt: skip
        self.acks = 0


def _doorbell(b: Bench) -> tuple[list[int], dict[str, int]]:
    """Ten stores to DDR, then a store to IO; returns the stale words the IO slave would read
    when the doorbell reaches it, and when (cycles) the CPU saw the doorbell's ack."""
    addrs = [CPU_BASE + 0x300 + 4 * i for i in range(10)]
    stale: list[int] = []
    seen = {"rung": 0}

    def cpu() -> Sim:
        for i, a in enumerate(addrs):
            yield from access(b, a, 0xE00 + i)
        yield from access(b, IO, 1)

    def device() -> Sim:  # the other master: reads DDR when the doorbell reaches it
        for _ in range(400):
            if (yield b.io.cyc) and (yield b.io.stb) and (yield b.io.we) and not seen["rung"]:
                seen["rung"] = 1
                for i, a in enumerate(addrs):
                    if (yield from ddr_word(b, a)) != 0xE00 + i:
                        stale.append(a)
            yield

    run_simulation(b, [cpu(), device()])
    return stale, seen


def test_an_io_store_reaches_its_device_only_after_every_posted_store_is_in_ddr() -> None:
    stale, seen = _doorbell(Bench())
    assert seen["rung"] == 1 and stale == []


def test_break_without_the_fence_the_device_reads_stores_still_in_the_buffer() -> None:
    stale, seen = _doorbell(Bench("nofence"))
    assert seen["rung"] == 1 and stale != []


def test_an_io_load_is_not_held_behind_the_posted_stores() -> None:
    b, took = Bench(), {}

    def cpu() -> Sim:
        for i in range(8):
            yield from access(b, CPU_BASE + 0x500 + 4 * i, i)
        _, took["load"] = yield from access(b, IO)
        took["idle"] = yield b.bridge.idle

    run_simulation(b, [cpu()])
    assert took["load"] <= 2 and took["idle"] == 0  # answered while stores were still buffered


def test_a_slave_below_bit_31_other_than_main_ram_fails_the_build() -> None:
    regions = {"main_ram": SoCRegion(origin=CPU_BASE, size=1 << 25), "rom": SoCRegion(origin=0, size=1 << 16)}
    fence = IOFence(_wb(), Signal(), regions=regions)
    with pytest.raises(ValueError, match="rom at 0x0"):
        fence.do_finalize()


def _abandoned_burst_then_store(b: Bench) -> Sim:
    """A refill burst abandoned after one beat (its line buffer stays live), a store into that
    line, then a single load of the stored word."""
    line, bus = CPU_BASE + 0x700, b.cpu
    yield from access(b, line + 12, 0x1111)  # the old value, in DDR before the burst
    for _ in range(40):
        yield
    yield from access(b, line, cti=0b010)  # one beat of an incrementing burst; cyc then drops
    for _ in range(40):  # the AXI burst fills every beat of the buffer meanwhile
        yield
    yield from access(b, line + 12, 0x2222)
    data, _ = yield from access(b, line + 12)
    yield bus.cyc.eq(0)
    return data


def test_a_load_after_an_abandoned_burst_and_a_store_returns_the_stored_word() -> None:
    # The store's acknowledge closes the line buffer (a single beat is a burst's last:
    # WishboneHP._line_buffer), so the load misses and waits for the store to drain.
    b, got = Bench(), []

    def cpu() -> Sim:
        got.append((yield from _abandoned_burst_then_store(b)))

    run_simulation(b, [cpu()])
    assert got == [0x2222]
