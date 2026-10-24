"""The Z7-Lite board build of soc/zigmachine_soc.py: its clocks and its CPU core.

    uv run python -m soc.zigmachine_soc --target z7 --build      # bitstream, openXC7 in Docker

- **Clocks** (one PLL off the 50 MHz PL oscillator): `sys` for the CPU and the
  bus, `comp` for the compositor (rtl/video, crossing in soc/zm_video_cdc.py),
  `pix` (40 MHz, 800x600 at 60 Hz) and `pix5x` for the TMDS serialisers. sys and
  comp are separate because the compositor closes timing well above the CPU
  and both share one frame budget (fpga/README.md "Timing under openXC7").
- **CPU**: the board core is VexRiscv with a 16 KiB 2-way I$, the seal and
  static branch prediction (`BOARD_CORE`, made by `make -C fpga vexgen-board`).
  The same core WITHOUT prediction (`NOPRED_CORE`, same target) closes ~8 % more
  sys fmax over a seed sweep but costs 16-25 % more cycles a frame, so it loses
  (fpga/CYCLES.md "Branch prediction and the clock"). `--cpu-netlist <path>`
  takes any vexgen netlist; `--cpu-netlist standard` LiteX's own core.
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

from litex.soc.cores.clock import S7PLL
from litex.soc.integration.builder import Builder
from migen import ClockDomain, Module

from soc import openxc7, zm_board_mem, zm_timing
from soc.zigmachine_soc import PIX_CLK, ZigMachineSoC
from soc.zm_blit_soc import add_blitter
from soc.zm_hp import CPU_BASE, hp_interface

FPGA = Path(__file__).resolve().parent.parent
SYS_CLK = int(100e6)
COMP_CLK = int(125e6)
BOARD_CORE = FPGA / "build/vexgen/VexRiscv_I16w2D4Seal.v"
NOPRED_CORE = FPGA / "build/vexgen/VexRiscv_I16w2D4SealNopred.v"
STANDARD = "standard"  # --cpu-netlist: LiteX's own VexRiscv


class Z7CRG(Module):
    """sys, comp, the 40 MHz pixel clock and its 5x, from the board's PL oscillator."""

    def __init__(self, platform: object, osc: tuple[str, int], sys_hz: int, comp_hz: int) -> None:
        osc_name, osc_hz = osc
        self.clock_domains.cd_sys = ClockDomain()
        self.clock_domains.cd_comp = ClockDomain()
        self.clock_domains.cd_pix = ClockDomain()
        self.clock_domains.cd_pix5x = ClockDomain()
        self.submodules.pll = pll = S7PLL(speedgrade=-1)
        clkin = platform.request(osc_name)  # type: ignore[attr-defined]  # untyped LiteX platform
        # The input period is what timing analysis derives every PLL output from:
        # without it nextpnr checks all clocks against its 12 MHz default.
        platform.add_period_constraint(clkin, 1e9 / osc_hz)  # type: ignore[attr-defined]  # untyped LiteX platform
        pll.register_clkin(clkin, osc_hz)
        # The sys reset reaches every flop with an R pin: from the synchronizer's last FDPE
        # (ASYNC_REG, so Vivado never replicates it) it was 11.5 ns of route, the worst path of the
        # --blit SoC at 100 MHz (2026-10-10). A BUFG carries it on the clock network instead.
        pll.create_clkout(self.cd_sys, sys_hz, reset_buf="bufg")
        if comp_hz == sys_hz:
            # One clock: every sys<->comp crossing becomes a TIMED same-clock path. The board's
            # failures moved with placement on the crossings nextpnr never times (docs/FPGA_STEPS.md).
            self.comb += [self.cd_comp.clk.eq(self.cd_sys.clk), self.cd_comp.rst.eq(self.cd_sys.rst)]
        else:
            pll.create_clkout(self.cd_comp, comp_hz, reset_buf="bufg")
        pll.create_clkout(self.cd_pix, PIX_CLK)
        pll.create_clkout(self.cd_pix5x, 5 * PIX_CLK)
        # The PLL's CLKOUT index of each clock, in create_clkout order: Vivado names them by it.
        comp = 0 if comp_hz == sys_hz else 1
        self.clkout = {"sys": 0, "comp": comp, "pix": comp + 1, "pix5x": comp + 2}


def core_netlist(choice: str | None) -> Path | None:
    """The VexRiscv netlist to build around, or None for LiteX's `standard`."""
    if choice == STANDARD:
        return None
    netlist = Path(choice).resolve() if choice else BOARD_CORE
    if not netlist.exists():
        hint = "make -C fpga vexgen-board" if netlist in (BOARD_CORE, NOPRED_CORE) else "vexgen/gen.sh"
        raise FileNotFoundError(f"{netlist}: generate it with `{hint}` (or pass --cpu-netlist {STANDARD})")
    return netlist


def make_z7(args: argparse.Namespace) -> tuple[ZigMachineSoC, object]:
    """The board's SoC and its platform (tools/soc_util.py synthesises them)."""
    from soc import litex_compat
    from soc.platform_z7 import Platform

    litex_compat.install()  # Verilog is written here, see soc/litex_compat.py
    platform = Platform(toolchain=args.toolchain)
    # TIMING (fpga/README.md "Timing under openXC7"): --sys-mhz, --comp-mhz, --cpu-netlist, the CDC constraints.
    sys_hz = int(getattr(args, "sys_mhz", SYS_CLK / 1e6) * 1e6)
    comp_hz = int(getattr(args, "comp_mhz", COMP_CLK / 1e6) * 1e6)
    # The Z7-Lite UART is on PS MIO (the ARM's), not PL pins: the console runs over USB-JTAG.
    audio = not getattr(args, "no_audio", False)
    sound = getattr(args, "sound_cpu", False)
    if sound and not audio:
        raise SystemExit("zm_z7: --sound-cpu needs the audio core (drop --no-audio)")
    soc = _board_soc(
        platform,
        sys_hz,
        not args.no_glass,
        getattr(args, "blit", False),
        audio,
        sound,
        getattr(args, "hp_probe", False),
        getattr(args, "posted", zm_board_mem.POSTED),
    )
    soc.crg = crg = Z7CRG(platform, (args.osc, args.osc_hz), sys_hz, comp_hz)
    soc.csr_bridge_register = True
    clocks = {
        "sys": (crg.cd_sys.clk, sys_hz, crg.clkout["sys"]),
        "comp": (crg.cd_comp.clk, comp_hz, crg.clkout["comp"]),
        "pix": (crg.cd_pix.clk, PIX_CLK, crg.clkout["pix"]),
    }
    pairs = [("sys", "pix")] + ([] if comp_hz == sys_hz else [("comp", "pix"), ("sys", "comp")])
    zm_timing.add_cdc_constraints(platform, clocks, pairs)
    netlist = core_netlist(getattr(args, "cpu_netlist", None))
    if netlist is not None:
        zm_timing.use_core(soc, platform, netlist)
    return soc, platform


def _board_soc(
    platform: object,
    sys_hz: int,
    glass: bool,
    blit: bool = False,
    audio: bool = True,
    sound: bool = False,
    hp_probe: bool = False,
    posted: int = zm_board_mem.POSTED,
) -> ZigMachineSoC:
    """With the glass: the cart CPU's RAM and the video DMA in PS DDR over HP0/HP1, the CPU
    reset into it (soc/zm_board_mem.py), with `blit` the blitter on HP2 (soc/zm_blit_soc.py),
    and with `audio` the sound core on HP3 and HDMI with audio (soc/zm_audio_soc.py); with `sound`
    the players on the sound CPU, sharing HP3 with the core's PCM (soc/zm_sound_cpu.py).
    Without the glass: on-chip RAM and the BIOS, run over JTAG, DVI only."""
    if not glass:
        return ZigMachineSoC(platform, sys_hz, "pipe", uart_name="jtag_uart")
    hp0, hp1 = hp_interface(), hp_interface()
    hp3 = hp_interface() if audio else None
    # The console is a stub: with the glass nothing reads the JTAG UART (cycles/bboard.c prints
    # nothing under ZM_BOARD), and its PHY and FIFOs cost LUTs. Same CSRs, so the same map as the sim.
    soc = ZigMachineSoC(
        platform, sys_hz, "pipe", glass=True, video_hp=hp1, uart_name="stub",
        rom_size=0, main_ram_size=0, cpu_reset_address=CPU_BASE, audio=None if hp3 is None else {"hp": hp3, "sound": sound},
        hp_probe=hp_probe,
    )  # fmt: skip
    zm_board_mem.add_cpu_memory(soc, hp0, posted)  # ZIGGY's stores posted (soc/zm_io_fence.py), 0 = blocking
    hp2 = hp_interface() if blit else None
    if hp2 is not None:
        add_blitter(soc, platform, hp2)
    # Every HP port through a register slice at the PS7 (zm_board_mem.hp_slice: its pins are untimed).
    hps = (hp0, hp1, hp2, hp3)
    ps = [None if hp is None else zm_board_mem.hp_slice(soc, f"hp{i}", hp) for i, hp in enumerate(hps)]
    soc.specials += zm_board_mem.ps7_instance(soc.glass.axi, *ps)
    return soc


# Named place/route directive sets (--vivado-directives); `explore` is also --vivado-explore.
# explore: Vivado's harder passes (about 2x the build time); the --blit SoC at 100 MHz was ~62 % LUTs
# and its last misses were placement, not logic.
# closure: what closed the 89 % LUT board build with the copper engine (bitstream c72c58ca,
# 2026-10-24): the default directives missed sys by -0.258 ns (a blitter path) or comp by -0.24 ns,
# ExtraTimingOpt failed to place; spreading the logic met every clock (sys +0.068, comp +0.353).
DIRECTIVES = {
    "default": {},
    "explore": {
        "vivado_place_directive": "ExtraTimingOpt",
        "vivado_post_place_phys_opt_directive": "AggressiveExplore",
        "vivado_route_directive": "AggressiveExplore",
        "vivado_post_route_phys_opt_directive": "AggressiveExplore",
    },
    "closure": {
        "vivado_place_directive": "AltSpreadLogic_high",
        "vivado_post_place_phys_opt_directive": "AggressiveExplore",
        "vivado_route_directive": "Explore",
        "vivado_post_route_phys_opt_directive": "AggressiveExplore",
    },
}
EXPLORE = DIRECTIVES["explore"]
# Vivado's threads: each costs memory, and a full board run beside a sim has been OOM-killed (~8 GB).
VIVADO_THREADS = 2


def _vivado_directives(args: argparse.Namespace) -> dict:
    if args.toolchain != "vivado":
        return {}
    name = "explore" if getattr(args, "vivado_explore", False) else getattr(args, "vivado_directives", "default")
    return {**DIRECTIVES[name], "vivado_max_threads": getattr(args, "vivado_threads", VIVADO_THREADS)}


def build_z7(args: argparse.Namespace) -> None:
    start = time.monotonic()
    soc, _ = make_z7(args)
    in_docker = args.toolchain == "openxc7"  # the tools are in a container: soc/openxc7.py
    if in_docker:
        openxc7.prepare_env()
    out = getattr(args, "out", None) or FPGA / "build/soc_z7"  # --out: sweeps and REUSE bases keep their own
    builder = Builder(soc, output_dir=str(out), compile_software=args.build)
    builder.build(run=args.build and not in_docker, **_vivado_directives(args))
    if in_docker and args.build:
        openxc7.run_build(builder.gateware_dir, soc.get_build_name(), time.monotonic() - start)
