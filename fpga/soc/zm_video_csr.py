"""The video pipeline's CSRs (soc/zm_video_pipe.py): the sequencer's command and
status, the picture addresses, and the counters.

The command and status fields are listed in bit order here, once: the
firmware's header is generated from them (tools/cycles_csr.py --video).
"""

from __future__ import annotations

from litex.soc.interconnect.csr import CSRField, CSRStatus, CSRStorage

CMD_FIELDS = [
    ("op", 3, "0 BG, 1 PLANE, 2 LATCH, 3 MIX, 4 PRESENT"),
    ("plane", 2, ""),
    ("line", 9, ""),
    ("mix", 1, "fold this pass into the picture"),
    ("first", 1, "... as the line's first layer"),
]
STATUS_FIELDS = [
    ("ready", 1, "no command queued or running: one may be written"),
    ("painted", 1, "the last pass has read the CPU's state"),
    ("drained", 1, "every CPU store has reached the compositor"),
    ("pending", 1, "a presented picture waits for the VBL"),
    ("front", 1, "the picture being shown"),
    ("underrun", 1, "the scanout showed a line not fetched"),
    ("overflow", 1, "a plane line was too long to fetch"),
]


class ZMVideoCSRs:
    """Mixed into ZMVideo (a LiteXModule), which collects these attributes as CSRs."""

    def _csrs(self) -> None:
        self.cmd = CSRStorage(
            fields=[CSRField(n, size=w, description=d) for n, w, d in CMD_FIELDS],
            description="Writing queues one command (rtl/video/zm_video_comp.v).",
        )
        self.status = CSRStatus(fields=[CSRField(n, size=w, description=d) for n, w, d in STATUS_FIELDS])
        self.vbase = CSRStorage(32, description="Bus address of HW_VIDEO_BASE (region offset 0).")
        self.fb0 = CSRStorage(32, description="Bus address of picture 0 (800 x 280 x 4 bytes).")
        self.fb1 = CSRStorage(32, description="Bus address of picture 1.")
        self.swaps = CSRStatus(32, description="Pictures shown so far.")
        self.frame = CSRStatus(32, description="VBLs since reset.")
        self.comp_busy = CSRStatus(32, description="Compositor clocks (`comp`) a pass was running, mod 2**32.")
        self.dma_busy = CSRStatus(32, description="Cycles (`sys`) the DMA had a burst in progress, mod 2**32.")
