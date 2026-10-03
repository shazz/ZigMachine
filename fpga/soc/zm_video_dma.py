"""The video pipeline's memory master: the compositor's read and write ports and
the scanout fetch's read port (rtl/video/README.md "Memory"), served over one
64-bit Wishbone master in bursts.

Every port asks for a burst (an address and a beat count, rows are 400 beats);
the DMA serves one burst at a time, the scanout first (it has the only
deadline), then the compositor's writes, then its reads. A burst is one
Wishbone cycle with `cti` = incrementing on every beat but the last, so the
memory path's first-beat latency (soc/zm_memtiming.py) is paid once per burst,
as an AXI HP master with several bursts outstanding pays it once per stream.
On the board this is the AXI master toward HP0; `max_burst` then splits a
request into AXI bursts (16 beats), and is 0 (whole requests) in the sim.

Addresses are bus byte addresses; the Wishbone address is the 64-bit word.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect import wishbone
from migen import If, Mux, Signal

CTI_INCR, CTI_END = 0b010, 0b111
# A LiteX wishbone.Interface: untyped, its signals are attributes made at runtime.
Bus = Any


@dataclass
class ReadPort:
    req_valid: Signal
    req_ready: Signal
    req_addr: Signal
    req_len: Signal
    rsp_valid: Signal
    rsp_data: Signal


@dataclass
class WritePort:
    req_valid: Signal
    req_ready: Signal
    req_addr: Signal
    req_len: Signal
    dat_valid: Signal
    dat_ready: Signal
    dat: Signal
    busy: Signal


def read_port(prefix: str) -> ReadPort:
    widths = {"req_valid": 1, "req_ready": 1, "req_addr": 32, "req_len": 10, "rsp_valid": 1, "rsp_data": 64}
    return ReadPort(**{k: Signal(w, name=f"{prefix}_{k}") for k, w in widths.items()})


def write_port(prefix: str) -> WritePort:
    widths = {"req_valid": 1, "req_ready": 1, "req_addr": 32, "req_len": 10}
    widths |= {"dat_valid": 1, "dat_ready": 1, "dat": 64, "busy": 1}
    return WritePort(**{k: Signal(w, name=f"{prefix}_{k}") for k, w in widths.items()})


class ZMVideoDMA(LiteXModule):
    """Serves `reads` and one `write` port over `self.bus`. Priority: reads[0] (the
    scanout), the write, then the other reads."""

    def __init__(self, reads: list[ReadPort], write: WritePort, max_burst: int = 0) -> None:
        self.bus = bus = wishbone.Interface(data_width=64, address_width=32, addressing="word")
        self.active = Signal()  # a burst is in progress (for the busy counters)
        self.is_wr = is_wr = Signal()
        self.rd_sel = Signal(max(1, (len(reads) - 1).bit_length()))
        self.adr, self.left = Signal(29), Signal(10)
        # The last beat of a request, or of an AXI burst: the next beat pays the latency again.
        last = self.left == 1
        if max_burst:
            assert max_burst & (max_burst - 1) == 0, "AXI bursts here are a power of two beats"
            last = last | (self.adr[: max_burst.bit_length() - 1] == max_burst - 1)
        beat = bus.cyc & bus.stb & bus.ack
        self._grant(reads, write)
        self.comb += [
            bus.cyc.eq(self.active),
            bus.stb.eq(self.active & (~is_wr | write.dat_valid)),
            bus.we.eq(is_wr),
            bus.sel.eq(0xFF),
            bus.adr.eq(self.adr),
            bus.dat_w.eq(write.dat),
            bus.cti.eq(Mux(last, CTI_END, CTI_INCR)),
            write.dat_ready.eq(is_wr & beat),
            write.busy.eq(self.active & is_wr),
        ]
        for i, port in enumerate(reads):
            self.comb += [port.rsp_valid.eq(~is_wr & (self.rd_sel == i) & beat), port.rsp_data.eq(bus.dat_r)]
        self.sync += If(
            beat, self.adr.eq(self.adr + 1), self.left.eq(self.left - 1), If(last & (self.left == 1), self.active.eq(0))
        )

    def _grant(self, reads: list[ReadPort], write: WritePort) -> None:
        """When idle, the highest-priority request is granted (its req_ready) and loaded."""
        order: list[tuple[ReadPort | WritePort, int]] = [(reads[0], 0), (write, -1)]
        order += [(reads[i], i) for i in range(1, len(reads))]
        taken = Signal()  # a higher-priority port asked this cycle
        for port, i in order:
            grant, before = Signal(), taken
            taken = Signal()
            self.comb += [grant.eq(~self.active & port.req_valid & ~before), taken.eq(before | port.req_valid)]
            self.comb += port.req_ready.eq(grant)
            load = [self.active.eq(1), self.is_wr.eq(i < 0), self.adr.eq(port.req_addr[3:]), self.left.eq(port.req_len)]
            if i >= 0:
                load.append(self.rd_sel.eq(i))
            self.sync += If(grant, *load)
