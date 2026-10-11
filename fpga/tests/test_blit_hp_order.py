"""The blitter's HP2 bridge with several requests in flight (soc/zm_blit_hp.py), and the
DDR model that lets it (soc/zm_simaxi.py `reads`), in Migen's simulator.

The ordering rule the bridge adds to AXI: a read waits for the B of a write in flight that
covers its byte, and only for that one. Each rule has its break (`break_`) and a test
that requires the break to show."""

from __future__ import annotations

from collections.abc import Generator

from migen import Module, Signal, run_simulation

from soc.zm_blit_hp import BlitHP
from soc.zm_hp import hp_interface
from soc.zm_simaxi import ZMSimAXIRAM
from test_blit_soc import LIN0, SIZE, collect, read_byte, write_byte

Sim = Generator[object, None, None]


class Bridge(Module):
    def __init__(self, break_: str = "", reads: int = 8, latency: int = 8) -> None:
        self.hp = hp_interface()
        self.base, self.enable = Signal(32, reset=LIN0), Signal(reset=1)
        self.submodules.mem = BlitHP(self.hp, self.base, self.enable, break_)
        self.submodules.ram = ZMSimAXIRAM(SIZE, [self.hp], latency=latency, wr32=True, reads=reads)
        self.rsp: list[int] = []
        self.events: list[tuple[int, str]] = []  # (cycle, "ar" | "b" | "r")


def watch(b: Bridge, cycles: int) -> Sim:
    """Records each AR, B and R handshake on the port, by cycle."""
    hp = b.hp
    for t in range(cycles):
        for name, ch in (("ar", hp.ar), ("b", hp.b), ("r", hp.r)):
            if (yield ch.valid) and (yield ch.ready):
                b.events.append((t, name))
        yield


def first(b: Bridge, name: str) -> int:
    return next(t for t, n in b.events if n == name)


def _write_then_read(b: Bridge, w_lin: int, r_lin: int) -> Sim:
    yield from write_byte(b, w_lin, 0x5A)
    yield from read_byte(b, r_lin)


def _run(b: Bridge, w_lin: int, r_lin: int) -> None:
    run_simulation(b, [_write_then_read(b, w_lin, r_lin), watch(b, 80), collect(b, 80)])


def test_a_read_of_a_byte_a_write_in_flight_covers_waits_for_that_write_b() -> None:
    b = Bridge()
    _run(b, 0x40, 0x40)
    assert first(b, "ar") > first(b, "b")
    assert [(w >> 0) & 0xFF for w in b.rsp] == [0x5A]


def test_with_the_alias_check_broken_the_read_leaves_before_the_write_has_landed() -> None:
    b = Bridge(break_="alias")
    _run(b, 0x40, 0x40)
    assert first(b, "ar") < first(b, "b")


def test_a_read_of_another_byte_of_the_word_passes_the_write_in_flight() -> None:
    b = Bridge()
    _run(b, 0x40, 0x41)  # same 32-bit word, a byte the write's strobe does not cover
    assert first(b, "ar") < first(b, "b")


def _fill_then_read(b: Bridge, lins: list[int]) -> Sim:
    for i, lin in enumerate(lins):
        yield from write_byte(b, lin, 0x10 + i)
    for _ in range(40):  # every write lands before the reads start
        yield
    for lin in lins:
        yield from read_byte(b, lin)


def _flight(b: Bridge, cycles: int, most: list[int]) -> Sim:
    for _ in range(cycles):
        most[0] = max(most[0], (yield b.mem.reads))
        yield


def _reads_in_order(break_: str) -> tuple[list[int], int]:
    b, most = Bridge(break_), [0]
    lins = [0x100, 0x104, 0x10B, 0x111, 0x116, 0x11C, 0x120, 0x127]  # alternate halves of the 64-bit beats
    run_simulation(b, [_fill_then_read(b, lins), collect(b, 400), _flight(b, 400, most)])
    return [(w >> (8 * (lin & 3))) & 0xFF for w, lin in zip(b.rsp, lins, strict=True)], most[0]


def test_reads_go_out_back_to_back_several_in_flight_and_come_back_in_order() -> None:
    got, most = _reads_in_order("")
    assert got == [0x10 + i for i in range(8)]
    assert most >= 6  # the DDR model's 8-cycle latency is paid once, not per read


def test_with_the_halves_paired_out_of_order_the_bytes_come_back_wrong() -> None:
    got, _ = _reads_in_order("order")
    assert got != [0x10 + i for i in range(8)]


class Port(Module):
    """A bare AXI master on the DDR model: ARs, the R stream."""

    def __init__(self, reads: int) -> None:
        self.hp = hp_interface()
        self.submodules.ram = ZMSimAXIRAM(SIZE, [self.hp], latency=10, wr32=True, reads=reads)
        self.beats: list[int] = []


def _ars(p: Port, n: int) -> Sim:
    hp = p.hp
    yield hp.r.ready.eq(1)
    for i in range(n):
        yield hp.ar.valid.eq(1)
        yield hp.ar.addr.eq(0x0400_0000 + 0x40 * i)
        yield hp.ar.len.eq(1)  # two beats
        yield
        while not (yield hp.ar.ready):
            yield
    yield hp.ar.valid.eq(0)


def _beats(p: Port, cycles: int) -> Sim:
    for t in range(cycles):
        if (yield p.hp.r.valid) and (yield p.hp.r.ready):
            p.beats.append(t)
        yield


def test_the_ddr_model_with_reads_pays_the_latency_once_for_back_to_back_bursts() -> None:
    p = Port(reads=4)
    run_simulation(p, [_ars(p, 4), _beats(p, 100)])
    assert len(p.beats) == 8
    assert p.beats[-1] - p.beats[0] == 7  # eight beats in eight cycles: no latency between bursts


def test_the_ddr_model_with_one_read_answers_one_burst_at_a_time() -> None:
    p = Port(reads=1)
    run_simulation(p, [_ars(p, 4), _beats(p, 200)])
    assert len(p.beats) == 8
    assert p.beats[-1] - p.beats[0] > 3 * 10  # each burst waits its own latency
