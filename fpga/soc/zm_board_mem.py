"""The board's memory, shared by the bitstream (soc/zm_z7.py) and its simulation
(soc/hp_sim.py) so the two are the same SoC around the PS:

    hp0, hp1 = hp_interface(), hp_interface()
    soc = ZigMachineSoC(..., video_hp=hp1, rom_size=0, main_ram_size=0, cpu_reset_address=CPU_BASE)
    add_cpu_memory(soc, hp0)
    soc.specials += ps7_instance(soc.glass.axi, hp_slice(soc, "hp0", hp0), hp_slice(soc, "hp1", hp1))  # the board
    soc.ddr = ZMSimAXIRAM(WINDOW, [hp0, hp1])                     # the sim

- main_ram: the 32 MiB cart window at CPU_BASE, through WishboneHP onto HP0
  (soc/zm_hp.py). No boot ROM: the CPU's reset vector IS the window's first
  word, and the glass holds the CPU in reset (CTRL.RUN) until the ARM has put
  the firmware image there.
- ZMCycles: the cycle counter the firmware times its waits with (cycles/board.h).
- The PS7: ONE primitive with M_AXI_GP0 (the glass), S_AXI_HP0 (the CPU),
  S_AXI_HP1 (the video DMA), with `--blit` S_AXI_HP2 (the blitter,
  soc/zm_blit_soc.py) and, unless `--no-audio`, S_AXI_HP3 (the audio core's PCM
  reads, soc/zm_audio_soc.py), every port clocked from sys.
"""

from __future__ import annotations

from typing import Any

from litex.soc.integration.soc import SoCRegion
from litex.soc.interconnect import axi, stream, wishbone
from migen import Cat, ClockSignal, Instance

from soc.zm_cycles import ZMCycles
from soc.zm_glass import ps7_gp0
from soc.zm_hp import CPU_BASE, WINDOW, WINDOW_LOG2, WishboneHP, hp_interface, ps7_hp_ports

# A LiteX SoC: untyped, its submodules are attributes made at runtime.
SoC = Any


def add_cpu_memory(soc: SoC, hp0: axi.AXIInterface, posted: int = 0) -> None:
    """main_ram at CPU_BASE on HP0, and the firmware's cycle counter. `posted`: the bridge's
    store buffer (soc/zm_hp_posted.py), 0 = blocking stores; its `idle` drives the SoC's
    `stores_idle`, which the video's `drained` and the blitter's start wait for."""
    bus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
    soc.main_ram_hp = WishboneHP(bus, hp0, posted)
    soc.comb += soc.stores_idle.eq(soc.main_ram_hp.idle)
    soc.bus.add_slave("main_ram", bus, SoCRegion(origin=CPU_BASE, size=WINDOW, mode="rwx"))
    soc.zm_cycles = ZMCycles(soc.cpu.ibus, soc.cpu.dbus)


def hp_slice(soc: SoC, name: str, master: axi.AXIInterface) -> axi.AXIInterface:
    """A full register slice between an HP master and the PS7, returned as the PS7's side:
    every PS7 pin of the port meets a flip-flop and nothing else. nextpnr-xilinx times no
    path into or out of the PS7 (its timing report has none), so logic on those pins is
    placement luck (2026-10-04: the cart CPU dead on some builds of one netlist); with the
    slice an untimed route is one wire into one flop. Costs a clock each way.

    The slice also places the cart window: every master addresses it at zm_hp.DDR_BASE, and the
    AW/AR address leaves with bits 31..25 replaced by the glass's LOAD_BASE (reset: the same
    DDR_BASE, U-Boot's window; under Linux the glass writes 0x1E00_0000 before CTRL.RUN). The
    masters only run while CTRL.RUN, so the base never changes under a burst."""
    ps = hp_interface()
    glass = getattr(soc, "glass", None)
    for ch, out in (("aw", True), ("w", True), ("ar", True), ("b", False), ("r", False)):
        src, dst = (getattr(master, ch), getattr(ps, ch)) if out else (getattr(ps, ch), getattr(master, ch))
        # Outbound (aw/w/ar) the payload and valid leave from flip-flops (pipe_valid) and READY
        # comes back combinationally: the skid half (pipe_ready) put a 2:1 mux on every PS7 pin
        # (~450 LUT, ~1,000 FF over four ports). Vivado times the PS7's pins, unlike nextpnr-xilinx.
        # Inbound (b/r) keeps both halves, so RREADY/BREADY leave from a flop too.
        buf = stream.Buffer(src.description, pipe_valid=True, pipe_ready=not out)
        setattr(soc, f"{name}_{ch}_slice", buf)
        if ch in ("aw", "ar") and glass is not None:
            soc.comb += [
                src.connect(buf.sink, omit={"addr"}),
                buf.sink.addr.eq(Cat(src.addr[:WINDOW_LOG2], glass.load_base[WINDOW_LOG2:])),
            ]
        else:
            soc.comb += src.connect(buf.sink)
        soc.comb += buf.source.connect(dst)
    return ps


def ps7_instance(
    gp0: axi.AXIInterface,
    hp0: axi.AXIInterface,
    hp1: axi.AXIInterface,
    hp2: axi.AXIInterface | None = None,
    hp3: axi.AXIInterface | None = None,
) -> Instance:
    """The PS7 with GP0 (soc/zm_glass.py's wiring, reused as is) plus HP0, HP1 and, with the
    blitter (soc/zm_blit_soc.py), HP2, and with the audio (soc/zm_audio_soc.py), HP3."""
    clk = ClockSignal("sys")
    more = {}
    for name, hp in (("SAXIHP2", hp2), ("SAXIHP3", hp3)):
        if hp is not None:
            more |= ps7_hp_ports(name, hp, clk)
    ps7 = Instance("PS7", **ps7_hp_ports("SAXIHP0", hp0, clk), **ps7_hp_ports("SAXIHP1", hp1, clk), **more)
    ps7.items += ps7_gp0(gp0).items
    return ps7
