"""The HP2 bridge's write bursts (soc/zm_blit_wburst.py, BlitHP `burst=N`) in Migen's simulator,
against the sim's DDR model (soc/zm_simaxi.py: it refuses a burst whose WLAST disagrees with
AWLEN, and an upsized one).

The same request streams go through the 1-beat bridge and the burst one: every read must
return the byte port order says (each access applied when the port takes it), and the DDR
must end the same. The bursts must actually form, stay inside a 4 KiB page and N beats,
and a read must never pass a write held in the open burst (its break: `alias`)."""

from __future__ import annotations

import random
from collections.abc import Generator

import pytest
from migen import Memory, Module, Signal, run_simulation

from soc.zm_blit_hp import BlitHP
from soc.zm_hp import CPU_BASE, hp_interface
from soc.zm_simaxi import ZMSimAXIRAM

Sim = Generator[object, None, None]
SIZE = 1 << 16
LIN0 = CPU_BASE + 0x1000  # the bus address of linear 0: DDR offset 0x1000
Op = tuple[str, int, int, int]  # ("w", lin, data, strb) | ("r", lin, 0, 0)


class Bridge(Module):
    def __init__(self, burst: int, break_: str = "", latency: int = 6) -> None:
        self.hp = hp_interface()
        self.submodules.mem = BlitHP(self.hp, Signal(32, reset=LIN0), Signal(reset=1), break_, burst)
        self.submodules.ram = ZMSimAXIRAM(SIZE, [self.hp], latency=latency, wr32=True, reads=8)
        self.rsp: list[int] = []
        self.aws: list[tuple[int, int]] = []  # (DDR byte address, beats)


def drive(b: Bridge, ops: list[Op], gaps: random.Random, pause: tuple[int, ...]) -> Sim:
    m = b.mem
    for kind, lin, data, strb in ops:
        valid, ready = (m.wr_req_valid, m.wr_req_ready) if kind == "w" else (m.rd_req_valid, m.rd_req_ready)
        yield valid.eq(1)
        if kind == "w":
            yield m.wr_req_addr.eq(lin)
            yield m.wr_req_data.eq(data)
            yield m.wr_req_strb.eq(strb)
        else:
            yield m.rd_req_addr.eq(lin)
        yield
        while not (yield ready):
            yield
        yield valid.eq(0)
        for _ in range(gaps.choice(pause)):
            yield


def watch(b: Bridge, cycles: int) -> Sim:
    hp = b.hp
    for _ in range(cycles):
        if (yield b.mem.rd_rsp_valid):
            b.rsp.append((yield b.mem.rd_rsp_data))
        if (yield hp.aw.valid) and (yield hp.aw.ready):
            b.aws.append(((yield hp.aw.addr), (yield hp.aw.len) + 1))
        yield


def model(ops: list[Op]) -> tuple[list[int], dict[int, int]]:
    """Port order: the byte each read must return, and the memory at the end."""
    mem: dict[int, int] = {}
    got = []
    for kind, lin, data, strb in ops:
        if kind == "w":
            for i in range(4):
                if strb >> i & 1:
                    mem[(lin & ~3) + i] = (data >> (8 * i)) & 0xFF
        else:
            got.append(mem.get(lin, 0))
    return got, mem


MIXED = (0, 0, 0, 1, 3, 12)  # clocks between requests: back to back, the pixel rate, a pause past TIMEOUT


def run(b: Bridge, ops: list[Op], seed: int = 1, cycles: int = 6000, pause: tuple[int, ...] = MIXED) -> tuple[list[int], dict[int, int]]:
    final: dict[int, int] = {}

    def end() -> Sim:
        for _ in range(cycles - 2):
            yield
        assert not (yield b.mem.wr_pending), "a write never got its B"
        ram = next(x for x in b.ram._fragment.specials if isinstance(x, Memory))  # the model keeps no handle
        for lin in {lin & ~3 for k, lin, _, _ in ops if k == "w"}:
            for i in range(4):
                off = 0x1000 + lin + i
                final[lin + i] = ((yield ram[off // 8]) >> (8 * (off % 8))) & 0xFF
        assert not (yield b.ram.error), "the DDR model saw a malformed burst"

    run_simulation(b, [drive(b, ops, random.Random(seed), pause), watch(b, cycles), end()])
    reads = [lin for k, lin, _, _ in ops if k == "r"]
    return [(w >> (8 * (lin & 3))) & 0xFF for w, lin in zip(b.rsp, reads, strict=True)], final


def stream(seed: int, n: int = 300) -> list[Op]:
    """Runs of consecutive words (whole, partial, a keyed-out gap), page crossings, jumps,
    the same word twice, and reads of bytes just written or long settled."""
    rnd, ops, lin = random.Random(seed), [], 0x0FE0
    while len(ops) < n:
        if rnd.random() < 0.2:
            lin = rnd.choice((0x0FF8, 0x1FF0, rnd.randrange(0, 0x3000) & ~3))
        for _ in range(rnd.randrange(1, 12)):
            strb = rnd.choice((0xF, 0xF, 0xF, 0x1, 0x6, 0x8, 0xC))
            if rnd.random() < 0.1:
                lin += 4  # a word the key left out: a gap in the run
            ops.append(("w", lin, rnd.getrandbits(32), strb))
            if rnd.random() < 0.15:
                ops.append(("r", lin + rnd.randrange(4), 0, 0))
            lin += 0 if rnd.random() < 0.05 else 4
        if rnd.random() < 0.3:
            ops.append(("r", rnd.randrange(0, 0x3000), 0, 0))
    return ops


@pytest.mark.parametrize("burst", [0, 4, 8])
@pytest.mark.parametrize("seed", [1, 2, 3])
def test_reads_and_the_final_ddr_follow_port_order_with_and_without_bursts(burst: int, seed: int) -> None:
    ops = stream(seed)
    want, mem = model(ops)
    got, final = run(Bridge(burst), ops, seed)
    assert got == want
    assert final == {a: mem.get(a, 0) for a in final}


def _run_words(burst: int, first: int, words: int, break_: str = "") -> Bridge:
    b = Bridge(burst, break_)
    run(b, [("w", first + 4 * i, i, 0xF) for i in range(words)], cycles=1500, pause=(3,))  # the pixel rate
    return b


@pytest.mark.parametrize("burst", [4, 8])
def test_a_run_of_words_goes_out_as_full_bursts(burst: int) -> None:
    b = _run_words(burst, 0x100, 64)
    assert [n for _, n in b.aws] == [burst] * (64 // burst)


def test_without_bursts_every_word_is_its_own_write() -> None:
    assert [n for _, n in _run_words(0, 0x100, 16).aws] == [1] * 16


def test_a_write_left_alone_goes_out_after_the_timeout_alone() -> None:
    b = Bridge(4)
    run(b, [("w", 0x40, 1, 0xF), ("w", 0x44, 2, 0xF), ("w", 0x48, 3, 0xF)], cycles=200, pause=(0, 0, 20))
    assert [n for _, n in b.aws] == [2, 1]  # the pause split the run; the last word did not wait forever


@pytest.mark.parametrize("burst", [4, 8])
def test_no_burst_crosses_a_4k_page_or_exceeds_n_beats(burst: int) -> None:
    b = _run_words(burst, 0x0FE4, 40)  # DDR 0x1FE4..: the page ends 7 words in
    for addr, n in b.aws:
        assert n <= burst
        assert addr >> 12 == (addr + 4 * n - 1) >> 12, f"burst at {addr:#x}, {n} beats, crosses a page"
    assert sum(n for _, n in b.aws) == 40
    assert any((a + 4 * n) % 4096 == 0 for a, n in b.aws)  # one ends exactly at the page


def test_a_read_of_a_word_in_the_open_burst_sees_the_write() -> None:
    ops: list[Op] = [("w", 0x200, 0x11223344, 0xF), ("w", 0x204, 0x55667788, 0x3), ("r", 0x205, 0, 0)]
    got, _ = run(Bridge(4, latency=1), ops, cycles=400)
    assert got == [0x77]


def test_with_the_alias_check_broken_the_read_passes_the_open_burst() -> None:
    ops: list[Op] = [("w", 0x200, 0x11223344, 0xF), ("w", 0x204, 0x55667788, 0x3), ("r", 0x205, 0, 0)]
    got, _ = run(Bridge(4, break_="alias", latency=1), ops, cycles=400)  # back before the burst times out
    assert got == [0x00]
