"""Main RAM for the video integration sim (soc/video_sim.py): ONE memory that the
cart CPU and the video DMA share, as they share the board's one DDR.

- One 64-bit wide array, one access a cycle: the DDR's single data path. When
  both masters want it in the same cycle they alternate, so neither starves;
  bandwidth taken by one is visibly lost to the other.
- CPU port: 32-bit Wishbone, word-addressed, timed like LiteX's SRAM (the ack
  and data the cycle after the grant), so the CPU's own figures stay those of
  the cycles sim (CYCLES.md).
- DMA port: 64-bit Wishbone, a beat in the cycle it is granted, bursts held
  with `cti`: what a 64-bit AXI HP port delivers once its first beat arrives.
  The first-beat latency is zm_memtiming's job, in front of each port.
- Counters of what each port moved, for the bandwidth figures.

The array is declared with a one-word init so the Verilog reads `<name>.init`
from the run directory at time 0 (soc/cycles_sim.py does the same): one
Verilated model runs every firmware image. 64-bit words, little-endian.
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect.csr import CSRStatus
from migen import If, Memory, Mux, Replicate, Signal

# A LiteX wishbone.Interface: untyped, its signals are attributes made at runtime.
Bus = Any
COUNTERS = ["cpu_rd", "cpu_wr", "dma_rd", "dma_wr", "both"]


class ZMSimRAM(LiteXModule):
    def __init__(self, size: int, cpu: Bus, dma: Bus, name: str = "zm_ram") -> None:
        depth = size // 8
        aw = depth.bit_length() - 1
        mem = Memory(64, depth, init=[0], name=name)
        port = mem.get_port(write_capable=True, we_granularity=8, async_read=True)
        self.specials += mem, port
        cpu_ack, last_dma = Signal(), Signal()
        cpu_req = cpu.cyc & cpu.stb & ~cpu_ack
        dma_req = dma.cyc & dma.stb
        self.g_cpu = g_cpu = Signal()
        self.g_dma = g_dma = Signal()
        half = cpu.adr[0]
        self.comb += [
            g_cpu.eq(cpu_req & (~dma_req | last_dma)),
            g_dma.eq(dma_req & ~g_cpu),
            port.adr.eq(Mux(g_cpu, cpu.adr[1 : 1 + aw], dma.adr[:aw])),
            port.dat_w.eq(Mux(g_cpu, Replicate(cpu.dat_w, 2), dma.dat_w)),
            If(g_cpu & cpu.we, port.we.eq(Mux(half, cpu.sel << 4, cpu.sel))).Elif(g_dma & dma.we, port.we.eq(dma.sel)),
            dma.ack.eq(g_dma),
            dma.dat_r.eq(port.dat_r),
            cpu.ack.eq(cpu_ack),
        ]
        self.sync += [
            cpu_ack.eq(g_cpu),
            If(g_cpu, cpu.dat_r.eq(Mux(half, port.dat_r[32:], port.dat_r[:32]))),
            If(g_cpu | g_dma, last_dma.eq(g_dma)),
        ]
        self._counters(cpu, dma, cpu_req, dma_req)

    def _counters(self, cpu: Bus, dma: Bus, cpu_req: Signal, dma_req: Signal) -> None:
        events = {
            "cpu_rd": self.g_cpu & ~cpu.we,
            "cpu_wr": self.g_cpu & cpu.we,
            "dma_rd": self.g_dma & ~dma.we,
            "dma_wr": self.g_dma & dma.we,
            "both": cpu_req & dma_req,  # cycles the two masters wanted the memory at once
        }
        for name in COUNTERS:
            reg = CSRStatus(32, name=name, description=f"{name}, mod 2**32")
            setattr(self, name, reg)
            count = Signal(32)
            self.sync += If(events[name], count.eq(count + 1))
            self.comb += reg.status.eq(count)
