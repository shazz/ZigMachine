"""The hp-test's bridge engines (soc/zm_hp_test.py): the board SoC's OWN HP masters,
imported as they are, driven from registers instead of the CPU and the compositor.

- `WishboneRun` -> soc/zm_hp.py WishboneHP on HP0: COUNT 32-bit Wishbone accesses
  from ADDR, as the cart CPU makes them: single stores (data seed + 2i), single loads,
  or with LINE, 8-beat incrementing bursts (cti 010 .. 111) like a VexRiscv line refill.
- `VideoRun` -> soc/zm_video_axi.py ZMVideoAXI on HP1: one request of COUNT 64-bit beats
  (at most 1023), as the compositor's row write or read; CACHE[1:0] is its `hp_cfg`
  (bit 0 UPSIZE, bit 1 W64).

ADDR is the DDR byte address; the bus address handed to a bridge is the same offset in
the cart window (soc/zm_hp.py CPU_BASE <-> DDR_BASE).
"""

from __future__ import annotations

from litex.gen import LiteXModule
from litex.soc.interconnect import axi, wishbone
from migen import Cat, If, Mux, Signal
from migen import Constant as Const

from soc.zm_hp import CPU_BASE, WINDOW_LOG2, WishboneHP
from soc.zm_hp_test_axi import RunCfg, byte_mask
from soc.zm_hp_test_stats import Pattern, Stats
from soc.zm_video_axi import ZMVideoAXI
from soc.zm_video_dma import read_port, write_port

CTI_INCR, CTI_END, CTI_CLASSIC = 0b010, 0b111, 0b000


def bus_addr(ddr: Signal) -> Cat:
    """The cart-window bus byte address of DDR byte address `ddr`."""
    return Cat(ddr[:WINDOW_LOG2], Const(CPU_BASE >> WINDOW_LOG2, 32 - WINDOW_LOG2))


class WishboneRun(LiteXModule):
    def __init__(self, hp: axi.AXIInterface, cfg: RunCfg, line: Signal) -> None:
        self.bus = bus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.hp_bridge = WishboneHP(bus, hp)
        self.stats = st = Stats()
        active, left, i, gap = Signal(), Signal(16), Signal(16), Signal()
        self.pattern = Pattern(cfg.seed, cfg.go, bus.ack, 0)
        word = self.pattern.lo
        burst_cti = Mux(i[:3] == 7, CTI_END, CTI_INCR)
        self.comb += [
            bus.dat_w.eq(word), bus.sel.eq(0xF), bus.we.eq(cfg.write),
            bus.cti.eq(Mux(line, burst_cti, CTI_CLASSIC)), bus.bte.eq(0),
            bus.cyc.eq(active & ~gap), bus.stb.eq(active & ~gap),
            st.start.eq(cfg.go), st.busy.eq(active), st.check.eq(cfg.check),
            st.beat.eq(bus.ack), st.got.eq(Mux(cfg.write, word, bus.dat_r)), st.exp.eq(word),
            st.mask.eq(Mux(cfg.write, 0, byte_mask(Const(0x0F, 8)))),
        ]  # fmt: skip
        self.sync += [
            gap.eq(bus.ack),  # one idle cycle after every beat, as tests/test_board_mem.py's `access`
            If(cfg.go, active.eq(cfg.count != 0), left.eq(cfg.count), i.eq(0), bus.adr.eq(bus_addr(cfg.addr)[2:])),
            If(bus.ack, i.eq(i + 1), left.eq(left - 1), bus.adr.eq(bus.adr + 1), If(left == 1, active.eq(0))),
        ]  # fmt: skip


class VideoRun(LiteXModule):
    def __init__(self, hp: axi.AXIInterface, cfg: RunCfg) -> None:
        self.rd, self.wr = rd, wr = read_port("hpt_rd"), write_port("hpt_wr")
        self.dma = ZMVideoAXI([rd], wr, hp, cfg.cache[:2])
        self.stats = st = Stats()
        active, asked, k = Signal(), Signal(), Signal(16)
        self.pattern = Pattern(cfg.seed, cfg.go, st.beat)
        data = Cat(self.pattern.lo, self.pattern.hi)
        for port in (rd, wr):
            self.comb += [port.req_addr.eq(bus_addr(cfg.addr)), port.req_len.eq(cfg.count[:10])]
        self.comb += [
            rd.req_valid.eq(active & ~asked & ~cfg.write), wr.req_valid.eq(active & ~asked & cfg.write),
            wr.dat.eq(data), wr.dat_valid.eq(active & asked & cfg.write & (k != cfg.count[:10])),
            st.start.eq(cfg.go), st.busy.eq(active), st.check.eq(cfg.check),
            st.beat.eq(Mux(cfg.write, wr.dat_valid & wr.dat_ready, rd.rsp_valid)),
            st.got.eq(Mux(cfg.write, data, rd.rsp_data)), st.exp.eq(data),
            st.mask.eq(Mux(cfg.write, 0, byte_mask(cfg.strb))),
        ]  # fmt: skip
        granted = (rd.req_valid & rd.req_ready) | (wr.req_valid & wr.req_ready)
        idle = Signal()  # the DMA has finished: its request is over (a write: every response back)
        self.comb += idle.eq(~self.dma.active)
        self.sync += [
            If(cfg.go, active.eq(cfg.count[:10] != 0), asked.eq(0), k.eq(0)),
            If(granted, asked.eq(1)),
            If(st.beat, k.eq(k + 1)),
            If(active & asked & idle & ~granted, active.eq(0)),
        ]  # fmt: skip
