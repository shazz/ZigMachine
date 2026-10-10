"""The hp-test bitstream's registers (soc/zm_hp_test.py): an AXI3 slave on the PS's
M_AXI_GP0, so U-Boot drives them with `mw.l` / `md.l` at 0x43c0_0000 (any address in
the GP0 window decodes; only the low 12 bits are looked at).

LiteX's AXI2AXILite cuts GP0's bursts into single beats and axi_lite_to_simple turns
those into a 1-cycle register port; `GP0Regs` hangs storage registers and read-only
signals on it, by word index.
"""

from __future__ import annotations

from litex.gen import LiteXModule
from litex.soc.interconnect import axi
from litex.soc.interconnect.axi.axi_full_to_axi_lite import AXI2AXILite
from litex.soc.interconnect.axi.axi_lite import axi_lite_to_simple
from migen import Case, Constant, If, Signal

ADDR_WORDS = 10  # 4 KiB of register space: a 0x400-byte bank per port is plenty


def gp0_interface() -> axi.AXIInterface:
    """M_AXI_GP0 as the PS7 primitive has it (soc/zm_glass.py ZMGlass.axi)."""
    return axi.AXIInterface(data_width=32, address_width=32, id_width=12, version="axi3")


class GP0Regs(LiteXModule):
    """Word-indexed registers on `gp0`. Call `storage()` / `status()` while building,
    then `finalize` (LiteX runs it) builds the decoder."""

    def __init__(self, gp0: axi.AXIInterface) -> None:
        lite = axi.AXILiteInterface(data_width=32, address_width=32)
        self.bridge = AXI2AXILite(gp0, lite)
        self.adr, self.dat_r, self.dat_w, self.we = Signal(ADDR_WORDS), Signal(32), Signal(32), Signal()
        self.fsm, comb = axi_lite_to_simple(lite, self.adr, self.dat_r, self.dat_w, port_we=self.we)
        self.comb += comb
        self._reads: dict[int, Signal | Constant] = {}
        self._writes: dict[int, Signal] = {}
        self.strobes: dict[int, Signal] = {}  # word -> a 1-cycle pulse on every write to it

    def storage(self, word: int, width: int = 32, reset: int = 0) -> Signal:
        """A read/write register at `word`."""
        reg = Signal(width, reset=reset, name=f"hpt_reg{word:03x}")
        self._writes[word] = reg
        self._reads[word] = reg
        return reg

    def status(self, word: int, sig: Signal | Constant) -> None:
        """A read-only signal at `word` (writes are ignored)."""
        self._reads[word] = sig

    def strobe(self, word: int) -> Signal:
        """A write-only pulse register at `word` (reads 0): the data is in `dat_w`."""
        pulse = Signal(name=f"hpt_go{word:03x}")
        self.strobes[word] = pulse
        return pulse

    def do_finalize(self) -> None:
        # axi_lite_to_simple wants the read data one cycle after the address (a CSR-bus port).
        reads = {w: self.dat_r.eq(sig) for w, sig in self._reads.items()}
        self.sync += Case(self.adr, {**reads, "default": self.dat_r.eq(0)})
        self.sync += If(self.we, Case(self.adr, {w: reg.eq(self.dat_w) for w, reg in self._writes.items()}))
        for w, pulse in self.strobes.items():
            self.comb += pulse.eq(self.we & (self.adr == w))
