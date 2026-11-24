"""A board's release SoC: what `make BOARD=<board> bitstream` builds (repo reorg Part B2).

One RTL tree, one set of parameters per board (soc/boards.py `Board.soc`). `--release` on
soc.zigmachine_soc makes them the parser's defaults, so an explicit flag still wins (`SOC_ARGS`); every
other build (soc-z7, soc-dev, hp_sim, tools/soc_util.py) keeps the parser's own defaults, as before.

What a parameter can be is what the SoC already plumbs as an option. The sizes the 7010 squeezed live in
the two vexgen netlists (ZIGGY: I$/D$ size and ways, the f32 FPU, ZM-X; BARD: its D$, the dynamic branch
predictor, its FPU) and in the HP-port options. Not parameters yet (each is an RTL or ABI change): the
number of FRESCO planes and its line buffers, CHISEL's internal options, the 32 MiB cart window.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Final

FPGA: Final = Path(__file__).resolve().parent.parent
VEXGEN: Final = FPGA / "build/vexgen"
READS: Final = ("base", "fast", "prefetch")  # soc/zm_board_mem.py READ_MODES
DIRECTIVES: Final = ("default", "explore", "closure", "fit", "fit_timing", "fit_netdelay")  # soc/zm_z7.py


class BoardSocError(ValueError):
    pass


@dataclass(frozen=True)
class SocParams:
    cpu_core: str  # ZIGGY's vexgen netlist, in build/vexgen/: its caches, FPU and ZM-X are in the core
    sound_core: str  # BARD's netlist, in build/vexgen/
    blit: bool = True  # CHISEL on HP2
    sound_cpu: bool = True  # BARD, sharing HP3 with the PCM reader
    posted: int = 8  # ZIGGY's posted-store buffer on HP0 (0 = blocking)
    read_bypass: bool = False  # refills bypass the posted stores (soc/zm_hp_bypass.py)
    ziggy_reads: str = "prefetch"  # ZIGGY's refill path
    sys_mhz: float = 100.0  # ZIGGY and the bus
    comp_mhz: float = 125.0  # FRESCO's compositor
    vivado_directives: str = "fit_timing"  # the place/route set the board closes timing with

    def __post_init__(self) -> None:
        if self.ziggy_reads not in READS:
            raise BoardSocError(f"ziggy_reads {self.ziggy_reads!r}: one of {', '.join(READS)}")
        if self.vivado_directives not in DIRECTIVES:
            raise BoardSocError(f"vivado_directives {self.vivado_directives!r}: one of {', '.join(DIRECTIVES)}")
        if self.posted < 0 or self.sys_mhz <= 0 or self.comp_mhz <= 0:
            raise BoardSocError(f"posted {self.posted}, sys {self.sys_mhz} MHz, comp {self.comp_mhz} MHz")

    @property
    def cpu_netlist(self) -> Path:
        return VEXGEN / self.cpu_core

    @property
    def sound_netlist(self) -> Path:
        return VEXGEN / self.sound_core

    def parser_defaults(self) -> dict[str, object]:
        """soc.zigmachine_soc's argument names -> this SoC's values (argparse set_defaults)."""
        return {
            "cpu_netlist": str(self.cpu_netlist),
            "sound_core": str(self.sound_netlist),
            "blit": self.blit,
            "sound_cpu": self.sound_cpu,
            "posted": self.posted,
            "no_read_bypass": not self.read_bypass,
            "ziggy_reads": self.ziggy_reads,
            "sys_mhz": self.sys_mhz,
            "comp_mhz": self.comp_mhz,
            "vivado_directives": self.vivado_directives,
        }


# KESTREL v1.3's release SoC (2026-11-20, lut_diet bit_a): ZIGGY with the 16 KiB 2-way I$ and D$, the
# f32 FPU and ZM-X; BARD SndNdD16Dyn8Sx (D$ 16 KB, dynamic prediction); CHISEL; posted stores; prefetch
# refills. fit_timing: area synthesis, the only set that fits the 7010 (soc/zm_z7.py DIRECTIVES).
KESTREL_V13: Final = SocParams(
    cpu_core="VexRiscv_I16w2D16w2SealFpuZmxE.v",
    sound_core="VexRiscv_SndNdD16Dyn8Sx.v",
)
