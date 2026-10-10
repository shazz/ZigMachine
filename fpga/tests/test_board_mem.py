"""The board's memory path in Migen's simulator (soc/zm_board_mem.py): the CPU's
Wishbone -> AXI3 bridge onto HP0 (soc/zm_hp.py), the video DMA as an AXI3 burst
master onto HP1 (soc/zm_video_axi.py), and the sim's DDR model behind both
(soc/zm_simaxi.py). The end-to-end check (a cart's frame hash through all three)
is `make hp-sim` (cycles/board.mk)."""

from __future__ import annotations

import runpy
from collections.abc import Generator
from pathlib import Path

import pytest
from litex.soc.interconnect import wishbone
from migen import If, Module, Signal, run_simulation

from soc import zm_video_axi
from soc.zm_hp import CPU_BASE, DDR_BASE, WishboneHP, hp_interface
from soc.zm_simaxi import BAD, ZMSimAXIRAM
from soc.zm_video_axi import ZMVideoAXI
from soc.zm_video_dma import read_port, write_port

Sim = Generator[object, None, None]
SIZE = 1 << 16  # a small window for the bench; the model only answers inside it


class Bench(Module):
    def __init__(self, ram_base: int = DDR_BASE, w64: bool = False, enable: Signal | None = None) -> None:
        self.cpu = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.hp0, self.hp1 = hp_interface(), hp_interface()
        self.scan, self.comp, self.wr = read_port("sc"), read_port("rd"), write_port("wr")
        self.submodules.bridge = WishboneHP(self.cpu, self.hp0)
        self.enable = enable
        self.submodules.dma = ZMVideoAXI(
            [self.scan, self.comp], self.wr, self.hp1, Signal(2, reset=2 if w64 else 0), enable
        )
        # The write channels 32-bit, as the board runs them (soc/zm_hp.py "WR32"), or 64-bit for W64.
        self.submodules.ram = ZMSimAXIRAM(SIZE, [self.hp0, self.hp1], latency=5, base=ram_base, wr32=not w64)
        self.ars = []  # (port, addr, len) of every AR handshake
        self.aws = []  # (port, addr, len, size) of every AW handshake


def access(bus: wishbone.Interface, addr: int, value: int | None = None, sel: int = 0xF, cti: int = 0) -> Sim:
    """One Wishbone beat at bus byte address `addr`; returns the read data."""
    yield bus.adr.eq(addr >> 2)
    yield bus.cti.eq(cti)
    yield bus.we.eq(value is not None)
    yield bus.dat_w.eq(value or 0)
    yield bus.sel.eq(sel)
    yield bus.cyc.eq(1)
    yield bus.stb.eq(1)
    yield
    while not (yield bus.ack):
        yield
    data = yield bus.dat_r
    yield bus.cyc.eq(0)
    yield bus.stb.eq(0)
    yield
    return data


def watch_ar(bench: Bench, cycles: int) -> Sim:
    for _ in range(cycles):
        for name, hp in (("hp0", bench.hp0), ("hp1", bench.hp1)):
            if (yield hp.ar.valid) and (yield hp.ar.ready):
                bench.ars.append((name, (yield hp.ar.addr), (yield hp.ar.len)))
            if (yield hp.aw.valid) and (yield hp.aw.ready):
                bench.aws.append((name, (yield hp.aw.addr), (yield hp.aw.len), (yield hp.aw.size)))
        yield


def dma_write(bench: Bench, addr: int, beats: list[int]) -> Sim:
    w = bench.wr
    yield w.req_valid.eq(1)
    yield w.req_addr.eq(addr)
    yield w.req_len.eq(len(beats))
    yield
    while not (yield w.req_ready):
        yield
    yield w.req_valid.eq(0)
    for b in beats:
        yield w.dat.eq(b)
        yield w.dat_valid.eq(1)
        yield
        while not (yield w.dat_ready):
            yield
    yield w.dat_valid.eq(0)
    while (yield w.busy) or (yield bench.dma.active):
        yield


def dma_read(port: object, addr: int, n: int) -> Sim:
    yield port.req_valid.eq(1)
    yield port.req_addr.eq(addr)
    yield port.req_len.eq(n)
    yield
    while not (yield port.req_ready):
        yield
    yield port.req_valid.eq(0)
    got = []
    while len(got) < n:
        if (yield port.rsp_valid):
            got.append((yield port.rsp_data))
        yield
    return got


def run(bench: Bench, *gens: Sim, cycles: int = 3000) -> None:
    run_simulation(bench, [*gens, watch_ar(bench, cycles)])


def test_cpu_store_then_load_returns_it_including_the_upper_lane_and_byte_selects() -> None:
    bench, got = Bench(), []

    def cpu() -> Sim:
        yield from access(bench.cpu, CPU_BASE + 0x100, 0x11223344)
        yield from access(bench.cpu, CPU_BASE + 0x104, 0x55667788)
        yield from access(bench.cpu, CPU_BASE + 0x104, 0x0000AA00, sel=0b0010)
        got.append((yield from access(bench.cpu, CPU_BASE + 0x100)))
        got.append((yield from access(bench.cpu, CPU_BASE + 0x104)))

    run(bench, cpu())
    assert got == [0x11223344, 0x5566AA88]


def test_cpu_line_refill_is_one_four_beat_axi_burst_from_the_line_start() -> None:
    bench, got = Bench(), []
    words = [0x1000 + i for i in range(8)]

    def cpu() -> Sim:
        for i, w in enumerate(words):
            yield from access(bench.cpu, CPU_BASE + 0x220 + 4 * i, w)
        bench.ars.clear()
        for i in range(8):  # VexRiscv's refill: 8 beats, cti INCR then END on the last
            got.append((yield from access(bench.cpu, CPU_BASE + 0x220 + 4 * i, cti=0b111 if i == 7 else 0b010)))

    run(bench, cpu())
    assert got == words
    assert bench.ars == [("hp0", DDR_BASE + 0x220, 3)]


def test_cpu_line_buffer_is_dropped_after_the_burst_so_a_dma_write_is_seen() -> None:
    bench, got = Bench(), []

    def flow() -> Sim:
        yield from access(bench.cpu, CPU_BASE + 0x300, 1)
        got.append((yield from access(bench.cpu, CPU_BASE + 0x300, cti=0b111)))
        yield from dma_write(bench, CPU_BASE + 0x300, [0xCAFE])
        got.append((yield from access(bench.cpu, CPU_BASE + 0x300, cti=0b111)))

    run(bench, flow())
    assert got == [1, 0xCAFE]


def test_dma_write_then_read_round_trips_and_bursts_stop_at_128_byte_boundaries() -> None:
    bench, got = Bench(), []
    beats = [0x0102030405060708 * (i + 1) & (2**64 - 1) for i in range(40)]
    start = CPU_BASE + 0x1000 + 8 * 13  # 3 beats before a 128-byte boundary

    def flow() -> Sim:
        yield from dma_write(bench, start, beats)
        got.extend((yield from dma_read(bench.comp, start, len(beats))))

    run(bench, flow())
    assert got == beats
    lens = [n + 1 for port, _, n in bench.ars if port == "hp1"]
    assert lens == [3, 16, 16, 5]
    # Writes: 4-byte beats, two per 64-bit beat, bursts of up to 64 bytes ending on 64-byte boundaries.
    aws = [(n + 1, size) for port, _, n, size in bench.aws if port == "hp1"]
    assert aws == [(6, 2), (16, 2), (16, 2), (16, 2), (16, 2), (10, 2)]


def test_cpu_reads_what_the_dma_wrote_through_the_shared_memory() -> None:
    bench, got = Bench(), []

    def flow() -> Sim:
        yield from dma_write(bench, CPU_BASE + 0x2000, [0xAAAABBBB_CCCCDDDD])
        got.append((yield from access(bench.cpu, CPU_BASE + 0x2000)))
        got.append((yield from access(bench.cpu, CPU_BASE + 0x2004)))

    run(bench, flow())
    assert got == [0xCCCCDDDD, 0xAAAABBBB]


def test_ddr_model_answers_bad_outside_the_window_so_a_wrong_map_breaks_the_hash(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The mutant: a DMA that maps the cart window to the wrong DDR address.
    def wrong(beat: Signal) -> object:
        return beat << 3

    monkeypatch.setattr(zm_video_axi, "ddr_addr", wrong)
    bench, got = Bench(), []

    def flow() -> Sim:
        got.extend((yield from dma_read(bench.comp, CPU_BASE + 0x40, 2)))

    run(bench, flow())
    assert got == [BAD, BAD]


def test_ddr_model_poisons_writes_after_a_wlast_that_disagrees_with_awlen(monkeypatch: pytest.MonkeyPatch) -> None:
    # The mutant: a DMA whose WLAST comes only at the request's end, not at each 16-beat burst's.
    orig = ZMVideoAXI._write

    def late_wlast(self: ZMVideoAXI, write: object) -> None:
        orig(self, write)
        self.comb += self.hp.w.last.eq(self.w_hi & (self.d_left == 1))

    monkeypatch.setattr(ZMVideoAXI, "_write", late_wlast)
    bench, got = Bench(), []
    beats = list(range(1, 41))

    def flow() -> Sim:
        yield from dma_write(bench, CPU_BASE + 0x4000, beats)
        got.extend((yield from dma_read(bench.comp, CPU_BASE + 0x4000, len(beats))))

    run(bench, flow())
    assert got != beats


def test_board_bug_64_bit_write_beats_lose_every_odd_word_on_a_32_bit_write_channel(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The board's first picture (2026-10-03): the DMA wrote whole 8-byte beats (AxSIZE 3,
    # WSTRB 0xFF); on the PS only the low word of each landed, every odd pixel stayed black.
    def write64(self: ZMVideoAXI, write: object) -> None:
        hp = self.hp
        beat = hp.w.valid & hp.w.ready
        self.comb += [
            hp.w.valid.eq(self.active & self.is_wr & write.dat_valid & (self.d_left > self.a_left)),
            hp.w.data.eq(write.dat), hp.w.strb.eq(0xFF), hp.aw.size.eq(3), hp.aw.len.eq(self.hp.ar.len),
            hp.w.last.eq((self.d_left == 1) | (self.w_adr == 7)),
            write.dat_ready.eq(beat), write.busy.eq(self.active & self.is_wr),
        ]  # fmt: skip
        self.sync += If(beat, self.d_left.eq(self.d_left - 1), self.w_adr.eq(self.w_adr + 1))

    monkeypatch.setattr(ZMVideoAXI, "_write", write64)
    bench, got = Bench(), []
    beats = [(0x2000 + i) << 32 | (0x1000 + i) for i in range(12)]

    def flow() -> Sim:
        yield from dma_write(bench, CPU_BASE + 0x5000, beats)
        got.extend((yield from dma_read(bench.comp, CPU_BASE + 0x5000, len(beats))))

    run(bench, flow())
    assert [g & 0xFFFFFFFF for g in got] == [b & 0xFFFFFFFF for b in beats]  # even pixels land
    assert [g >> 32 for g in got] == [0] * len(beats)  # odd pixels never written: black


def test_board_bug_upsized_write_bursts_are_refused_like_the_afi_mangled_them(monkeypatch: pytest.MonkeyPatch) -> None:
    # The board's second picture (bdiag mode 3): AWCACHE 0b0011 let the 32-bit write channel
    # upsize the DMA's bursts; the row came out twice as long with wrong words.
    orig = ZMVideoAXI._issue

    def upsizing(self: ZMVideoAXI) -> None:
        orig(self)
        self.comb += self.hp.aw.cache.eq(0b0011)

    monkeypatch.setattr(ZMVideoAXI, "_issue", upsizing)
    bench, got = Bench(), []
    beats = list(range(1, 21))

    def flow() -> Sim:
        yield from dma_write(bench, CPU_BASE + 0x6000, beats)
        got.extend((yield from dma_read(bench.comp, CPU_BASE + 0x6000, len(beats))))

    run(bench, flow())
    assert got != beats


def test_dma_w64_mode_writes_whole_8_byte_beats_on_a_64_bit_write_channel() -> None:
    bench, got = Bench(w64=True), []
    beats = [(0x2000 + i) << 32 | (0x1000 + i) for i in range(20)]

    def flow() -> Sim:
        yield from dma_write(bench, CPU_BASE + 0x7000 + 8 * 3, beats)
        got.extend((yield from dma_read(bench.comp, CPU_BASE + 0x7000 + 8 * 3, len(beats))))

    run(bench, flow())
    assert got == beats
    assert [(n + 1, size) for port, _, n, size in bench.aws if port == "hp1"] == [(5, 3), (8, 3), (7, 3)]


def held_and_drained(bench: Bench, drop_after: int) -> tuple[int, int, int, bool]:
    """AWs while held, the request's beats once released, B responses, and the DMA idle at the end;
    the enable drops `drop_after` cycles into the request."""
    seen = {"aw_held": 0, "b": 0, "active": 1}
    beats = list(range(1, 41))

    def flow() -> Sim:
        w = bench.wr
        yield w.req_valid.eq(1)
        yield w.req_addr.eq(CPU_BASE + 0x8000)
        yield w.req_len.eq(len(beats))
        taken = False
        for _ in range(20):  # held: the request must not be taken
            if (yield bench.hp1.aw.valid):
                seen["aw_held"] += 1
            if (yield w.req_ready):
                taken = True
                yield w.req_valid.eq(0)
            yield
        yield bench.enable.eq(1)
        yield
        while not taken and not (yield w.req_ready):
            yield
        yield w.req_valid.eq(0)
        n = 0
        for b in beats:
            yield w.dat.eq(b)
            yield w.dat_valid.eq(1)
            yield
            while not (yield w.dat_ready):
                yield
            n += 1
            if n == drop_after:
                yield bench.enable.eq(0)  # CTRL 0 mid-request: the request still finishes
        yield w.dat_valid.eq(0)
        for _ in range(200):
            yield
        seen["active"] = yield bench.dma.active

    def count_b() -> Sim:
        for _ in range(1500):
            if (yield bench.hp1.b.valid) and (yield bench.hp1.b.ready):
                seen["b"] += 1
            yield

    run_simulation(bench, [flow(), count_b(), watch_ar(bench, 1500)])
    aws = len([a for a in bench.aws if a[0] == "hp1"])
    return seen["aw_held"], aws, seen["b"], bool(seen["active"])


def test_dma_takes_no_request_while_held_and_a_drop_mid_request_still_completes_every_burst() -> None:
    bench = Bench(enable=Signal())
    aw_held, aws, bs, active = held_and_drained(bench, drop_after=10)
    assert aw_held == 0  # nothing reaches the AFI before CTRL.RUN
    assert aws == bs > 1  # every burst issued got its response: the port is left idle, not mid-burst
    assert not active


def test_board_bug_a_dma_that_ignores_the_enable_talks_to_the_port_before_run(monkeypatch: pytest.MonkeyPatch) -> None:
    orig = ZMVideoAXI.__init__

    def ungated(self: ZMVideoAXI, *a: object, **k: object) -> None:
        k.pop("enable", None)
        args = list(a)[:4]
        orig(self, *args)

    monkeypatch.setattr(ZMVideoAXI, "__init__", ungated)
    bench = Bench(enable=Signal())
    aw_held, _, _, _ = held_and_drained(bench, drop_after=10)
    assert aw_held > 0


class _Glass:
    def __init__(self, load_base: int) -> None:
        self.load_base = Signal(32, reset=load_base)


def _slice_ar(load_base: int | None) -> int:
    """The AR address the PS7 sees for a master's DDR_BASE + 0x1238, through zm_board_mem.hp_slice."""
    from litex.gen import LiteXModule

    from soc.zm_board_mem import hp_slice

    soc = LiteXModule()
    if load_base is not None:
        soc.glass = _Glass(load_base)
    master = hp_interface()
    ps = hp_slice(soc, "hp0", master)
    seen: list[int] = []

    def drive() -> Sim:
        yield master.ar.valid.eq(1)
        yield master.ar.addr.eq(DDR_BASE + 0x1238)
        yield ps.ar.ready.eq(1)
        for _ in range(6):
            yield
            if (yield ps.ar.valid):
                seen.append((yield ps.ar.addr))

    run_simulation(soc, drive())
    assert seen, "no AR reached the PS7 side"
    return seen[0]


def test_slice_places_the_cart_window_at_the_glass_load_base() -> None:
    assert _slice_ar(0x1E000000) == 0x1E001238  # Linux: the top 32 MiB, kept from the kernel


def test_slice_reset_load_base_is_the_u_boot_window_so_board_run_needs_no_write() -> None:
    from soc.zm_hp import DDR_BASE as U_BOOT_WINDOW

    glass_map = runpy.run_path(str(Path(__file__).resolve().parent.parent / "gen" / "glass_map.py"))
    assert glass_map["LOAD_BASE_RESET"] == U_BOOT_WINDOW
    assert _slice_ar(glass_map["LOAD_BASE_RESET"]) == U_BOOT_WINDOW + 0x1238


def test_slice_without_a_glass_passes_the_address_through() -> None:
    assert _slice_ar(None) == DDR_BASE + 0x1238
