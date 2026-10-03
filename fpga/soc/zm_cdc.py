"""Clock-domain crossings for the compositor's own clock (soc/zm_video_cdc.py).

Two primitives, both built on 2-flip-flop synchronisers (Migen's MultiReg, which
Yosys/Vivado see as ASYNC_REG chains) and on values held stable until their
toggle has landed, the discipline rtl/video/zm_video_sync.v already uses
between `sys` and `pix`:

- `AsyncQueue`: a FIFO with gray-coded pointers, the data in distributed RAM
  (written in the writer's clock, read asynchronously by the reader). Besides
  the usual `writable` / `readable`, the writer sees `empty_w`: every entry it
  wrote has been taken by the reader. That is what the drain rule needs: the
  sequencer may only start a pass once the snooped stores have reached the
  compositor, a fact that lives in the READER's domain.
- `ReqCross`: one request (a valid/ready handshake plus a payload) carried by a
  toggle. The payload is latched when the source's handshake fires and held
  until the destination's acknowledge toggles back, so it is never sampled
  while it changes. One request in flight at a time.
"""

from __future__ import annotations

from litex.gen import LiteXModule
from migen import Cat, If, Memory, Signal
from migen.genlib.cdc import MultiReg


def _gray(v: Signal) -> Signal:
    return v ^ (v >> 1)


def _bin(g: Signal) -> list[Signal]:
    """The bits of the binary value of gray code `g`, low bit first."""
    bits = [g[len(g) - 1]]
    for i in reversed(range(len(g) - 1)):
        bits.insert(0, bits[0] ^ g[i])
    return bits


class AsyncQueue(LiteXModule):
    """A `width`-bit FIFO from domain `wcd` to domain `rcd`, `depth` a power of two.

    Writer side: `we`, `din`, `writable`, `level_w` (entries the reader has not
    yet consumed, as the writer sees it: never fewer than there are), `empty_w`.
    Reader side: `re`, `dout` (asynchronous, the entry at the head), `readable`.
    The reader publishes its pointer one clock after a pop, so a consumer that
    registers `dout` has used the entry before the writer can see it gone.
    """

    def __init__(self, width: int, depth: int, wcd: str, rcd: str) -> None:
        assert depth >= 2 and depth & (depth - 1) == 0, "the gray pointers need a power-of-two depth"
        aw = depth.bit_length() - 1
        self.we, self.din, self.writable, self.empty_w = Signal(), Signal(width), Signal(), Signal()
        self.level_w = Signal(aw + 1)
        self.re, self.dout, self.readable = Signal(), Signal(width), Signal()
        wbin, rbin, rbin_w = Signal(aw + 1), Signal(aw + 1), Signal(aw + 1)
        wgray, rgray, rgray_pub = Signal(aw + 1), Signal(aw + 1), Signal(aw + 1)  # registered: one flop each
        wgray_r, rgray_w = Signal(aw + 1), Signal(aw + 1)
        self.specials += MultiReg(wgray, wgray_r, rcd), MultiReg(rgray_pub, rgray_w, wcd)
        push, pop = Signal(), Signal()
        wnext, rnext = Signal(aw + 1), Signal(aw + 1)
        self.comb += [
            rbin_w.eq(Cat(*_bin(rgray_w))),
            self.level_w.eq(wbin - rbin_w),
            self.writable.eq(self.level_w != depth),
            self.empty_w.eq(self.level_w == 0),
            self.readable.eq(rgray != wgray_r),
            push.eq(self.we & self.writable),
            pop.eq(self.re & self.readable),
            wnext.eq(wbin + push),
            rnext.eq(rbin + pop),
        ]
        wsync, rsync = getattr(self.sync, wcd), getattr(self.sync, rcd)
        wsync += [wbin.eq(wnext), wgray.eq(_gray(wnext))]
        rsync += [rbin.eq(rnext), rgray.eq(_gray(rnext)), rgray_pub.eq(rgray)]
        self._storage(width, depth, wcd, push, wbin[:aw], rbin[:aw])

    def _storage(self, width: int, depth: int, wcd: str, push: Signal, wadr: Signal, radr: Signal) -> None:
        """Distributed RAM: written in the writer's clock, read asynchronously."""
        mem = Memory(width, depth)
        wport = mem.get_port(write_capable=True, clock_domain=wcd)
        rport = mem.get_port(async_read=True)
        self.specials += mem, wport, rport
        self.comb += [
            wport.adr.eq(wadr),
            wport.we.eq(push),
            wport.dat_w.eq(self.din),
            rport.adr.eq(radr),
            self.dout.eq(rport.dat_r),
        ]


class ReqCross(LiteXModule):
    """A request with a `width`-bit payload from `scd` to `dcd`.

    Source side: `s_valid`, `s_payload` in, `s_ready` out (the request is taken
    when both are high); `s_idle`: nothing is in flight. Destination side:
    `d_valid`, `d_payload` out, `d_ready` in. `tog` (source domain) flips with
    each request taken and `ack` (destination domain) follows it when taken there,
    for a caller that echoes a later event of the same request back.
    """

    def __init__(self, width: int, scd: str, dcd: str) -> None:
        self.s_valid, self.s_ready, self.s_payload, self.s_idle = Signal(), Signal(), Signal(width), Signal()
        self.d_valid, self.d_ready, self.d_payload = Signal(), Signal(), Signal(width)
        self.tog, self.ack = req, ack = Signal(), Signal()
        req_d, ack_s = Signal(), Signal()
        payload = Signal(width)
        self.specials += MultiReg(req, req_d, dcd), MultiReg(ack, ack_s, scd)
        self.comb += [
            self.s_idle.eq(req == ack_s),
            self.s_ready.eq(self.s_idle),
            self.d_valid.eq(req_d != ack),
            self.d_payload.eq(payload),
        ]
        ssync, dsync = getattr(self.sync, scd), getattr(self.sync, dcd)
        ssync += If(self.s_valid & self.s_ready, req.eq(~req), payload.eq(self.s_payload))
        dsync += If(self.d_valid & self.d_ready, ack.eq(req_d))
