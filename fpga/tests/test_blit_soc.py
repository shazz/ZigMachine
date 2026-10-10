"""The blitter's SoC glue in Migen's simulator (soc/zm_blit_hp.py, soc/zm_blit_soc.py):
the HP2 bridge against the sim's DDR model, and the tap that turns the CPU's stores
into zm_blit's register writes. zm_blit itself is proven in test_rtl_blitter.py; the
whole path (a cart's frame hashes through it) is `make hp-sim` with ZM_BLIT=hw."""

from __future__ import annotations

from collections.abc import Generator

from litex.soc.interconnect import wishbone
from migen import Memory, Module, Signal, run_simulation

from gen import memmap as mm
from soc.zm_blit_hp import BlitHP
from soc.zm_blit_soc import BLIT_WINDOW, ZMBlitTap
from soc.zm_hp import CPU_BASE, hp_interface
from soc.zm_simaxi import ZMSimAXIRAM

Sim = Generator[object, None, None]
SIZE = 1 << 16
LIN0 = CPU_BASE + 0x1000  # the bus address of linear 0 in this bench


class Bridge(Module):
    def __init__(self, base: int = LIN0) -> None:
        self.hp = hp_interface()
        self.base, self.enable = Signal(32, reset=base), Signal(reset=1)
        self.submodules.mem = BlitHP(self.hp, self.base, self.enable)
        self.submodules.ram = ZMSimAXIRAM(SIZE, [self.hp], latency=4, wr32=True)
        self.rsp: list[int] = []


def write_byte(b: Bridge, lin: int, value: int) -> Sim:
    m = b.mem
    lane = lin & 3
    yield m.wr_req_valid.eq(1)
    yield m.wr_req_addr.eq(lin)
    yield m.wr_req_data.eq(value * 0x01010101)
    yield m.wr_req_strb.eq(1 << lane)
    yield
    while not (yield m.wr_req_ready):
        yield
    yield m.wr_req_valid.eq(0)


def read_byte(b: Bridge, lin: int) -> Sim:
    m = b.mem
    yield m.rd_req_valid.eq(1)
    yield m.rd_req_addr.eq(lin)
    yield
    while not (yield m.rd_req_ready):
        yield
    yield m.rd_req_valid.eq(0)


def collect(b: Bridge, cycles: int) -> Sim:
    for _ in range(cycles):
        if (yield b.mem.rd_rsp_valid):
            b.rsp.append((yield b.mem.rd_rsp_data))
        yield


def settle(b: Bridge) -> Sim:
    yield  # the bench's last request is taken on this clock (Migen applies a generator's writes at the edge)
    yield
    while (yield b.mem.wr_pending) or (yield b.mem.reads):
        yield


def ddr_byte(b: Bridge, lin: int) -> Sim:
    """The byte the DDR model holds where the CPU path would put bus LIN0 + lin."""
    off = LIN0 + lin - CPU_BASE
    mem = next(x for x in b.ram._fragment.specials if isinstance(x, Memory))  # the model keeps no handle
    word = yield mem[off // 8]
    return (word >> (8 * (off % 8))) & 0xFF


def test_bridge_byte_writes_land_where_the_cpu_path_maps_them() -> None:
    b, got = Bridge(), {}

    def bench() -> Sim:
        for i, lin in enumerate((0x10, 0x11, 0x16, 0x17, 0x2D)):
            yield from write_byte(b, lin, 0xA0 + i)
        yield from settle(b)
        for lin in (0x10, 0x11, 0x12, 0x16, 0x17, 0x2D):
            got[lin] = yield from ddr_byte(b, lin)

    run_simulation(b, bench())
    assert got == {0x10: 0xA0, 0x11: 0xA1, 0x12: 0, 0x16: 0xA2, 0x17: 0xA3, 0x2D: 0xA4}


def test_bridge_read_after_write_sees_it_and_lanes_come_back_in_order() -> None:
    b = Bridge()

    def bench() -> Sim:
        for lin, v in ((0x40, 0x11), (0x45, 0x22), (0x4A, 0x33)):
            yield from write_byte(b, lin, v)
        for lin in (0x40, 0x45, 0x4A):  # issued right behind the writes, all in flight
            yield from read_byte(b, lin)

    run_simulation(b, [bench(), collect(b, 200)])
    lanes = [(w >> (8 * (lin & 3))) & 0xFF for w, lin in zip(b.rsp, (0x40, 0x45, 0x4A), strict=True)]
    assert lanes == [0x11, 0x22, 0x33]


def test_bridge_wr_pending_holds_until_every_b_response() -> None:
    b, seen = Bridge(), []

    def bench() -> Sim:
        yield from write_byte(b, 0x80, 0x5A)
        for _ in range(12):
            seen.append((yield b.mem.wr_pending))
            yield

    run_simulation(b, bench())
    assert 1 in seen[:3] and seen[-1] == 0  # up after the take, down once the B came back


def test_bridge_masks_the_bus_address_to_the_32mib_ddr_window() -> None:
    b, got = Bridge(base=0x7000_0000 | (LIN0 - CPU_BASE)), []  # bits above the window are dropped

    def bench() -> Sim:
        yield from write_byte(b, 0x20, 0x77)
        yield from settle(b)
        got.append((yield from ddr_byte(b, 0x20)))

    run_simulation(b, bench())
    assert got == [0x77]


def test_bridge_with_a_wrong_base_misses_the_byte_the_cpu_sees() -> None:
    b, got = Bridge(base=LIN0 + 8), []  # the hp_sim break test `base`: one beat off

    def bench() -> Sim:
        yield from write_byte(b, 0x20, 0x77)
        yield from settle(b)
        got.append((yield from ddr_byte(b, 0x20)))

    run_simulation(b, bench())
    assert got == [0]


class Tap(Module):
    def __init__(self, vbase: int, break_: str = "") -> None:
        self.dbus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.submodules.tap = ZMBlitTap(self.dbus, Signal(32, reset=vbase), break_)
        self.got: list[tuple[int, int, int]] = []


def store(t: Tap, addr: int, value: int, sel: int) -> Sim:
    d = t.dbus
    yield d.adr.eq(addr >> 2)
    yield d.dat_w.eq(value)
    yield d.sel.eq(sel)
    yield d.we.eq(1)
    yield d.cyc.eq(1)
    yield d.stb.eq(1)
    yield d.ack.eq(1)
    yield
    yield d.cyc.eq(0)
    yield d.stb.eq(0)
    yield d.ack.eq(0)
    yield


def watch(t: Tap, cycles: int) -> Sim:
    for _ in range(cycles):
        if (yield t.tap.we):
            t.got.append(((yield t.tap.waddr), (yield t.tap.be), (yield t.tap.wdata)))
        yield


def test_tap_forwards_region_stores_masks_command_and_starts_only_from_the_window() -> None:
    vbase = CPU_BASE + 0x30_0000
    t = Tap(vbase)
    blit = vbase + mm.OFF_BLIT

    def bench() -> Sim:
        yield from store(t, blit + 0x24, 0x140, 0b0011)  # D_STRIDE: word 9
        yield from store(t, blit + 0x00, 0x00F00102, 0b1111)  # COMMAND..CON2 as one word
        yield from store(t, vbase + 0x7C, 0x1234, 0b1111)  # the word below the block: not ours
        yield from store(t, blit + 0x60, 99, 0b1111)  # CYCLES: read-only, not forwarded
        yield from store(t, BLIT_WINDOW, 0x02, 0b0001)  # the start

    run_simulation(t, [bench(), watch(t, 40)])
    assert t.got == [(9, 0b0011, 0x140), (0, 0b1110, 0x00F00102), (0, 0b0001, 0x02)]


def test_tap_drop_mutant_loses_the_d_stride_store() -> None:
    vbase = CPU_BASE + 0x30_0000
    t = Tap(vbase, break_="drop")  # the hp_sim break test `drop`

    def bench() -> Sim:
        yield from store(t, vbase + mm.OFF_BLIT + 0x24, 0x140, 0b0011)
        yield from store(t, vbase + mm.OFF_BLIT + 0x28, 0x10, 0b0011)

    run_simulation(t, [bench(), watch(t, 20)])
    assert t.got == [(10, 0b0011, 0x10)]
