"""A board debug probe on the compositor's read path (cycles/bdiag.c mode 4 reads it):
the first two 64-bit beats of the latest read request, latched twice,

- `axi`: at the AXI port, RDATA as the DMA hands it to the read port (sys);
- `q`:   at the far side of the sys->comp crossing, as the compositor gets it (comp).

Equal and right: the corruption is after the crossing (the compositor). `axi` right,
`q` wrong: the crossing. Both wrong: the PS or the AXI side. The comp-side latches
are read from sys as CSRs; they hold still once the pass is over, so the multi-bit
read across the clock boundary is safe for a debug read.
"""

from __future__ import annotations

from litex.gen import LiteXModule
from litex.soc.interconnect.csr import CSRStatus
from migen import Cat, If, Signal

from soc.zm_video_dma import ReadPort


class ZMHPProbe(LiteXModule):
    def __init__(self, s: ReadPort, c: ReadPort, cd_comp: str) -> None:
        """s: the DMA side of the compositor's read port (sys); c: the RTL side (cd_comp)."""
        self.probe = CSRStatus(256, description="{q1, q0, axi1, axi0}: the first 2 beats of the last read.")
        axi, q = [Signal(64) for _ in range(2)], [Signal(64) for _ in range(2)]
        self._latch(s, axi, "sys")
        self._latch(c, q, cd_comp)
        self.comb += self.probe.status.eq(Cat(axi[0], axi[1], q[0], q[1]))

    def _latch(self, port: ReadPort, beats: list[Signal], cd: str) -> None:
        n = Signal(2)
        sync = getattr(self.sync, cd)
        sync += [
            If(port.req_valid & port.req_ready, n.eq(0)),
            If(port.rsp_valid & (n < 2), n.eq(n + 1), If(n == 0, beats[0].eq(port.rsp_data)).Else(beats[1].eq(port.rsp_data))),
        ]
