"""The hp-test's raw AXI3 engine (soc/zm_hp_test.py): bursts on one HP port with every
field from a register, so U-Boot can ask the PS's AFI and DDR any question the bridges
(soc/zm_hp.py, soc/zm_video_axi.py) would only ever ask one way.

A run is COUNT bursts of LEN+1 beats of 2^SIZE bytes from ADDR (a DDR byte address,
INCR, back to back: every burst starts where the last ended). Writes send the pattern
(soc/zm_hp_test_stats.py Pattern: beat k = seed + 2k | seed + 2k + 1 << 32, the low word in both
halves for SIZE < 3) with WSTRB = STRB; reads are compared against it under STRB. With
LANE set, a beat's STRB[3:0] and its compared word move to the 4-byte lane its address
selects (a 64-bit channel's narrow beats); without, they stay in the low lane (what a
32-bit channel uses). All address bursts are issued as fast as the port takes them,
write data never ahead of its burst's address.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from litex.gen import LiteXModule
from litex.soc.interconnect import axi
from migen import Cat, If, Mux, Replicate, Signal
from migen import Constant as Const

from soc.zm_hp import BURST_INCR
from soc.zm_hp_test_stats import Pattern, Stats


@dataclass
class RunCfg:
    """One port's run registers (soc/zm_hp_test.py lays them out)."""

    go: Signal = field(default_factory=Signal)
    write: Signal = field(default_factory=Signal)
    check: Signal = field(default_factory=Signal)
    lane: Signal = field(default_factory=Signal)
    addr: Signal = field(default_factory=lambda: Signal(32))
    len: Signal = field(default_factory=lambda: Signal(4))
    size: Signal = field(default_factory=lambda: Signal(3, reset=3))
    cache: Signal = field(default_factory=lambda: Signal(4))
    count: Signal = field(default_factory=lambda: Signal(16, reset=1))
    strb: Signal = field(default_factory=lambda: Signal(8, reset=0xFF))
    seed: Signal = field(default_factory=lambda: Signal(32))


def byte_mask(strb: object) -> Cat:
    """WSTRB-style byte enables -> a 64-bit bit mask."""
    return Cat(*[Replicate(strb[i], 8) for i in range(len(strb))])


class AXIProbe(LiteXModule):
    def __init__(self, hp: axi.AXIInterface, cfg: RunCfg) -> None:
        self.hp, self.cfg = hp, cfg
        self.stats = st = Stats()
        self.active, self.is_wr = Signal(), Signal()
        self.a_left, self.a_addr = Signal(16), Signal(32)  # bursts not yet issued; the next one's address
        self.d_left = Signal(16)  # bursts whose data (W) or last beat (R) has not been seen
        self.b_left = Signal(16)  # write responses still due
        self.w_beat, self.w_burst = Signal(4), Signal(16)  # beat in the current W burst; W bursts sent
        self.d_addr = Signal(32)  # the next data beat's address
        wide = cfg.size == 3
        step = (hp.w.valid & hp.w.ready) | (hp.r.valid & hp.r.ready)
        self.pattern = Pattern(cfg.seed, cfg.go, step, wide)
        self.lo, self.hi = self.pattern.lo, self.pattern.hi
        self.lane_hi = cfg.lane & ~wide & self.d_addr[2]
        self.comb += [st.start.eq(cfg.go), st.busy.eq(self.active), st.check.eq(cfg.check)]
        self.sync += If(cfg.go,
            self.active.eq(1), self.is_wr.eq(cfg.write), self.a_left.eq(cfg.count), self.a_addr.eq(cfg.addr),
            self.d_left.eq(cfg.count), self.b_left.eq(Mux(cfg.write, cfg.count, 0)), self.w_beat.eq(0),
            self.w_burst.eq(0), self.d_addr.eq(cfg.addr),
        )  # fmt: skip
        self._address()
        self._write()
        self._read()
        done = (self.a_left == 0) & (self.d_left == 0) & (self.b_left == 0)
        self.sync += If(self.active & done & ~cfg.go, self.active.eq(0))

    def _address(self) -> None:
        hp, cfg = self.hp, self.cfg
        want = self.active & (self.a_left != 0)
        for ch, on in ((hp.aw, self.is_wr), (hp.ar, ~self.is_wr)):
            self.comb += [
                ch.valid.eq(want & on), ch.addr.eq(self.a_addr), ch.len.eq(cfg.len), ch.size.eq(cfg.size),
                ch.burst.eq(BURST_INCR), ch.cache.eq(cfg.cache), ch.lock.eq(0), ch.prot.eq(0), ch.qos.eq(0),
                ch.id.eq(0),
            ]  # fmt: skip
        step = (cfg.len + 1) << cfg.size
        issued = (hp.aw.valid & hp.aw.ready) | (hp.ar.valid & hp.ar.ready)
        self.sync += If(issued, self.a_left.eq(self.a_left - 1), self.a_addr.eq(self.a_addr + step))

    def _write(self) -> None:
        hp, cfg = self.hp, self.cfg
        issued = self.cfg.count - self.a_left  # bursts whose address went out
        last = self.w_beat == cfg.len
        strb = Mux(self.lane_hi, cfg.strb[:4] << 4, Mux(cfg.lane & (cfg.size != 3), cfg.strb[:4], cfg.strb))
        self.comb += [
            hp.w.valid.eq(self.active & self.is_wr & (self.d_left != 0) & (self.w_burst < issued)),
            hp.w.data.eq(Cat(self.lo, self.hi)), hp.w.strb.eq(strb), hp.w.last.eq(last), hp.w.id.eq(0),
            hp.b.ready.eq(1),
            self.stats.resp_valid.eq((hp.b.valid & hp.b.ready) | (hp.r.valid & hp.r.ready & hp.r.last)),
            self.stats.resp.eq(Mux(hp.b.valid, hp.b.resp, hp.r.resp)),
        ]  # fmt: skip
        sent = hp.w.valid & hp.w.ready
        self.sync += [
            If(sent, self._next_beat(), self.w_beat.eq(Mux(last, 0, self.w_beat + 1)),
               If(last, self.w_burst.eq(self.w_burst + 1), self.d_left.eq(self.d_left - 1))),
            If(hp.b.valid & hp.b.ready, self.b_left.eq(self.b_left - 1)),
        ]  # fmt: skip

    def _read(self) -> None:
        hp, cfg, st = self.hp, self.cfg, self.stats
        got = hp.r.data
        narrow = cfg.lane & (cfg.size != 3)
        exp, mask = Cat(self.lo, self.hi), byte_mask(cfg.strb)
        lane_word = Mux(self.lane_hi, got[32:], got[:32])  # LANE: the word the beat's address selects
        self.comb += [
            hp.r.ready.eq(1),
            st.beat.eq((hp.w.valid & hp.w.ready) | (hp.r.valid & hp.r.ready)),
            st.got.eq(Mux(self.is_wr, Cat(self.lo, self.hi), Mux(narrow, Cat(lane_word, got[32:]), got))),
            st.exp.eq(exp), st.mask.eq(Mux(self.is_wr, 0, Mux(narrow, byte_mask(cfg.strb[:4]), mask))),
        ]  # fmt: skip
        beat = hp.r.valid & hp.r.ready
        self.sync += If(beat, self._next_beat(), If(hp.r.last, self.d_left.eq(self.d_left - 1)))

    def _next_beat(self) -> list[object]:
        return [self.d_addr.eq(self.d_addr + (Const(1, 4) << self.cfg.size))]
