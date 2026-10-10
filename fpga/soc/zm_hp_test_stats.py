"""What one hp-test run measured (soc/zm_hp_test.py): the counters every engine
(soc/zm_hp_test_axi.py, soc/zm_hp_test_bridge.py) reports through the same registers.

The engine drives `start` (a pulse, clears everything), `busy`, and per data beat
`beat` with `got` / `exp` / `mask` (a mismatch is `(got ^ exp) & mask != 0` while
`check` is set), plus `resp_valid` / `resp` for every AXI response it sees.
"""

from __future__ import annotations

from litex.gen import LiteXModule
from migen import Cat, If, Mux, Signal

NO_BAD = 0xFFFFFFFF  # badidx when no beat mismatched


class Pattern(LiteXModule):
    """Beat k's two words, in registers: low seed + 2k, high seed + 2k + 1 (the low word again
    unless `wide`: a 4-byte beat gets the low word whichever lane the AFI takes). `load` sets
    k = 0, `step` moves to k + 1, so no adder sits between a register and the data or the compare."""

    def __init__(self, seed: Signal, load: object, step: object, wide: object = 1) -> None:
        self.lo, self.hi = Signal(32), Signal(32)
        hi = Signal(32)
        self.sync += If(load, self.lo.eq(seed), hi.eq(seed + 1)).Elif(step, self.lo.eq(self.lo + 2), hi.eq(hi + 2))
        self.comb += self.hi.eq(Mux(wide, hi, self.lo))


class Stats(LiteXModule):
    def __init__(self) -> None:
        self.start, self.busy, self.check = Signal(), Signal(), Signal()
        self.beat, self.got, self.exp, self.mask = Signal(), Signal(64), Signal(64), Signal(64)
        self.resp_valid, self.resp = Signal(), Signal(2)
        self.ran = Signal()  # a run was started since reset
        self.done = Signal()
        self.resp_err = Signal()  # some response was not OKAY
        self.last_resp = Signal(2)
        self.beats, self.errs, self.cycles, self.first = Signal(32), Signal(32), Signal(32), Signal(32)
        self.d0 = Signal(64)  # the first beat's data
        self.badidx = Signal(32, reset=NO_BAD)
        seen = Signal()  # the first beat or response has been timed
        bad = self.check & (((self.got ^ self.exp) & self.mask) != 0)
        self.comb += self.done.eq(self.ran & ~self.busy & ~self.start)
        self.sync += [
            If(self.start,
               self.ran.eq(1), self.resp_err.eq(0), self.last_resp.eq(0), seen.eq(0), self.beats.eq(0),
               self.errs.eq(0), self.cycles.eq(0), self.first.eq(0), self.d0.eq(0), self.badidx.eq(NO_BAD),
            ).Else(
                If(self.busy, self.cycles.eq(self.cycles + 1)),
                If((self.beat | self.resp_valid) & ~seen, seen.eq(1), self.first.eq(self.cycles)),
                If(self.beat,
                   self.beats.eq(self.beats + 1),
                   If(self.beats == 0, self.d0.eq(self.got)),
                   If(bad, self.errs.eq(self.errs + 1), If(self.errs == 0, self.badidx.eq(self.beats)))),
                If(self.resp_valid, self.last_resp.eq(self.resp), If(self.resp != 0, self.resp_err.eq(1))),
            ),
        ]  # fmt: skip

    def status_word(self) -> object:
        """STATUS: [0] busy, [1] done, [2] a response was not OKAY, [5:4] the last response."""
        return Cat(self.busy, self.done, self.resp_err, Signal(), self.last_resp)
