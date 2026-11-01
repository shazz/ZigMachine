"""The QUEUE's SoC glue in Migen's simulator (soc/zm_blit_soc.py): the tap feeding the CPU's
stores to the ring into zm_blit's ring port and the list's range in the GO word, and
BLIT_WINDOW holding a read while a kick copies the block (the firmware's barrier after GO).
zm_blit itself, the queue included, is proven in test_rtl_blitter.py."""

from __future__ import annotations

from collections.abc import Generator

from litex.soc.interconnect import wishbone
from migen import Module, Signal, run_simulation

from gen import memmap as mm
from soc.zm_blit_soc import BLIT_WINDOW, BlitWindow
from soc.zm_hp import CPU_BASE
from test_blit_soc import Tap, store, watch

Sim = Generator[object, None, None]
VBASE = CPU_BASE + 0x30_0000
RING = VBASE + mm.OFF_BLIT_QUEUE


def ring_watch(t: Tap, cycles: int, got: list[tuple[int, int, int]]) -> Sim:
    for _ in range(cycles):
        if (yield t.tap.q_we):
            got.append(((yield t.tap.q_waddr), (yield t.tap.q_be), (yield t.tap.q_wdata)))
        yield


def test_tap_forwards_ring_stores_by_word_index_and_only_to_the_ring_port() -> None:
    t, ring = Tap(VBASE), []

    def bench() -> Sim:
        yield from store(t, RING, 0x0200_0C00, 0b1111)  # word 0: a FILL header
        yield from store(t, RING + 4 * 511 + 2, 0xBEEF << 16, 0b1100)  # the last word, upper half
        yield from store(t, RING + 4 * 512, 0x1234, 0b1111)  # one past the ring: not ours
        yield from store(t, RING - 4, 0x1234, 0b1111)  # one below

    run_simulation(t, [bench(), ring_watch(t, 40, ring), watch(t, 40)])
    assert ring == [(0, 0b1111, 0x0200_0C00), (511, 0b1100, 0xBEEF << 16)]
    assert t.got == []  # nothing reached the register port


def test_tap_ring_mutant_loses_the_list() -> None:
    t, ring = Tap(VBASE, break_="ring"), []

    def bench() -> Sim:
        yield from store(t, RING + 8, 0x0200_0000, 0b1111)

    run_simulation(t, [bench(), ring_watch(t, 20, ring)])
    assert ring == []


def test_go_word_carries_the_lists_range_past_the_command_lane() -> None:
    t = Tap(VBASE)
    word = mm.BLIT_CMD_QUEUE | 100 << 8 | 37 << 17

    def bench() -> Sim:
        yield from store(t, RING + 4 * 100, 0x0200_0000, 0b1111)
        yield from store(t, BLIT_WINDOW, word, 0b1111)

    run_simulation(t, [bench(), watch(t, 40)])
    assert t.got == [(0, 0b0001, word)]  # COMMAND's lane only, the whole word for the range


class Window(Module):
    def __init__(self, break_: str = "") -> None:
        self.bus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.hold, self.busy = Signal(), Signal()
        self.submodules.win = BlitWindow(self.bus, Signal(32), self.busy, self.hold, break_)


def access(w: Window, we: int, log: list[int], at: list[int]) -> Sim:
    """One bus access; the clock it was acked on goes to `log`."""
    b = w.bus
    yield b.adr.eq(0)
    yield b.we.eq(we)
    yield b.cyc.eq(1)
    yield b.stb.eq(1)
    yield
    while not (yield b.ack):
        at[0] += 1
        yield
    log.append(at[0])
    yield b.cyc.eq(0)
    yield b.stb.eq(0)
    yield


def held_read(break_: str) -> tuple[list[int], list[int]]:
    w, reads, writes, at = Window(break_), [], [], [0]

    def bench() -> Sim:
        yield w.hold.eq(1)  # a kick is copying the block
        yield from access(w, 1, writes, [0])  # GO: acked at once
        yield from access(w, 0, reads, at)

    def release() -> Sim:
        for _ in range(12):
            yield
        yield w.hold.eq(0)

    run_simulation(w, [bench(), release()])
    return reads, writes


def test_window_read_waits_for_the_copy_and_a_write_does_not() -> None:
    reads, writes = held_read("")
    assert writes[0] <= 1  # the registered ack: the next clock
    assert reads[0] >= 8  # answered only after the hold fell


def test_window_nohold_mutant_answers_the_read_during_the_copy() -> None:
    reads, _ = held_read("nohold")
    assert reads[0] <= 1
