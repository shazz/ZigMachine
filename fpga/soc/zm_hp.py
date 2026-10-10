"""The cart CPU's main RAM in the PS's DDR, through the PS7's AXI HP ports
(fpga/README.md "The board's memory"; UG585 ch. 5 "AXI_HP").

- **The window.** The cart CPU's main RAM is 32 MiB at bus address `CPU_BASE`
  (0x4000_0000, where the firmware is linked: cycles/cycles.mk RV_LDFLAGS),
  and it IS PS DDR at `DDR_BASE` (0x0400_0000): bus `CPU_BASE + off` is DDR
  `DDR_BASE + off`. U-Boot leaves 0x0200_0000-0x0FFF_FFFF alone (its `bdinfo`
  reserves 0x1000_0000-0x10FF_FFFF and 0x1DAC_9F20 up), so the ARM can
  `fatload` the firmware image straight to DDR_BASE. That is where every master here
  addresses it; on the board, the PS7's register slice moves it to the glass's
  LOAD_BASE (soc/zm_board_mem.py hp_slice: 0x1E00_0000 under Linux).
- **HP0: the CPU** (`WishboneHP`): its 32-bit Wishbone becomes 64-bit AXI3, one
  transaction at a time. A cache-line refill (VexRiscv's 8-beat incrementing
  Wishbone burst, `cti` 010...111) is ONE 4-beat AXI burst into a line buffer
  the remaining beats are served from; the buffer lives only until the burst
  ends, so nothing goes stale behind the video DMA. A single read is a 1-beat
  burst; a store is a 1-beat 4-byte write, acknowledged on its write response
  (blocking: no store is posted, so `drained` needs no store-buffer term).
- **HP1: the video DMA** (soc/zm_video_axi.py), bursts of up to 16 beats.

**Reads 64-bit, writes 32-bit (WR32).** Each port's read channel runs 64-bit
(AFI_RDCHAN_CTRL 32BitEn = 0): 8-byte beats, AxSIZE 3. Its write channel runs
32-bit (AFI_WRCHAN_CTRL 32BitEn = 1): 4-byte beats on WDATA[31:0] / WSTRB[3:0],
AxSIZE 2; the AFI upsizes even, 64-bit aligned INCR bursts to the DDR's 64 bits
(UG585 5.3.6). On the board the upper half of every 64-bit WRITE beat was
lost (2026-10-03: every odd picture column black, never written; reads of both
halves fine), so no write uses WDATA[63:32] any more. U-Boot sets the AFI
registers after the PL is loaded (they hang the ARM without the PL's HP clock):
fpga/boards/microphase_z7_7010/README.md, "Running a cart from U-Boot".
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect import axi
from migen import Array, Cat, Constant as Const, If, Mux, Signal

CPU_BASE = 0x40000000
DDR_BASE = 0x04000000
WINDOW = 32 << 20  # bytes; DDR_BASE is aligned to it, so the map is a bit splice
WINDOW_LOG2 = 25
assert DDR_BASE % WINDOW == 0 and 1 << WINDOW_LOG2 == WINDOW
BURST_INCR, SIZE_4, SIZE_8 = 0b01, 2, 3
CACHE = 0b0011  # reads: bufferable, modifiable (a 64-bit read channel passes them as is)
AW_CACHE = 0b0000  # writes: [1] clear, so a 32-bit write channel never upsizes (soc/zm_video_axi.py)
CTI_CLASSIC, CTI_END = 0b000, 0b111
LINE_BEATS = 4  # VexRiscv's 32-byte lines (vexgen GenZm.scala bytePerLine) in 64-bit beats

# A LiteX wishbone.Interface: untyped, its signals are attributes made at runtime.
Bus = Any


def hp_interface() -> axi.AXIInterface:
    """One HP port's AXI3: 64-bit data, 6-bit IDs (the PS7's SAXIHP* widths)."""
    return axi.AXIInterface(data_width=64, address_width=32, id_width=6, version="axi3")


def ddr_addr(beat: Signal) -> Cat:
    """The DDR byte address of 64-bit beat index `beat` (a bus address >> 3)."""
    return Cat(Const(0, 3), beat[: WINDOW_LOG2 - 3], Const(DDR_BASE >> WINDOW_LOG2, 32 - WINDOW_LOG2))


def ddr_word_addr(word: Signal) -> Cat:
    """The DDR byte address of 32-bit word index `word` (a bus address >> 2)."""
    return Cat(Const(0, 2), word[: WINDOW_LOG2 - 2], Const(DDR_BASE >> WINDOW_LOG2, 32 - WINDOW_LOG2))


def fixed_fields(ch: Any) -> list[Any]:
    """The AW/AR fields every master here drives the same way."""
    return [ch.burst.eq(BURST_INCR), ch.size.eq(SIZE_8), ch.lock.eq(0), ch.prot.eq(0), ch.cache.eq(CACHE),
            ch.qos.eq(0), ch.id.eq(0)]  # fmt: skip


class WishboneHP(LiteXModule):
    """`bus` (32-bit, word-addressed Wishbone slave) -> `hp` (64-bit AXI3 master)."""

    def __init__(self, bus: Bus, hp: axi.AXIInterface) -> None:
        self.bus, self.hp = bus, hp
        self.ack = ack = Signal()
        self.req = bus.cyc & bus.stb & ~ack
        self.beat = bus.adr[1:]  # 64-bit beat index of the bus address
        self.line = bus.adr[3:]  # 32-byte line
        self.lane_hi = bus.adr[0]  # the upper 32 bits of the beat
        self.rbusy, self.wbusy = Signal(), Signal()  # an AXI read / write is in flight
        self.comb += [bus.ack.eq(ack), *fixed_fields(hp.ar), *fixed_fields(hp.aw)]
        self._line_buffer()
        self._read()
        self._write()

    def _line_buffer(self) -> None:
        """The beats of the line being refilled, valid until its burst ends."""
        bus = self.bus
        self.buf = Array(Signal(64, name=f"hp_line{i}") for i in range(LINE_BEATS))
        self.valid, self.tag, self.live = Signal(LINE_BEATS), Signal(len(self.line)), Signal()
        idx = self.beat[:2]
        self.hit = self.live & (self.tag == self.line) & (self.valid >> idx)[0]
        word = self.buf[idx]
        last = (bus.cti == CTI_CLASSIC) | (bus.cti == CTI_END)
        self.sync += [
            self.ack.eq(self.req & ~bus.we & self.hit),
            If(self.req & ~bus.we & self.hit, bus.dat_r.eq(Mux(self.lane_hi, word[32:], word[:32]))),
            # A burst's last beat (or a single access) closes the buffer: the next one refetches.
            If(self.ack & last, self.live.eq(0)),
        ]

    def _read(self) -> None:
        """A miss: one AXI read, the whole line for a burst beat, the one beat otherwise."""
        bus, hp = self.bus, self.hp
        busy, fill = self.rbusy, Signal(2)
        burst = bus.cti != CTI_CLASSIC
        start = self.req & ~bus.we & ~self.hit & ~busy & ~self.wbusy
        first = Mux(burst, Cat(Const(0, 2), self.line), self.beat)
        self.sync += [
            If(start,
               hp.ar.valid.eq(1), hp.ar.addr.eq(ddr_addr(first)), hp.ar.len.eq(Mux(burst, LINE_BEATS - 1, 0)),
               busy.eq(1), fill.eq(Mux(burst, 0, self.beat[:2])),
               self.tag.eq(self.line), self.valid.eq(0), self.live.eq(1)),
            If(hp.ar.valid & hp.ar.ready, hp.ar.valid.eq(0)),
            If(hp.r.valid & hp.r.ready,
               self.buf[fill].eq(hp.r.data), self.valid.eq(self.valid | (1 << fill)), fill.eq(fill + 1),
               If(hp.r.last, busy.eq(0))),
        ]  # fmt: skip
        self.comb += hp.r.ready.eq(1)

    def _write(self) -> None:
        """A store: one 1-beat AXI write, acknowledged on its response."""
        bus, hp, busy = self.bus, self.hp, self.wbusy
        start = self.req & bus.we & ~busy & ~self.rbusy
        self.sync += [
            If(start,
               hp.aw.valid.eq(1), hp.aw.addr.eq(ddr_word_addr(bus.adr)), hp.aw.len.eq(0),
               hp.w.valid.eq(1), hp.w.data.eq(Cat(bus.dat_w, bus.dat_w)), hp.w.strb.eq(bus.sel),
               busy.eq(1), self.live.eq(0)),
            If(hp.aw.valid & hp.aw.ready, hp.aw.valid.eq(0)),
            If(hp.w.valid & hp.w.ready, hp.w.valid.eq(0)),
            If(hp.b.valid & hp.b.ready, busy.eq(0), self.ack.eq(1)),
        ]  # fmt: skip
        # A 32-bit write channel (WR32): 4-byte beats on WDATA[31:0], whatever the address.
        self.comb += [hp.aw.size.eq(SIZE_4), hp.aw.cache.eq(AW_CACHE), hp.w.last.eq(1), hp.w.id.eq(0)]
        self.comb += hp.b.ready.eq(1)


def ps7_hp_ports(port: str, hp: axi.AXIInterface, clk: Signal) -> dict[str, object]:
    """The PS7 primitive's ports for S_AXI_HP<n> (`port` = "SAXIHP0"), wired to `hp`."""
    ports: dict[str, object] = {f"i_{port}ACLK": clk, f"i_{port}RDISSUECAP1EN": 0, f"i_{port}WRISSUECAP1EN": 0}
    for ch in ("AW", "AR"):
        sub = getattr(hp, ch.lower())
        for f in ("valid", "addr", "burst", "len", "id", "lock", "prot", "cache", "qos"):
            ports[f"i_{port}{ch}{f.upper()}"] = getattr(sub, f)
        ports[f"i_{port}{ch}SIZE"] = sub.size[:2]  # 2 bits on the primitive: 8-byte beats at most
        ports[f"o_{port}{ch}READY"] = sub.ready
    ports.update({
        f"i_{port}WVALID": hp.w.valid, f"i_{port}WLAST": hp.w.last, f"o_{port}WREADY": hp.w.ready,
        f"i_{port}WID": hp.w.id, f"i_{port}WDATA": hp.w.data, f"i_{port}WSTRB": hp.w.strb,
        f"o_{port}BVALID": hp.b.valid, f"i_{port}BREADY": hp.b.ready, f"o_{port}BID": hp.b.id,
        f"o_{port}BRESP": hp.b.resp,
        f"o_{port}RVALID": hp.r.valid, f"i_{port}RREADY": hp.r.ready, f"o_{port}RLAST": hp.r.last,
        f"o_{port}RID": hp.r.id, f"o_{port}RRESP": hp.r.resp, f"o_{port}RDATA": hp.r.data,
    })  # fmt: skip
    return ports
