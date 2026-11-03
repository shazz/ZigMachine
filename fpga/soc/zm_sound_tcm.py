"""BARD's data scratchpad (fpga/review/BARD_BRAM_STUDY.md): a BRAM on the core's tightly coupled
data port, for the `tcm` core (vexgen/gen.sh `SndNdT:...:snd,nodiv,tcm`, vexgen ZmTcm.scala).

- **Where**: TCM_BASE, decoded by the core itself (a 256 KiB window); `size` bytes of BRAM behind
  it, aliased inside the window. A load there costs a D$ hit and never misses; nothing else in the
  SoC can see it (no second port): the players' private tables and state, never a buffer ZIGGY or
  CHORUS reads.
- **Timing**: the core drives `dTcm_*` in EXECUTE (enable only while that stage moves on) and takes
  `read_data` in MEMORY, one clock later: a synchronous read port with a read enable, so the word
  holds while MEMORY is stuck.
- **Contents**: undefined at reset (BRAM init is zeros in the sim); the firmware copies or computes
  what it places there (a linker section, cycles/sound/README of the study).
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from migen import Memory, Replicate, Signal

TCM_BASE = 0x9E000000  # vexgen ZmTcm.BASE


class SoundTcm(LiteXModule):
    """`size` bytes of 32-bit BRAM; `ports()` are the core Instance's dTcm_* connections."""

    def __init__(self, size: int) -> None:
        if size <= 0 or size & (size - 1) or size > 1 << 18:
            raise ValueError(f"TCM size {size}: a power of two up to the 256 KiB window")
        words = size // 4
        self.en, self.we = Signal(), Signal()
        self.adr, self.dat_w, self.dat_r, self.mask = Signal(32), Signal(32), Signal(32), Signal(4)
        mem = Memory(32, words, name="zm_snd_tcm")  # a local: as an attribute, LiteX would map it as a CSR
        rd = mem.get_port(has_re=True)
        wr = mem.get_port(write_capable=True, we_granularity=8)
        self.specials += mem, rd, wr
        word = self.adr[2 : 2 + (words - 1).bit_length()]
        self.comb += [
            rd.adr.eq(word), rd.re.eq(self.en), self.dat_r.eq(rd.dat_r),
            wr.adr.eq(word), wr.dat_w.eq(self.dat_w),
            wr.we.eq(self.mask & Replicate(self.en & self.we, 4)),
        ]  # fmt: skip

    def ports(self) -> dict[str, Any]:  # Any: Migen signals, as Instance takes them
        return {
            "o_dTcm_enable": self.en, "o_dTcm_address": self.adr, "o_dTcm_write_enable": self.we,
            "o_dTcm_write_data": self.dat_w, "o_dTcm_write_mask": self.mask, "i_dTcm_read_data": self.dat_r,
        }  # fmt: skip
