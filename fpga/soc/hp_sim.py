"""The board SoC's simulation (plan: "the first cart on the board"): the z7 build's
SoC (soc/zm_z7.py with the glass) as it is, but with a model of the PS in place
of the PS7, in Verilator.

    uv run python -m soc.hp_sim       # -> build/soc_hp: obj_dir/Vsim + csr.json

- Same SoC: the cart CPU (the board core, sealed, 16 KiB I$) reset into main RAM
  at CPU_BASE, main RAM on HP0 through soc/zm_hp.py's WishboneHP, the video
  pipeline's DMA on HP1 (soc/zm_video_axi.py), the glass registers holding the
  CPU in reset, ZMCycles. Built by the same calls (soc/zm_board_mem.py), so the
  CSR map is the board's: the firmware image that runs here runs there.
- The blitter (soc/zm_blit_soc.py, the board's `--blit`) on HP2; `--blit-break` builds a mutant.
- The sound core (soc/zm_audio_soc.py) on HP3, with its tap: every write landing and every
  sample goes to audio_tap.txt in the run directory (tools/audio_sim_run.py); `--audio-break`
  builds a mutant (a YM write dropped, the PCM base a byte off).
- The PS: ZMSimAXIRAM (soc/zm_simaxi.py, write channels 32-bit as on the board) answers HP0-HP3 from one 64-bit
  memory that only answers inside the DDR window (DDR_BASE), with an HP-like
  first-beat latency; and a "U-Boot" that writes the glass's CTRL.RUN over GP0
  after `BOOT_DELAY` cycles, as `mw.l 0x43c00008 1` does on the board.
- Clocks as on the board: sys 100 MHz, comp 125 MHz, pix 40 MHz. Only `--hdmi`
  is missing (no serialisers in the sim): the picture is the scanout's.
- The UART is the sim's console where the board has the JTAG UART, and
  `sim_finish` ends the run: both sit at CSR locations the board leaves alone.
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
from litex.soc.interconnect import axi
from migen import If, Module, Signal

from soc import litex_compat, zm_board_mem, zm_timing
from soc.video_sim import _CRG
from soc.zigmachine_soc import SIM_IO, ZigMachineSoC
from soc.zm_blit_soc import add_blitter
from soc.zm_hp import CPU_BASE, WINDOW, hp_interface
from soc.zm_simaxi import ZMSimAXIRAM
from soc.zm_z7 import BOARD_CORE

FPGA = Path(__file__).resolve().parent.parent
OUT = FPGA / "build/soc_hp"
SYS_CLK, COMP_CLK, PIX_CLK = int(100e6), int(125e6), int(40e6)
HP_LATENCY = 20  # sys clocks to an HP read's first beat (soc/zm_memtiming.py HP: 24 at 150 MHz)
HP_READS = 8  # read bursts an HP port accepts at a time (UG585 5.3.1, its command FIFO)
BOOT_DELAY = 64  # sys clocks before "U-Boot" releases the CPU
CTRL_RUN = (0x8, 0x1)  # gen/glass_map.py REG_CTRL, CTRL_RUN
FINISH_LOC = 31  # the last CSR page: the board has nothing there


class _UBoot(Module):
    """One AXI3 write on GP0 after `delay` clocks: CTRL = RUN, the cart CPU leaves reset."""

    def __init__(self, gp0: axi.AXIInterface, delay: int) -> None:
        wait, sent = Signal(max=delay + 1, reset=delay), Signal()
        reg, value = CTRL_RUN
        self.comb += [
            gp0.aw.addr.eq(reg), gp0.aw.len.eq(0), gp0.aw.size.eq(2), gp0.aw.burst.eq(1),
            gp0.w.data.eq(value), gp0.w.strb.eq(0xF), gp0.w.last.eq(1), gp0.b.ready.eq(1),
        ]  # fmt: skip
        self.sync += [
            If(wait != 0, wait.eq(wait - 1)),
            If((wait == 1) & ~sent, gp0.aw.valid.eq(1), gp0.w.valid.eq(1), sent.eq(1)),
            If(gp0.aw.valid & gp0.aw.ready, gp0.aw.valid.eq(0)),
            If(gp0.w.valid & gp0.w.ready, gp0.w.valid.eq(0)),
        ]


def make_soc(
    blit_break: str = "", audio_break: str = "", core: Path = BOARD_CORE, posted: int = 0, sound: bool = False
) -> ZigMachineSoC:
    platform = SimPlatform("SIM", [*SIM_IO, ("pix_clk", 0, Pins(1)), ("comp_clk", 0, Pins(1))])
    hp0, hp1, hp2, hp3 = hp_interface(), hp_interface(), hp_interface(), hp_interface()
    # the sound core and its tap (rtl/sim/zm_audio_tap.v); `sound`: its players on the sound CPU
    audio = {"hp": hp3, "tap": True, "break_": audio_break, "sound": sound}
    soc = ZigMachineSoC(
        platform, SYS_CLK, "pipe", glass=True, video_hp=hp1, hdmi=False, uart_name="sim",
        rom_size=0, main_ram_size=0, cpu_reset_address=CPU_BASE, audio=audio,
    )  # fmt: skip
    zm_board_mem.add_cpu_memory(soc, hp0, posted)
    zm_timing.use_core(soc, platform, core)
    # No OSD without a wire; and its `inside` net is a SystemVerilog keyword to Verilator.
    platform.sources = [s for s in platform.sources if not s[0].endswith("zm_glass_osd.v")]
    soc.crg = _CRG({name: platform.request(f"{name}_clk") for name in ("sys", "comp", "pix")})
    add_blitter(soc, platform, hp2, blit_break)  # the board's `--blit`: zm_blit on HP2 (soc/zm_blit_soc.py)
    ps = [zm_board_mem.hp_slice(soc, f"hp{i}", hp) for i, hp in enumerate((hp0, hp1, hp2, hp3))]  # as the board
    soc.ddr = ZMSimAXIRAM(WINDOW, ps, latency=HP_LATENCY, wr32=True, reads=HP_READS)  # the board: WRCHAN 32-bit
    soc.uboot = _UBoot(soc.glass.axi, BOOT_DELAY)
    soc.csr.add("sim_finish", n=FINISH_LOC)
    soc.sim_finish = SimFinish()
    return soc


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", type=Path, default=OUT, help="build directory")
    ap.add_argument("--blit-break", choices=["", "drop", "base"], default="", help="a blitter mutant (zm_blit_soc.py)")
    ap.add_argument("--audio-break", choices=["", "drop", "base"], default="", help="an audio mutant (zm_audio_soc.py)")
    ap.add_argument("--core", type=Path, default=BOARD_CORE, help="the CPU netlist (vexgen/gen.sh)")
    ap.add_argument("--posted", type=int, default=0, help="the CPU bridge's store buffer (soc/zm_hp_posted.py)")
    ap.add_argument("--sound-cpu", action="store_true", help="the players on the sound CPU (soc/zm_sound_cpu.py)")
    a = ap.parse_args()
    out = a.out if a.out.is_absolute() else FPGA / a.out
    litex_compat.install()
    soc = make_soc(a.blit_break, a.audio_break, a.core.resolve(), a.posted, a.sound_cpu)
    sim_config = SimConfig()
    for name, hz in (("sys_clk", SYS_CLK), ("pix_clk", PIX_CLK), ("comp_clk", COMP_CLK)):
        sim_config.add_clocker(name, freq_hz=hz)
    sim_config.add_module("serial2console", "serial")
    builder = Builder(soc, output_dir=str(out), compile_software=False)
    builder.build(sim_config=sim_config, run=False, build=True, opt_level="O3")
    deps = FPGA / ".tools/simdeps/usr"
    env = dict(os.environ, CFLAGS=f"-I{deps}/include", LDFLAGS=f"-L{deps}/lib/x86_64-linux-gnu")
    subprocess.run(["bash", "build_sim.sh"], cwd=out / "gateware", env=env, check=True)
    init = sorted((out / "gateware").glob("*zm_ddr*.init"))
    if len(init) != 1:
        raise SystemExit(f"hp_sim: expected one zm_ddr .init file, found {init}")
    meta = {"init": init[0].name, "main_ram": CPU_BASE, "main_ram_size": WINDOW, "sys_clk": SYS_CLK}
    (out / "hp_sim.json").write_text(json.dumps(meta, indent=2) + "\n")


if __name__ == "__main__":
    main()
