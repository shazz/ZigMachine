"""The video integration sim (Fable #9): the cart CPU running a translated cart,
the RTL video pipeline, and one shared main RAM, in Verilator.

    uv run python -m soc.video_sim     # -> build/soc_video: obj_dir/Vsim + csr.json

- The cart CPU (VexRiscv `standard`, as soc/cycles_sim.py) runs the cycles
  firmware built with the video sequencer (fpga/cycles/vseq.c): the machine's
  frame order, the HBL handlers as calls between the compositor's passes.
- The video pipeline (soc/zm_video_pipe.py) without DVI: the compositor builds
  each frame into a picture in main RAM, the scanout fetch reads the previous
  one back in the 40 MHz pixel clock's time.
- Main RAM is ONE memory both masters share (soc/zm_simram.py), with the
  board's memory-path model (soc/zm_memtiming.py) in front of EACH master: the
  CPU's reads zm_memcfg.init, the video DMA's zm_dmacfg.init, from the run
  directory (tools/video_sim_run.py writes them).
- The CPU's stores reach the compositor through the snoop (soc/zm_video_snoop.py)
  on the CPU's main-RAM path, delivered at the store buffer's drain rate.

The clocks: sys at 160 MHz, pix at 40 MHz (4:1; the sim's clocker needs whole
picosecond half-periods, which 150 MHz has not). Every figure is in sys cycles.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

from litex.build.generic_platform import Pins
from litex.build.sim import SimPlatform
from litex.build.sim.config import SimConfig
from litex.build.sim.platform import SimFinish
from litex.soc.integration.builder import Builder
from litex.soc.integration.soc import SoCRegion
from litex.soc.interconnect import wishbone
from migen import ClockDomain, If, Instance, Module, Signal

from soc import litex_compat
from soc.zigmachine_soc import SIM_IO, ZigMachineSoC
from soc.zm_cycles import ZMCycles
from soc.zm_memtiming import ZMMemTiming
from soc.zm_simram import ZMSimRAM
from soc.zm_video_pipe import WINDOW_BYTES, ZMVideo
from soc.zm_video_snoop import ZMVideoSnoop, attach_snoop

FPGA = Path(__file__).resolve().parent.parent
OUT = FPGA / "build/soc_video"
SYS_CLK, PIX_CLK = int(160e6), int(40e6)
MAIN_RAM, MAIN_RAM_SIZE = 0x40000000, 32 << 20  # as soc/cycles_sim.py: cycles/cycles.mk links for it
WINDOW = 0x90000000  # the compositor's register read-back, in the uncached IO region


class _CRG(Module):
    """sys and pix from the sim's two clockers, each with a power-on reset."""

    def __init__(self, sys_clk: Signal, pix_clk: Signal) -> None:
        self.clock_domains.cd_sys = ClockDomain()
        self.clock_domains.cd_pix = ClockDomain()
        self.clock_domains.cd_por = ClockDomain(reset_less=True)
        self.clock_domains.cd_por_pix = ClockDomain(reset_less=True)
        por, por_pix = Signal(4, reset=15), Signal(4, reset=15)
        self.comb += [
            self.cd_sys.clk.eq(sys_clk),
            self.cd_por.clk.eq(sys_clk),
            self.cd_sys.rst.eq(por != 0),
            self.cd_pix.clk.eq(pix_clk),
            self.cd_por_pix.clk.eq(pix_clk),
            self.cd_pix.rst.eq(por_pix != 0),
        ]
        self.sync.por += If(por != 0, por.eq(por - 1))
        self.sync.por_pix += If(por_pix != 0, por_pix.eq(por_pix - 1))


def add_memory(soc: ZigMachineSoC, platform: SimPlatform) -> None:
    """CPU: interconnect -> snoop -> memtiming -> RAM; video DMA: memtiming -> RAM."""
    word32 = {"data_width": 32, "address_width": 32, "addressing": "word"}
    word64 = {"data_width": 64, "address_width": 32, "addressing": "word"}
    bus, snooped, timed = (wishbone.Interface(**word32) for _ in range(3))
    dma_timed = wishbone.Interface(**word64)
    dma_cfg = Signal(512)
    soc.specials += Instance("zm_memcfg", p_FILE="zm_dmacfg.init", o_cfg=dma_cfg)
    soc.main_ram_timing = ZMMemTiming(snooped, timed)
    soc.dma_timing = ZMMemTiming(soc.zmv.dma, dma_timed, dma_cfg)
    drain = soc.main_ram_timing.cfg["sb_drain"]
    soc.zmv_snoop = ZMVideoSnoop(bus, snooped, soc.zmv.vbase.storage, drain)
    soc.main_ram = ZMSimRAM(MAIN_RAM_SIZE, timed, dma_timed)
    soc.bus.add_slave("main_ram", bus, SoCRegion(origin=MAIN_RAM, size=MAIN_RAM_SIZE, mode="rwx"))
    soc.comb += attach_snoop(soc.zmv, soc.zmv_snoop)
    soc.comb += soc.zmv.drained.eq(soc.zmv_snoop.empty & soc.main_ram_timing.sb_empty)
    platform.add_source(str(FPGA / "rtl/sim/zm_memcfg.v"))


def make_soc() -> ZigMachineSoC:
    platform = SimPlatform("SIM", [*SIM_IO, ("pix_clk", 0, Pins(1))])
    soc = ZigMachineSoC(
        platform, SYS_CLK, "sys", rom_size=0, main_ram_size=0, uart_name="sim", cpu_reset_address=MAIN_RAM
    )
    soc.crg = _CRG(platform.request("sys_clk"), platform.request("pix_clk"))
    soc.zmv = ZMVideo(platform, None, cd_pix="pix", max_burst=0)
    soc.bus.add_slave("zmv_window", soc.zmv.bus, SoCRegion(origin=WINDOW, size=WINDOW_BYTES, cached=False))
    add_memory(soc, platform)
    soc.zm_cycles = ZMCycles(soc.cpu.ibus, soc.cpu.dbus)
    soc.sim_finish = SimFinish()
    return soc


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", type=Path, default=OUT, help="build directory")
    a = ap.parse_args()
    out = a.out if a.out.is_absolute() else FPGA / a.out
    litex_compat.install()
    soc = make_soc()
    sim_config = SimConfig()
    sim_config.add_clocker("sys_clk", freq_hz=SYS_CLK)
    sim_config.add_clocker("pix_clk", freq_hz=PIX_CLK)
    sim_config.add_module("serial2console", "serial")
    builder = Builder(soc, output_dir=str(out), compile_software=False)
    builder.build(sim_config=sim_config, run=False, build=True, opt_level="O3")
    deps = FPGA / ".tools/simdeps/usr"
    env = dict(os.environ, CFLAGS=f"-I{deps}/include", LDFLAGS=f"-L{deps}/lib/x86_64-linux-gnu")
    subprocess.run(["bash", "build_sim.sh"], cwd=out / "gateware", env=env, check=True)
    init = sorted((out / "gateware").glob("*zm_ram*.init"))
    if len(init) != 1:
        raise SystemExit(f"video_sim: expected one zm_ram .init file, found {init}")
    meta = {"init": init[0].name, "main_ram": MAIN_RAM, "main_ram_size": MAIN_RAM_SIZE, "sys_clk": SYS_CLK}
    (out / "video_sim.json").write_text(json.dumps(meta, indent=2) + "\n")


if __name__ == "__main__":
    main()
