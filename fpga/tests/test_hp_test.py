"""The hp-test bitstream's logic (soc/zm_hp_test*.py) in Migen's simulator, against the
board-memory sim's DDR model (soc/zm_simaxi.py): the GP0 registers as U-Boot drives them,
the raw AXI engine, and the board's own bridges run from registers."""

from __future__ import annotations

from collections.abc import Generator

from litex.soc.interconnect import axi
from migen import Constant, Module, run_simulation

from soc.zm_hp import DDR_BASE, hp_interface
from soc.zm_hp_test import BANK, CTRL_BRIDGE, CTRL_CHECK, CTRL_LINE, CTRL_WRITE, GLOBAL, HPPort, bank_base
from soc.zm_hp_test_regs import GP0Regs, gp0_interface
from soc.zm_hp_test_stats import NO_BAD
from soc.zm_simaxi import ZMSimAXIRAM

Sim = Generator[object, None, None]
SIZE = 1 << 16
GO = 1


class Bench(Module):
    """One port behind GP0 registers, the PS's DDR modelled; `wr32`: the board's 32-bit write channel."""

    def __init__(self, port: int = 0, wr32: bool = False) -> None:
        self.gp0, self.hp = gp0_interface(), hp_interface()
        self.submodules.regs = GP0Regs(self.gp0)
        self.regs.status(GLOBAL["ID"], Constant(0x48505431, 32))
        self.submodules.port = HPPort(self.regs, port, self.hp)
        self.submodules.ram = ZMSimAXIRAM(SIZE, [self.hp], latency=5, base=DDR_BASE, wr32=wr32)


def mw(gp0: axi.AXIInterface, addr: int, value: int) -> Sim:
    """U-Boot's `mw.l`: one AXI3 write beat on GP0."""
    for sig, v in ((gp0.aw.valid, 1), (gp0.aw.addr, addr), (gp0.aw.len, 0), (gp0.aw.size, 2), (gp0.aw.burst, 1),
                   (gp0.aw.id, 7), (gp0.w.valid, 1), (gp0.w.data, value), (gp0.w.strb, 0xF), (gp0.w.last, 1),
                   (gp0.b.ready, 1)):  # fmt: skip
        yield sig.eq(v)
    aw_done = w_done = False
    while not (aw_done and w_done):
        yield
        aw_done = aw_done or bool((yield gp0.aw.ready))
        w_done = w_done or bool((yield gp0.w.ready))
        if aw_done:
            yield gp0.aw.valid.eq(0)
        if w_done:
            yield gp0.w.valid.eq(0)
    while not (yield gp0.b.valid):
        yield
    assert (yield gp0.b.id) == 7
    yield


def md(gp0: axi.AXIInterface, addr: int) -> Sim:
    """U-Boot's `md.l` of one word."""
    for sig, v in ((gp0.ar.valid, 1), (gp0.ar.addr, addr), (gp0.ar.len, 0), (gp0.ar.size, 2), (gp0.ar.burst, 1),
                   (gp0.ar.id, 3), (gp0.r.ready, 1)):  # fmt: skip
        yield sig.eq(v)
    yield
    while not (yield gp0.ar.ready):
        yield
    yield gp0.ar.valid.eq(0)
    while not (yield gp0.r.valid):
        yield
    data = yield gp0.r.data
    yield
    return data


def reg(port: int, name: str) -> int:
    return 0x43C0_0000 + 4 * (bank_base(port) + BANK[name])


def run_and_wait(bench: Bench, port: int, ctrl: int) -> Sim:
    yield from mw(bench.gp0, reg(port, "CTRL"), ctrl | GO)
    for _ in range(4000):
        if (yield from md(bench.gp0, reg(port, "STATUS"))) & 0b10:
            return
    raise AssertionError("the run never finished")


def program(bench: Bench, port: int, **fields: int) -> Sim:
    for name, value in fields.items():
        yield from mw(bench.gp0, reg(port, name.upper()), value)


def results(bench: Bench, port: int) -> Sim:
    out = {}
    for name in ("STATUS", "BEATS", "ERRS", "BADIDX", "D0LO", "D0HI"):
        out[name] = yield from md(bench.gp0, reg(port, name))
    return out


def test_gp0_reads_the_id_and_a_written_register_back() -> None:
    bench, got = Bench(), []

    def flow() -> Sim:
        got.append((yield from md(bench.gp0, 0x43C0_0000)))
        yield from mw(bench.gp0, reg(0, "SEED"), 0xDEADBEEF)
        got.append((yield from md(bench.gp0, reg(0, "SEED"))))

    run_simulation(bench, flow())
    assert got == [0x48505431, 0xDEADBEEF]


def test_raw_write_then_checked_read_of_four_16_beat_bursts_has_no_errors() -> None:
    bench, got = Bench(), {}

    def flow() -> Sim:
        yield from program(bench, 0, addr=DDR_BASE + 0x400, len=15, size=3, count=4, seed=0x100)
        yield from run_and_wait(bench, 0, 1 << CTRL_WRITE)
        yield from run_and_wait(bench, 0, 1 << CTRL_CHECK)
        got.update((yield from results(bench, 0)))

    run_simulation(bench, flow())
    assert got == {"STATUS": 0b10, "BEATS": 64, "ERRS": 0, "BADIDX": NO_BAD, "D0LO": 0x100, "D0HI": 0x101}


def test_raw_checked_read_outside_the_ddr_window_counts_every_beat_as_an_error() -> None:
    bench, got = Bench(), {}

    def flow() -> Sim:
        yield from program(bench, 0, addr=DDR_BASE + SIZE, len=3, size=3, count=2)
        yield from run_and_wait(bench, 0, 1 << CTRL_CHECK)
        got.update((yield from results(bench, 0)))

    run_simulation(bench, flow())
    assert (got["BEATS"], got["ERRS"], got["BADIDX"]) == (8, 8, 0)


def test_raw_8_byte_beats_on_a_32_bit_write_channel_lose_the_upper_word() -> None:
    # The board's first picture (soc/zm_hp.py "WR32"): the read-back check finds every beat wrong.
    bench, got = Bench(wr32=True), {}

    def flow() -> Sim:
        yield from program(bench, 0, addr=DDR_BASE, len=1, size=3, count=1, seed=0x20, cache=0)
        yield from run_and_wait(bench, 0, 1 << CTRL_WRITE)
        yield from run_and_wait(bench, 0, 1 << CTRL_CHECK)
        got.update((yield from results(bench, 0)))

    run_simulation(bench, flow())
    assert (got["ERRS"], got["D0LO"], got["D0HI"]) == (2, 0x20, 0)


def test_hp0_bridge_line_refill_reads_the_words_it_stored() -> None:
    bench, got = Bench(port=0, wr32=True), {}

    def flow() -> Sim:
        yield from program(bench, 0, addr=DDR_BASE + 0x200, count=16, seed=0x40)
        yield from run_and_wait(bench, 0, (1 << CTRL_BRIDGE) | (1 << CTRL_WRITE))
        yield from run_and_wait(bench, 0, (1 << CTRL_BRIDGE) | (1 << CTRL_LINE) | (1 << CTRL_CHECK))
        got.update((yield from results(bench, 0)))

    run_simulation(bench, flow())
    assert (got["BEATS"], got["ERRS"], got["D0LO"]) == (16, 0, 0x40)


def test_hp1_video_bridge_row_write_then_read_round_trips_on_the_32_bit_channel() -> None:
    bench, got = Bench(port=1, wr32=True), {}

    def flow() -> Sim:
        yield from program(bench, 1, addr=DDR_BASE + 0x1000, count=40, seed=0x7000, cache=0)
        yield from run_and_wait(bench, 1, (1 << CTRL_BRIDGE) | (1 << CTRL_WRITE))
        yield from run_and_wait(bench, 1, (1 << CTRL_BRIDGE) | (1 << CTRL_CHECK))
        got.update((yield from results(bench, 1)))

    run_simulation(bench, flow())
    assert (got["BEATS"], got["ERRS"], got["D0LO"], got["D0HI"]) == (40, 0, 0x7000, 0x7001)
