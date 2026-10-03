"""The compositor in its own clock domain (`comp`), the rest of the SoC in `sys`.

rtl/video/zm_video_out.v runs in ONE clock, `clk`: the compositor, the two
pictures' swap and the scanout fetch. On the board that clock is `comp`, faster
than the CPU's `sys` (fpga/README.md "Timing under openXC7": the compositor
alone closes ~118 MHz where the SoC closes ~100). Everything between the RTL
and the SoC crosses here, with the primitives of soc/zm_cdc.py:

- the snooped stores (sys -> comp): an AsyncQueue the snoop feeds and the
  compositor drains every clock. `drained` (the drain rule) is the writer's
  `empty_w`: a store counts as delivered once the compositor has used it.
- the command: `cmd` is written in sys; its toggle crosses, the fields (held
  in the CSR, which the sequencer writes only when `ready`) are read in comp.
  The compositor echoes back, as toggles, the command it has taken
  (`painted`: the pass has read the CPU's state) and finished (`ready`). An echo
  is the request's own toggle value, so a stale level can never pass for a new
  one, and `done` changes two clocks after the state it vouches for
  (`pending`, `front`), so the sequencer never sees one without the other.
- the register read-back (`bus`, sys): a toggle request, the word captured in
  comp, a toggle back.
- the memory ports: each request is a ReqCross, the read data an AsyncQueue
  (the DMA waits while it is full: `rsp_room`), the write data an AsyncQueue the
  DMA drains. A write is busy until the DMA has finished its burst.
- pulses (VBL, pass done) through PulseSynchronizers; counters through
  BusSynchronizers; sticky levels through MultiRegs.

`vbase`, `fb0`, `fb1` are not crossed: the firmware writes them once, before
the first command, whose own crossing orders them.
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from migen import Cat, If, Signal
from migen.genlib.cdc import BusSynchronizer, MultiReg, PulseSynchronizer

from soc.zm_cdc import AsyncQueue, ReqCross
from soc.zm_video_dma import ReadPort, WritePort

QUEUE = 16  # entries per data queue: a few clocks of round trip at one beat a clock
# A LiteX wishbone.Interface: untyped, its signals are attributes made at runtime.
Bus = Any
Ports = dict[str, Signal]


class ReadPortCross(LiteXModule):
    """The RTL's read port `c` (in `cd`) onto the DMA's read port `s` (in sys)."""

    def __init__(self, c: ReadPort, s: ReadPort, cd: str) -> None:
        self.req, self.rsp = req, rsp = ReqCross(42, cd, "sys"), AsyncQueue(64, QUEUE, "sys", cd)
        sync = getattr(self.sync, cd)
        self.comb += [
            req.s_valid.eq(c.req_valid),
            c.req_ready.eq(req.s_ready),
            req.s_payload.eq(Cat(c.req_addr, c.req_len)),
            s.req_valid.eq(req.d_valid),
            req.d_ready.eq(s.req_ready),
            Cat(s.req_addr, s.req_len).eq(req.d_payload),
            rsp.we.eq(s.rsp_valid),
            rsp.din.eq(s.rsp_data),
            s.rsp_room.eq(rsp.writable),
            rsp.re.eq(1),
        ]
        sync += [c.rsp_valid.eq(rsp.readable), c.rsp_data.eq(rsp.dout)]


class WritePortCross(LiteXModule):
    """The RTL's write port `c` (in `cd`) onto the DMA's write port `s` (in sys).
    One burst at a time end to end: `c.busy` from the request until the DMA's
    last beat, as the RTL's STORE requires before it reports a row written."""

    def __init__(self, c: WritePort, s: WritePort, cd: str) -> None:
        self.req, self.dat = req, dat = ReqCross(42, cd, "sys"), AsyncQueue(64, QUEUE, cd, "sys")
        fin, fin_c, was_busy = Signal(), Signal(), Signal()
        self.specials += MultiReg(fin, fin_c, cd)
        self.sync += [was_busy.eq(s.busy), If(was_busy & ~s.busy, fin.eq(req.ack))]
        self.comb += [
            c.busy.eq(req.tog != fin_c),
            req.s_valid.eq(c.req_valid & ~c.busy),
            c.req_ready.eq(req.s_ready & ~c.busy),
            req.s_payload.eq(Cat(c.req_addr, c.req_len)),
            s.req_valid.eq(req.d_valid),
            req.d_ready.eq(s.req_ready),
            Cat(s.req_addr, s.req_len).eq(req.d_payload),
            dat.we.eq(c.dat_valid),
            dat.din.eq(c.dat),
            c.dat_ready.eq(dat.writable),
            s.dat_valid.eq(dat.readable),
            s.dat.eq(dat.dout),
            dat.re.eq(s.dat_ready),
        ]


class ZMVideoCDC(LiteXModule):
    """Command, status, read-back, snoop and events between sys and the RTL's `p` (in `cd`)."""

    def __init__(self, p: Ports, cd: str) -> None:
        self.cmd_re = Signal()  # sys: the sequencer wrote `cmd`
        self.ready, self.painted, self.pending, self.front = Signal(), Signal(), Signal(), Signal()
        self.overflow, self.underrun, self.vbl, self.pass_done = Signal(), Signal(), Signal(), Signal()
        self.swaps, self.comp_busy = Signal(32), Signal(32)
        self._command(p, cd)
        self._levels(p, cd)

    def _command(self, p: Ports, cd: str) -> None:
        req, req_c, taken, painted_t, done0, done_t = (Signal() for _ in range(6))
        painted_s, done_s, issued = Signal(), Signal(), Signal()
        self.specials += MultiReg(req, req_c, cd), MultiReg(painted_t, painted_s), MultiReg(done_t, done_s)
        pend = req_c != taken
        sync = getattr(self.sync, cd)
        sync += [
            If(pend & p["cmd_ready"], taken.eq(req_c)),
            If(p["painted"], painted_t.eq(taken)),
            If(~pend & p["cmd_ready"], done0.eq(taken)),
            done_t.eq(done0),  # one clock after done0: `pending` and `front` have settled first
        ]
        self.sync += If(self.cmd_re, req.eq(~req), issued.eq(1))
        self.comb += [
            p["cmd_valid"].eq(pend),
            self.ready.eq(done_s == req),
            self.painted.eq(issued & (painted_s == req)),
        ]

    def _levels(self, p: Ports, cd: str) -> None:
        busy, sync = Signal(32), getattr(self.sync, cd)
        sync += If(~p["cmd_ready"], busy.eq(busy + 1))
        for src, dst in ((p["pending"], self.pending), (p["front"], self.front), (p["overflow"], self.overflow)):
            self.specials += MultiReg(src, dst)
        self.specials += MultiReg(p["underrun"], self.underrun)  # from the pixel clock, sticky
        for src, dst in ((p["vbl"], self.vbl), (p["pass_done"], self.pass_done)):
            ps = PulseSynchronizer(cd, "sys")
            self.submodules += ps
            self.comb += [ps.i.eq(src), dst.eq(ps.o)]
        for src, dst in ((p["swaps"], self.swaps), (busy, self.comp_busy)):
            bs = BusSynchronizer(32, cd, "sys")
            self.submodules += bs
            self.comb += [bs.i.eq(src), dst.eq(bs.o)]

    def window(self, bus: Bus, p: Ports, cd: str) -> None:
        """Wishbone slave (sys), read-only: one word of the compositor's register block."""
        rq, rq_c, rk, rk_s, pend, ack = (Signal() for _ in range(6))
        data = Signal(32)
        self.specials += MultiReg(rq, rq_c, cd), MultiReg(rk, rk_s)
        sync = getattr(self.sync, cd)
        sync += If(rq_c != rk, rk.eq(rq_c), data.eq(p["cpu_rdata"]))
        self.sync += [
            ack.eq(0),
            If(bus.cyc & bus.stb & ~pend & ~ack, rq.eq(~rq), pend.eq(1), p["cpu_rword"].eq(bus.adr[:5])),
            If(pend & (rk_s == rq), ack.eq(1), pend.eq(0), bus.dat_r.eq(data)),
        ]
        self.comb += bus.ack.eq(ack)

    def snoop(self, cd: str) -> tuple[Ports, Signal, Signal]:
        """The snooped stores' queue: (sys-side inputs, room for two more, empty)."""
        self.snoopq = q = AsyncQueue(60, QUEUE, "sys", cd)
        sys_side = {"we": Signal(), "waddr": Signal(21), "be": Signal(4), "wdata": Signal(32), "sel": Signal(3)}
        self.snoop_out = out = {k: Signal(len(v)) for k, v in sys_side.items()}

        def word(side: Ports) -> Cat:
            return Cat(side["waddr"], side["be"], side["wdata"], side["sel"])

        self.comb += [q.we.eq(sys_side["we"]), q.din.eq(word(sys_side)), q.re.eq(1)]
        sync = getattr(self.sync, cd)
        sync += [out["we"].eq(q.readable), word(out).eq(q.dout)]
        room = q.level_w < QUEUE - 1  # the snoop's delivery is registered: one more may be on its way
        return sys_side, room, q.empty_w
