"""The video pipeline's SoC side in Migen's simulator: the snoop that carries the
cart's stores to the compositor (soc/zm_video_snoop.py), the burst DMA
(soc/zm_video_dma.py) and the shared sim RAM (soc/zm_simram.py)."""

from __future__ import annotations

from collections.abc import Generator

from litex.soc.interconnect import wishbone
from migen import Module, Signal, run_simulation

from gen import memmap as mm
from soc.zm_simram import ZMSimRAM
from soc.zm_video_dma import CTI_END, CTI_INCR, ZMVideoDMA, read_port, write_port
from soc.zm_video_snoop import DEPTH, ZMVideoSnoop

Sim = Generator[object, None, None]
VBASE = 0x40300000  # a region at a bus address, as the firmware sets it


class SnoopBench(Module):
    def __init__(self, drain: int) -> None:
        word32 = {"data_width": 32, "address_width": 32, "addressing": "word"}
        self.cpu, ram = wishbone.Interface(**word32), wishbone.Interface(**word32)
        self.submodules.ram = wishbone.SRAM(
            4096, bus=ram, read_only=False, write_only=False
        )  # the snoop decodes the full address; the RAM may alias
        self.submodules.snoop = ZMVideoSnoop(self.cpu, ram, Signal(32, reset=VBASE), Signal(16, reset=drain))


def store(bus: wishbone.Interface, byte_addr: int, value: int, sel: int = 0xF) -> Sim:
    """One store; returns after its ack (the CPU's view)."""
    yield bus.adr.eq(byte_addr >> 2)
    yield bus.dat_w.eq(value)
    yield bus.sel.eq(sel)
    yield bus.we.eq(1)
    yield bus.cyc.eq(1)
    yield bus.stb.eq(1)
    yield
    while not (yield bus.ack):
        yield
    yield bus.cyc.eq(0)
    yield bus.stb.eq(0)


def delivered(bench: SnoopBench, stores: list[tuple[int, int]], cycles: int = 400) -> tuple[list[tuple], list[int]]:
    """(waddr, be, data) the compositor saw, and the cycle each store was acked."""
    seen: list[tuple] = []
    acked: list[int] = []

    def cpu() -> Sim:
        for addr, value in stores:
            yield from store(bench.cpu, addr, value)
            acked.append(len(seen))

    def watch() -> Sim:
        for _ in range(cycles):
            if (yield bench.snoop.we):
                seen.append(
                    (
                        (yield bench.snoop.waddr),
                        (yield bench.snoop.be),
                        (yield bench.snoop.wdata),
                        (yield bench.snoop.sel),
                    )
                )
            yield

    run_simulation(bench, [cpu(), watch()])
    return seen, acked


def test_snoop_delivers_register_palette_and_beam_stores_in_order() -> None:
    stores = [(VBASE + 0x04, 0x11), (VBASE + mm.OFF_PAL + 8, 0x22), (VBASE + mm.OFF_BEAM_TABLE + 4, 0x33)]
    seen, _ = delivered(SnoopBench(drain=1), stores)
    # with the compositor's selects decoded: register block 1, palettes 2, BEAM table 4
    want = [(1, 0xF, 0x11, 1), ((mm.OFF_PAL + 8) // 4, 0xF, 0x22, 2), ((mm.OFF_BEAM_TABLE + 4) // 4, 0xF, 0x33, 4)]
    assert seen == want


def test_snoop_ignores_framebuffers_and_memory_outside_the_region() -> None:
    # the blitter's registers (0x80..0xFF) are not the compositor's either
    stores = [(VBASE + mm.OFF_VRAM, 1), (VBASE + mm.OFF_PFB, 2), (VBASE - 4, 3), (VBASE + 0x80, 5), (VBASE + 0x30, 4)]
    seen, _ = delivered(SnoopBench(drain=1), stores)
    assert seen == [(0x30 // 4, 0xF, 4, 1)]


def test_snoop_delivers_at_the_drain_rate_and_stalls_the_cpu_when_full() -> None:
    n = DEPTH + 8
    stores = [(VBASE + mm.OFF_PAL + 4 * i, i) for i in range(n)]
    seen, acked = delivered(SnoopBench(drain=8), stores, cycles=8 * n + 64)
    assert [s[2] for s in seen] == list(range(n))  # nothing lost, nothing reordered
    # Past DEPTH queued stores the CPU waits for the queue: its last store is acked
    # only once the queue has delivered at least n - DEPTH - 1 of them.
    assert acked[-1] >= n - DEPTH - 1


class DmaBench(Module):
    def __init__(self) -> None:
        self.scan, self.comp, self.wr = read_port("sc"), read_port("rd"), write_port("wr")
        self.submodules.dma = ZMVideoDMA([self.scan, self.comp], self.wr)
        self.bus = self.dma.bus  # a memory that answers every beat at once with its address
        self.comb += [self.bus.ack.eq(self.bus.cyc & self.bus.stb), self.bus.dat_r.eq(self.bus.adr)]


def test_dma_serves_a_read_request_as_one_incrementing_burst() -> None:
    bench, beats = DmaBench(), []

    def gen() -> Sim:
        yield bench.comp.req_valid.eq(1)
        yield bench.comp.req_addr.eq(0x1000)
        yield bench.comp.req_len.eq(4)
        yield
        yield bench.comp.req_valid.eq(0)
        for _ in range(8):
            if (yield bench.comp.rsp_valid):
                beats.append(((yield bench.comp.rsp_data), (yield bench.bus.cti)))
            yield

    run_simulation(bench, gen())
    assert beats == [(0x200, CTI_INCR), (0x201, CTI_INCR), (0x202, CTI_INCR), (0x203, CTI_END)]


def test_dma_gives_the_scanout_priority_over_the_compositor() -> None:
    bench, order = DmaBench(), []

    def gen() -> Sim:
        for port, addr in ((bench.comp, 0x100), (bench.scan, 0x800)):
            yield port.req_valid.eq(1)
            yield port.req_addr.eq(addr)
            yield port.req_len.eq(1)
        for _ in range(8):
            for name, port in (("scan", bench.scan), ("comp", bench.comp)):
                if (yield port.req_ready):
                    order.append(name)
                    yield port.req_valid.eq(0)
            yield

    run_simulation(bench, gen())
    assert order == ["scan", "comp"]


def test_dma_write_burst_waits_for_data_and_stays_busy_until_its_last_beat() -> None:
    bench, log = DmaBench(), []

    def gen() -> Sim:
        w = bench.wr
        yield w.req_valid.eq(1)
        yield w.req_addr.eq(0x40)
        yield w.req_len.eq(2)
        yield
        yield w.req_valid.eq(0)
        for t, valid in enumerate([0, 0, 1, 0, 1, 0, 0]):
            yield w.dat_valid.eq(valid)
            yield w.dat.eq(t)
            yield
            log.append(((yield w.dat_ready), (yield w.busy)))

    run_simulation(bench, gen())
    assert [i for i, (ready, _) in enumerate(log) if ready] == [2, 4]  # only when data was there
    assert [busy for _, busy in log] == [1, 1, 1, 1, 1, 0, 0]


class RamBench(Module):
    def __init__(self) -> None:
        self.cpu = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.dma = wishbone.Interface(data_width=64, address_width=32, addressing="word")
        self.submodules.ram = ZMSimRAM(1 << 12, self.cpu, self.dma)


def test_simram_cpu_reads_what_the_dma_wrote_little_endian() -> None:
    bench, got = RamBench(), []

    def gen() -> Sim:
        d = bench.dma
        for sig, v in ((d.adr, 3), (d.dat_w, 0x1122334455667788), (d.sel, 0xFF), (d.we, 1), (d.cyc, 1), (d.stb, 1)):
            yield sig.eq(v)
        yield
        yield d.cyc.eq(0)
        yield d.stb.eq(0)
        for word in (6, 7):  # 64-bit word 3 = 32-bit words 6 (low) and 7 (high)
            c = bench.cpu
            yield c.adr.eq(word)
            yield c.cyc.eq(1)
            yield c.stb.eq(1)
            yield
            while not (yield c.ack):
                yield
            got.append((yield c.dat_r))
            yield c.cyc.eq(0)
            yield c.stb.eq(0)
            yield

    run_simulation(bench, gen())
    assert got == [0x55667788, 0x11223344]


def test_simram_alternates_when_both_masters_want_it() -> None:
    bench, grants = RamBench(), []

    def gen() -> Sim:
        for bus in (bench.cpu, bench.dma):
            yield bus.cyc.eq(1)
            yield bus.stb.eq(1)
        for _ in range(6):
            yield
            grants.append(("cpu" if (yield bench.ram.g_cpu) else "") + ("dma" if (yield bench.ram.g_dma) else ""))

    run_simulation(bench, gen())
    assert all(g in ("cpu", "dma") for g in grants)  # one access a cycle, never both
    assert "cpu" in grants and "dma" in grants  # neither starves
