"""The video pipeline's memory master on the board: soc/zm_video_dma.py's ports
(the scanout's and the compositor's reads, the compositor's writes) served
straight onto an AXI3 HP port (soc/zm_hp.py), in bursts.

Same contract as ZMVideoDMA: one request (an address and a beat count, a row
is 400 beats) at a time, the scanout first, then the write, then the other
reads. Inside a request the AXI side is pipelined:

- the address issuer cuts the request into bursts of up to 16 beats that never
  cross a 128-byte boundary (so never a 4 KiB one), and issues them back to
  back, as many as the port accepts;
- read data returns in order (one ID) and goes to the granted port while it has
  room (`rsp_room`, its clock-crossing queue's space): RREADY is that room;
- write data follows as 4-byte beats on WDATA[31:0], two per 64-bit beat, in
  bursts of up to 8 64-bit beats (64 bytes; the write channel is 32-bit, see
  soc/zm_hp.py), never ahead of the bursts already issued; the request
  ends once every burst's write response is back, so a pass that reads the row
  next sees it in DDR.

Addresses are cart-CPU bus byte addresses; zm_hp.ddr_addr maps them into the
DDR window.
"""

from __future__ import annotations

from litex.gen import LiteXModule
from litex.soc.interconnect import axi
from migen import Array, Cat, If, Mux, Signal

from soc.zm_hp import AW_CACHE, CACHE, SIZE_4, SIZE_8, ddr_addr, fixed_fields
from soc.zm_video_dma import ReadPort, WritePort

MAX_BURST = 16  # read bursts, in 64-bit beats
WR_BURST = 8  # write bursts, in 64-bit beats: 16 four-byte W beats (WR32, soc/zm_hp.py)


class ZMVideoAXI(LiteXModule):
    """Serves `reads` and one `write` port over `hp` (64-bit AXI3)."""

    def __init__(
        self, reads: list[ReadPort], write: WritePort, hp: axi.AXIInterface, cfg: Signal | None = None,
        enable: Signal | None = None,
    ) -> None:
        """cfg (the `hp_cfg` CSR, so the board picks without a rebuild): bit 0 UPSIZE, AWCACHE 0b0011
        instead of 0 (a 32-bit write channel may then upsize); bit 1 W64, whole 8-byte write
        beats (AWSIZE 3, WSTRB 0xff) for a 64-bit write channel, instead of two 4-byte beats."""
        self.hp = hp
        # enable (the board: glass CTRL.RUN): no request is granted while it is low, and one
        # already granted runs to its last response. A fresh bitstream then sends nothing before
        # U-Boot has set the AFI, and CTRL 0 lets a reload find the port idle, never mid-burst
        # (a cut burst wedges the PS's AFI across PL reloads: boards/.../README.md "Lessons").
        self.enable = enable if enable is not None else Signal(reset=1)
        self.cfg = cfg if cfg is not None else Signal(2)
        self.upsize, self.w64 = self.cfg[0], self.cfg[1]
        self.active, self.is_wr = Signal(), Signal()
        self.rd_sel = Signal(max(1, (len(reads) - 1).bit_length()))
        self.a_adr, self.a_left = Signal(29), Signal(10)  # the next burst's beat index; beats not yet issued
        self.d_left = Signal(10)  # beats not yet received (read) or sent (write)
        self.w_adr = Signal(3)  # the low bits of the next 64-bit write beat's index: a burst ends at 7
        self.w_hi = Signal()  # the next W beat is the upper word of the 64-bit beat
        self.b_out = Signal(6)  # bursts issued and not yet answered
        self.comb += [*fixed_fields(hp.ar), *fixed_fields(hp.aw), hp.w.id.eq(0), hp.b.ready.eq(1)]
        self._grant(reads, write)
        self._issue()
        self._read(reads)
        self._write(write)
        done = (self.d_left == 0) & (self.a_left == 0) & (self.b_out == 0)
        self.sync += If(self.active & done, self.active.eq(0))

    def _grant(self, reads: list[ReadPort], write: WritePort) -> None:
        """When idle, the highest-priority request is granted (its req_ready) and loaded."""
        order: list[tuple[ReadPort | WritePort, int]] = [(reads[0], 0), (write, -1)]
        order += [(reads[i], i) for i in range(1, len(reads))]
        taken = Signal()  # a higher-priority port asked this cycle
        for port, i in order:
            grant, before = Signal(), taken
            taken = Signal()
            self.comb += [
                grant.eq(self.enable & ~self.active & port.req_valid & ~before),
                taken.eq(before | port.req_valid),
            ]
            self.comb += port.req_ready.eq(grant)
            beat = port.req_addr[3:]
            load = [self.active.eq(1), self.is_wr.eq(i < 0), self.a_adr.eq(beat), self.a_left.eq(port.req_len)]
            load += [self.d_left.eq(port.req_len), self.w_adr.eq(beat[:3]), self.w_hi.eq(0)]
            if i >= 0:
                load.append(self.rd_sel.eq(i))
            self.sync += If(grant, *load)

    def _issue(self) -> None:
        """AR or AW: the next burst, up to the 128-byte boundary or the request's end."""
        hp = self.hp
        room = Signal(5)
        n = Signal(5)  # 64-bit beats in this burst
        self.comb += [
            room.eq(Mux(self.is_wr, WR_BURST - self.a_adr[:3], MAX_BURST - self.a_adr[:4])),
            n.eq(Mux(self.a_left < room, self.a_left, room)),
        ]
        want = self.active & (self.a_left != 0)
        for ch, on in ((hp.ar, ~self.is_wr), (hp.aw, self.is_wr)):
            self.comb += [ch.valid.eq(want & on), ch.addr.eq(ddr_addr(self.a_adr))]
        # Reads: n 8-byte beats. Writes: 2n 4-byte beats (WR32), or n 8-byte beats (W64).
        self.comb += [
            hp.ar.len.eq(n - 1),
            hp.aw.len.eq(Mux(self.w64, n - 1, 2 * n - 1)),
            hp.aw.size.eq(Mux(self.w64, SIZE_8, SIZE_4)),
            # AWCACHE[1] clear by default: a 32-bit channel EXPANDS the burst, one 4-byte beat at a
            # time placed by address, the path HP0's single stores take (proven: bdiag mode 1).
            # UPSIZE lets it upsize even, 64-bit aligned bursts: on the board that path wrote the
            # video's rows wrong (2026-10-03, bdiag mode 3).
            hp.aw.cache.eq(Mux(self.upsize, CACHE, AW_CACHE)),
        ]
        issued = (hp.ar.valid & hp.ar.ready) | (hp.aw.valid & hp.aw.ready)
        answered = hp.b.valid & hp.b.ready
        self.sync += [
            If(issued, self.a_adr.eq(self.a_adr + n), self.a_left.eq(self.a_left - n)),
            self.b_out.eq(self.b_out + (hp.aw.valid & hp.aw.ready) - answered),
        ]

    def _read(self, reads: list[ReadPort]) -> None:
        hp = self.hp
        room = Array(r.rsp_room for r in reads)[self.rd_sel]
        self.comb += hp.r.ready.eq(self.active & ~self.is_wr & room)
        beat = hp.r.valid & hp.r.ready
        for i, port in enumerate(reads):
            self.comb += [port.rsp_valid.eq(beat & (self.rd_sel == i)), port.rsp_data.eq(hp.r.data)]
        self.sync += If(beat, self.d_left.eq(self.d_left - 1))

    def _write(self, write: WritePort) -> None:
        """WR32: each 64-bit beat as two 4-byte W beats on WDATA[31:0], low word then high.
        W64: each 64-bit beat as one 8-byte W beat."""
        hp = self.hp
        ahead = self.d_left > self.a_left  # this beat belongs to a burst already issued
        word = Mux(self.w_hi, write.dat[32:], write.dat[:32])
        done = self.w_hi | self.w64  # this W beat ends a 64-bit beat
        beat = hp.w.valid & hp.w.ready
        self.comb += [
            hp.w.valid.eq(self.active & self.is_wr & write.dat_valid & ahead),
            hp.w.data.eq(Mux(self.w64, write.dat, Cat(word, word))),
            hp.w.strb.eq(Mux(self.w64, 0xFF, 0x0F)),
            hp.w.last.eq(done & ((self.d_left == 1) | (self.w_adr == WR_BURST - 1))),
            write.dat_ready.eq(beat & done),
            write.busy.eq(self.active & self.is_wr),
        ]
        self.sync += If(
            beat, If(~self.w64, self.w_hi.eq(~self.w_hi)), If(done, self.d_left.eq(self.d_left - 1), self.w_adr.eq(self.w_adr + 1))
        )
