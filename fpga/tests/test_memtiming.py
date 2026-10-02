"""The memory-path timing model (soc/zm_memtiming.py) in Migen's simulator: each
parameter adds exactly the cycles it says, and data still goes through."""

from __future__ import annotations

import sys
from collections.abc import Generator
from pathlib import Path

import pytest
from litex.soc.interconnect import wishbone
from migen import Module, Signal, run_simulation

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import mempath_cfg  # after the path insert: tools/ is not a package

from soc.zm_memtiming import CFG, ZMMemTiming

Sim = Generator[object, None, None]


class Bench(Module):
    def __init__(self, **params: int) -> None:
        words = sum(params.get(k, 0) << (32 * i) for i, k in enumerate(CFG))
        self.bus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        ram_bus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.submodules.ram = wishbone.SRAM(1024, bus=ram_bus)
        self.submodules.timing = ZMMemTiming(self.bus, ram_bus, Signal(512, reset=words))


def access(bus: wishbone.Interface, adr: int, we: int, dat: int, cti: int, out: list[int]) -> Sim:
    """One beat; appends the cycles from strobe to ack, then the data read."""
    yield bus.cyc.eq(1)
    yield bus.stb.eq(1)
    yield bus.adr.eq(adr)
    yield bus.we.eq(we)
    yield bus.sel.eq(0xF)
    yield bus.dat_w.eq(dat)
    yield bus.cti.eq(cti)
    n = 0
    while True:
        yield
        n += 1
        if (yield bus.ack):
            break
    out += [n, (yield bus.dat_r)]


def idle(bus: wishbone.Interface, cycles: int = 1) -> Sim:
    yield bus.cyc.eq(0)
    yield bus.stb.eq(0)
    for _ in range(cycles):
        yield


def run(bench: Bench, beats: list[tuple[int, int, int, int]], gap: int = 1) -> list[int]:
    """beats: (adr, we, dat, cti); a burst's beats follow each other with cyc held."""
    out: list[int] = []

    def gen() -> Sim:
        for adr, we, dat, cti in beats:
            yield from access(bench.bus, adr, we, dat, cti, out)
            if cti in (0, 7):
                yield from idle(bench.bus, gap)

    run_simulation(bench, gen())
    return out[0::2]


BASE = 2  # strobe to ack seen, through the SRAM's registered ack: the sim's own cost


def test_all_zero_config_costs_only_the_srams_own_cycles() -> None:
    assert run(Bench(), [(0, 0, 0, 0), (1, 1, 0, 0)]) == [BASE, BASE]


def test_read_latency_is_added_once_per_access_not_per_burst_beat() -> None:
    burst = [(8 + i, 0, 0, 2) for i in range(7)] + [(15, 0, 0, 7)]
    base = run(Bench(), burst)
    slow = run(Bench(rd_lat=5), burst)
    assert slow[0] == base[0] + 5
    assert slow[1:] == base[1:]


def test_unbuffered_store_waits_its_write_latency() -> None:
    assert run(Bench(wr_lat=7), [(0, 1, 1, 0)]) == [BASE + 7]


def test_store_buffer_full_stalls_until_an_entry_drains() -> None:
    stores = [(i, 1, i, 0) for i in range(3)]
    cycles = run(Bench(rd_lat=9, wr_lat=9, sb_depth=2, sb_drain=10), stores)
    assert cycles[:2] == [BASE, BASE]  # posted at once
    assert cycles[2] > 5  # waits for the first entry to leave


def test_write_combining_merges_stores_to_one_line() -> None:
    line = [(i, 1, i, 0) for i in range(8)]
    cycles = run(Bench(sb_depth=1, sb_drain=50, sb_combine=1, wc_timeout=16), line)
    assert cycles == [BASE] * 8  # one entry, never full


def test_read_waits_for_the_buffer_only_when_told_to() -> None:
    beats = [(0, 1, 5, 0), (64, 0, 0, 0)]
    assert run(Bench(sb_depth=4, sb_drain=20), beats)[1] == BASE
    assert run(Bench(sb_depth=4, sb_drain=20, rd_waits_sb=1), beats)[1] > 15


def test_l2_hit_costs_the_hit_latency_after_a_miss_allocates() -> None:
    beats = [(16, 0, 0, 0), (17, 0, 0, 0), (16 + (1 << 17), 0, 0, 0)]  # miss, hit, conflict miss
    assert run(Bench(rd_lat=20, l2_on=1, l2_hit_lat=4), beats) == [BASE + 20, BASE + 4, BASE + 20]


def test_buffered_store_data_reaches_the_ram() -> None:
    out: list[int] = []
    bench = Bench(sb_depth=2, sb_drain=30)

    def gen() -> Sim:
        yield from access(bench.bus, 3, 1, 0xCAFE, 0, out)
        yield from idle(bench.bus)
        yield from access(bench.bus, 3, 0, 0, 0, out)

    run_simulation(bench, gen())
    assert out[3] == 0xCAFE


def test_memcfg_text_lists_every_word_in_cfg_order() -> None:
    lines = mempath_cfg.memcfg_text("hp_wc").split()
    assert len(lines) == len(CFG)
    assert int(lines[CFG.index("rd_lat")], 16) == mempath_cfg.HP
    assert int(lines[CFG.index("sb_combine")], 16) == 1


def test_memcfg_text_refuses_a_parameter_the_model_lacks(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setitem(mempath_cfg.MEM, "bad", {"rd_latency": 3})
    with pytest.raises(ValueError, match="rd_latency"):
        mempath_cfg.memcfg_text("bad")
