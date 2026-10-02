"""Free-running counters the cart CPU reads to time itself (plan step 0b-ii).

The `standard` VexRiscv implements mcycle but does not decode it as a readable
CSR, and LiteX's timer0 uptime needs a latch write plus two reads. One 32-bit
CSR read per timestamp keeps the probe cheap enough to wrap every HBL handler.

The bus counters say how much of a span was spent waiting on memory. The sim's
main RAM answers in a cycle, so they are what turns a sim figure into a board
figure: a DDR access costs tens of cycles more, and these count the accesses.
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect.csr import CSRStatus
from migen import If, Signal

# A LiteX wishbone.Interface: untyped, its signals are attributes made at runtime.
Bus = Any

# Order matters: the firmware (fpga/cycles/board.c) reads them as an array.
COUNTERS = ["cycles", "ibus_ack", "ibus_wait", "dbus_rd", "dbus_wr", "dbus_wait"]


class ZMCycles(LiteXModule):
    """Counts sys_clk cycles and the CPU's wishbone traffic, all mod 2**32."""

    def __init__(self, ibus: Bus, dbus: Bus) -> None:
        regs = {name: CSRStatus(32, name=name, description=f"{name}, mod 2**32") for name in COUNTERS}
        for name, reg in regs.items():
            setattr(self, name, reg)
        counts = {name: Signal(32) for name in COUNTERS}
        ib_req = ibus.cyc & ibus.stb
        db_req = dbus.cyc & dbus.stb
        events = {
            "cycles": 1,
            "ibus_ack": ib_req & ibus.ack,
            "ibus_wait": ib_req & ~ibus.ack,
            "dbus_rd": db_req & dbus.ack & ~dbus.we,
            "dbus_wr": db_req & dbus.ack & dbus.we,
            "dbus_wait": db_req & ~dbus.ack,
        }
        for name in COUNTERS:
            self.sync += If(events[name], counts[name].eq(counts[name] + 1))
            self.comb += regs[name].status.eq(counts[name])
