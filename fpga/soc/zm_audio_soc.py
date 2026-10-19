"""The machine's sound on the board SoC (docs/FPGA_AUDIO.md "The SoC"): rtl/audio's
core behind its stamped write queue (zm_audio_soc.v), a register window on the
cart CPU's bus, its PCM memory on HP3, its samples out through HDMI (zm_hdmi_out).

- **The players run on the cart CPU** (the SNDH player = Musashi, via wasm2c, in
  the firmware: cycles/baudio.c; ADR 2026-10-09 "SNDH in software"). Their chip
  calls reach the core as register writes stamped with the sample they land
  before (host/audio_imports.c), queued through AUDIO_WINDOW and applied in
  program order, each at its sample (rtl/audio/zm_audio_sched.v).
- **AUDIO_WINDOW is M-only**: it sits outside every seal window
  (rtl/seal/zm_seal_map.vh), so the cart reaches nothing new; only the firmware
  pushes writes, as the machine's sealed audio module is the only one that calls
  the chips in the browser.
- **PCM memory**: the players' own wasm memory (3 MiB, in the firmware's heap in
  DDR), where the machine keeps it: a Paula DATA address is an offset in it.
  The firmware writes the memory's bus address to PCM_BASE; `AudioHP` reads one
  byte a request as a single 8-byte HP3 read (four channels: four reads a sample,
  about 100 of the 2,268 clocks a sample at 100 MHz), the offset masked to 4 MiB
  and the address mapped into the cart CPU's 32 MiB window like every HP master
  here (soc/zm_hp.py ddr_addr). No cache: the CPU's stores are write-through, and a
  write to AUDIO_WINDOW waits until every posted store before it is in DDR
  (soc/zm_io_fence.py), so a byte the players wrote is the byte read.
- **Held in reset while the CPU is** (CTRL.RUN low): silent, and no HP3 read starts,
  so a PL reload never cuts a burst (the AFI wedge, fpga/boards/.../README.md).
"""

from __future__ import annotations

from fractions import Fraction
from pathlib import Path
from typing import Any

from litex.gen import LiteXModule
from litex.soc.integration.soc import SoCRegion
from litex.soc.interconnect import axi, wishbone
from migen import Array, ClockSignal, If, Instance, ResetSignal, Signal

from soc.zm_hp import ddr_addr, fixed_fields

FPGA = Path(__file__).resolve().parent.parent
AUDIO_WINDOW = 0x92000000  # uncached (bit 31), outside the seal's windows (video 0x9000_0000, 8 MiB)
AUDIO_WINDOW_BYTES = 0x1000
PCM_SPAN_LOG2 = 22  # a PCM offset is masked to 4 MiB: the players' memory is 3 MiB
SOURCES = [
    *(f"rtl/audio/zm_audio_{m}.v" for m in ("frac", "ym", "pokey", "pcm", "mix", "core", "sched", "soc", "fifo")),
    *(f"rtl/audio/zm_pokey{m}.v" for m in ("", "_pair", "_poly")),
    *(f"third_party/jt49/hdl/jt49{m}.v" for m in ("", "_cen", "_div", "_eg", "_exp", "_noise")),
]
HDMI_SOURCES = [f"rtl/hdmi/zm_hdmi_{m}.v" for m in ("acr", "island", "packets", "enc", "tx")]
DROP_AFTER = 32  # the `drop` break test: the first YM R8 write after this many pushes is lost

# LiteX platforms and SoCs: untyped, their submodules are attributes made at runtime.
Platform = Any
SoC = Any


def rates(sys_hz: int) -> dict[str, int]:
    """zm_audio_soc's parameters: 44.1 kHz and the YM's 2 MHz as exact fractions of sys. (The
    POKEY needs none: zm_audio_pokey runs each sample's machine cycles in a burst at the strobe.)"""
    sr, ym = Fraction(44100, sys_hz), Fraction(2_000_000, sys_hz)
    if sr.denominator >= 1 << 24 or ym.numerator >= ym.denominator:
        raise ValueError(f"no exact 44.1 kHz / 2 MHz from a {sys_hz} Hz system clock")
    return {"p_SR_INC": sr.numerator, "p_SR_MOD": sr.denominator, "p_YM_INC": ym.numerator, "p_YM_MOD": ym.denominator}


class AudioHP(LiteXModule):
    """The core's PCM byte port (`req`/`addr` -> `ack`/`data`) on an HP port, read-only:
    one 1-beat 8-byte read per byte, started only while `enable`; else answered 0."""

    def __init__(self, hp: axi.AXIInterface, base: Signal, enable: Signal | int = 1) -> None:
        self.req, self.addr, self.ack, self.data = Signal(), Signal(32), Signal(), Signal(8)
        busy, lane, bus = Signal(), Signal(3), Signal(32)
        lanes = Array(hp.r.data[8 * i : 8 * i + 8] for i in range(8))
        self.comb += [
            bus.eq(base + self.addr[:PCM_SPAN_LOG2]),
            *fixed_fields(hp.ar),
            hp.r.ready.eq(1),
            hp.b.ready.eq(1),
        ]
        self.sync += [
            self.ack.eq(0),
            If(self.req & ~busy & ~self.ack,
               If(enable,
                  hp.ar.valid.eq(1), hp.ar.addr.eq(ddr_addr(bus[3:])), hp.ar.len.eq(0),
                  busy.eq(1), lane.eq(bus[:3]))
               .Else(self.ack.eq(1), self.data.eq(0))),
            If(hp.ar.valid & hp.ar.ready, hp.ar.valid.eq(0)),
            If(busy & hp.r.valid, busy.eq(0), self.ack.eq(1), self.data.eq(lanes[lane])),
        ]  # fmt: skip


class PcmWB(LiteXModule):
    """AudioHP's byte port as one 32-bit Wishbone read a byte, for a master that shares a bridge
    (the sound CPU's, soc/zm_sound_cpu.py): the offset is masked to 4 MiB as on HP3."""

    def __init__(self, bus: wishbone.Interface, base: Signal, enable: Signal | int = 1) -> None:
        self.req, self.addr, self.ack, self.data = Signal(), Signal(32), Signal(), Signal(8)
        busy, lane, at = Signal(), Signal(2), Signal(32)
        lanes = Array(bus.dat_r[8 * i : 8 * i + 8] for i in range(4))
        self.comb += [at.eq(base + self.addr[:PCM_SPAN_LOG2]), bus.we.eq(0), bus.sel.eq(0xF), bus.cti.eq(0)]
        self.sync += [
            self.ack.eq(0),
            If(self.req & ~busy & ~self.ack,
               If(enable, bus.cyc.eq(1), bus.stb.eq(1), bus.adr.eq(at[2:]), busy.eq(1), lane.eq(at[:2]))
               .Else(self.ack.eq(1), self.data.eq(0))),
            If(busy & bus.ack, bus.cyc.eq(0), bus.stb.eq(0), busy.eq(0), self.ack.eq(1), self.data.eq(lanes[lane])),
        ]  # fmt: skip


class ZMAudio(LiteXModule):
    """zm_audio_soc, its window (`bus`, a Wishbone slave), its PCM reader on HP3 (`hp`), or on the
    Wishbone `pcm_bus` a sound CPU shares with it (soc/zm_sound_cpu.py); `smp_*` (sys)."""

    def __init__(self, platform: Platform, sys_hz: int, hp: axi.AXIInterface, **kw: Any) -> None:
        enable, tap, break_ = kw.get("enable"), kw.get("tap", False), kw.get("break_", "")
        self.bus = bus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.smp_valid, self.smp_l, self.smp_r = Signal(), Signal(16), Signal(16)
        wr, rdata, base, core = Signal(), Signal(32), Signal(32), {k: Signal(n) for k, n in _CORE.items()}
        self.comb += wr.eq(bus.cyc & bus.stb & bus.we & ~bus.ack & ~self._dropped(bus, break_))
        self.sync += [bus.ack.eq(bus.cyc & bus.stb & ~bus.ack), bus.dat_r.eq(rdata)]
        at, en, pcm_bus = base + (1 if break_ == "base" else 0), 1 if enable is None else enable, kw.get("pcm_bus")
        self.mem = mem = AudioHP(hp, at, en) if pcm_bus is None else PcmWB(pcm_bus, at, en)
        rst = ResetSignal("sys") if enable is None else ResetSignal("sys") | ~enable
        self.specials += Instance(
            "zm_audio_soc", **rates(sys_hz), i_clk=ClockSignal("sys"), i_rst=rst,
            i_bus_wr=wr, i_bus_addr=bus.adr[:3], i_bus_wdata=bus.dat_w, o_bus_rdata=rdata,
            o_mem_req=mem.req, o_mem_addr=mem.addr, i_mem_ack=mem.ack, i_mem_data=mem.data, o_pcm_base=base,
            o_smp_valid=self.smp_valid, o_smp_l=self.smp_l, o_smp_r=self.smp_r,
            **{f"o_{k}": s for k, s in core.items()},
        )  # fmt: skip
        if tap:  # the sim's record of every write landing and every sample (rtl/sim/zm_audio_tap.v)
            self.specials += Instance(
                "zm_audio_tap", i_clk=ClockSignal("sys"), i_wr=core["core_wr"], i_addr=core["core_addr"],
                i_data=core["core_wdata"], i_now=core["now"], i_smp_valid=self.smp_valid,
                i_smp_l=self.smp_l, i_smp_r=self.smp_r,
            )  # fmt: skip
            platform.add_source(str(FPGA / "rtl/sim/zm_audio_tap.v"))
        for src in SOURCES:
            platform.add_source(str(FPGA / src))

    def _dropped(self, bus: Any, break_: str) -> Signal:  # Any: a LiteX wishbone.Interface
        """The `drop` break test: one YM R8 write (channel A's volume) never reaches the queue."""
        drop = Signal()
        if break_ != "drop":
            return drop
        qa, pushes, done = Signal(10), Signal(16), Signal()
        st = bus.cyc & bus.stb & bus.we & ~bus.ack
        self.comb += drop.eq(st & (bus.adr[:3] == 1) & (qa == 0x020) & (pushes > DROP_AFTER) & ~done)
        self.sync += [
            If(st & (bus.adr[:3] == 0), qa.eq(bus.dat_w[:10])),
            If(st & (bus.adr[:3] == 1), pushes.eq(pushes + 1)),
            If(drop, done.eq(1)),
        ]
        return drop


_CORE = {"core_wr": 1, "core_addr": 10, "core_wdata": 32, "now": 32}


def add_audio(soc: SoC, platform: Platform, hp: axi.AXIInterface, tap: bool = False, break_: str = "",
              sound: bool = False) -> None:  # fmt: skip
    """The audio on `hp` (HP3), its window on the bus; held in reset with the CPU (the glass).
    `sound`: the players on the sound CPU instead (soc/zm_sound_cpu.py), which then owns the window."""
    if sound:
        from soc.zm_sound_cpu import add_sound  # it builds on ZMAudio: imported here, not at the top

        return add_sound(soc, platform, hp, tap, break_)
    enable = soc.glass.cpu_run if hasattr(soc, "glass") else None
    soc.zm_audio = ZMAudio(platform, int(soc.sys_clk_freq), hp, enable=enable, tap=tap, break_=break_)
    soc.bus.add_slave("zm_audio", soc.zm_audio.bus, SoCRegion(origin=AUDIO_WINDOW, size=AUDIO_WINDOW_BYTES, cached=False))


def hdmi_out(audio: LiteXModule, platform: Platform, pic: dict[str, Signal], pads: dict[str, Signal]) -> Instance:
    """zm_hdmi_out: the picture `pic` (pix domain) and the audio's samples, on the HDMI pads."""
    for src in HDMI_SOURCES:
        platform.add_source(str(FPGA / src))
    return Instance(
        "zm_hdmi_out", i_sys_clk=ClockSignal("sys"), i_sys_rst=ResetSignal("sys"),
        i_smp_valid=audio.smp_valid, i_smp_l=audio.smp_l, i_smp_r=audio.smp_r,
        i_pix_clk=ClockSignal("pix"), i_pix5x_clk=ClockSignal("pix5x"), i_pix_rst=ResetSignal("pix"),
        i_r=pic["r"], i_g=pic["g"], i_b=pic["b"], i_de=pic["de"], i_hsync=pic["hsync"], i_vsync=pic["vsync"],
        o_tmds_p=pads["p"], o_tmds_n=pads["n"], o_fault=Signal(3),
    )  # fmt: skip
