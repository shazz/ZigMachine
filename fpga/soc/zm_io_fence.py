"""The cart CPU's IO stores wait for its posted DDR stores (soc/zm_hp_posted.py).

With HP0's stores posted, "acknowledged" no longer means "in DDR". The consumers on the
SoC's own side already wait for `stores_idle` (the bridge's reads, the video's `drained`,
the CHISEL start). Another master that reads DDR when the cart CPU TELLS it to through an
IO register does not see `stores_idle`, and would read what the buffer still holds:
- BARD (SOUND_WINDOW, cycles/bsound.c): the cart writes a sound command's words, then SEQ;
  the sound CPU then reads the PCM / song bytes the command names, over HP3;
- CHORUS (AUDIO_WINDOW, without the sound CPU): a stamped Paula write names PCM the
  players just wrote, read over HP3;
- the glass and the video pipe (CSRs, VIDEO_WINDOW): any doorbell after a DDR store.

So a STORE to the IO space (byte address bit 31: every window but main_ram, which sits at
CPU_BASE = 0x4000_0000) is held off the interconnect until `idle`: release ordering, as a
fence before every device write. Loads are not held (no consumer needs it, and a poll loop
would pay for the drain on every read). Once an IO store has been let through, `idle` cannot
fall under it: only this CPU's D-bus pushes stores into the buffer, and it is busy with the
IO store (the I-bus only reads).

DDR-only protocols (the debug mailbox, the cart request block: data first, magic last) need
no fence: the buffer drains in program order on one AXI ID with AWCACHE 0000 (Device
non-bufferable: each B response comes from DDR, same-ID writes complete in order).
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect import wishbone
from migen import Signal

from soc.zm_hp import CPU_BASE

# A LiteX wishbone.Interface / SoC: untyped, their signals are attributes made at runtime.
Bus = Any
SoC = Any
IO_BIT = 29  # word-address bit of byte address bit 31: the uncached IO space


class IOFence(LiteXModule):
    """`master` (the CPU's D-bus) -> `self.bus` (to the interconnect), with stores to the IO
    space held until `idle`. `break_` = "nofence": the break test's mutant, no hold."""

    def __init__(self, master: Bus, idle: Signal, break_: str = "", regions: dict[str, Any] | None = None) -> None:
        self._regions = regions  # the SoC's bus regions, checked once they are all known (do_finalize)
        assert len(master.adr) == 30, "a word-addressed 32-bit bus: bit 29 is byte bit 31"
        self.bus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        self.hold = Signal()
        io_store = master.we & master.adr[IO_BIT]
        self.comb += [
            master.connect(self.bus, omit={"cyc", "stb"}),
            self.hold.eq(0 if break_ == "nofence" else io_store & ~idle),
            self.bus.cyc.eq(master.cyc & ~self.hold),
            self.bus.stb.eq(master.stb & ~self.hold),
        ]

    def do_finalize(self) -> None:
        """Every slave but main_ram must sit in the IO space, or its stores would pass unfenced
        (or main_ram's would be held). Run after the SoC's own finalize has added its CSR bridge."""
        for name, region in (self._regions or {}).items():
            if (region.origin >= 1 << 31) == (region.origin == CPU_BASE):
                raise ValueError(f"zm_io_fence: {name} at {region.origin:#x} breaks the IO-space split")


def fence_cpu_io(soc: SoC, idle: Signal, break_: str = "") -> None:
    """Put an IOFence between the cart CPU's D-bus and the SoC interconnect (built at
    finalize, from `soc.bus.masters`); the taps keep watching the CPU's side."""
    names = [k for k, m in soc.bus.masters.items() if m is soc.cpu.dbus]
    if len(names) != 1:
        raise ValueError(f"zm_io_fence: the CPU's D-bus is not one bus master ({names})")
    soc.io_fence = IOFence(soc.cpu.dbus, idle, break_, soc.bus.regions)
    soc.bus.masters[names[0]] = soc.io_fence.bus
