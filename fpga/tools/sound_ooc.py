"""The sound CPU block's size (docs/FPGA_SOUND_CPU.md "Size"): SoundCPU (soc/zm_sound_cpu.py:
the core, its decoder, the arbiter, the posted HP bridge, the register block) written as one
Verilog top with its buses as ports, then Vivado out-of-context synthesis (tools/vivado_ooc.sh).

    uv run python tools/sound_ooc.py [--out build/ooc_sound] [--core build/vexgen/VexRiscv_SndNd.v]
    PERIOD=6.667 IMPL=1 uv run python tools/sound_ooc.py ...   # and its routed timing at 150 MHz
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import Any

from litex.soc.interconnect import wishbone
from migen import Module
from migen.fhdl.verilog import convert

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA))
from soc.zm_hp import hp_interface
from soc.zm_sound_cpu import SOUND_CORE, SoundCPU


class Sources:
    """The `platform` SoundCPU adds its Verilog to."""

    def __init__(self) -> None:
        self.files: list[str] = []

    def add_source(self, path: str) -> None:
        self.files.append(path)


def _signals(iface: Any) -> set[Any]:  # Any: a LiteX bus record (Wishbone) or an AXIInterface
    if hasattr(iface, "flatten"):
        return set(iface.flatten())
    return {s for ch in ("aw", "w", "b", "ar", "r") for s in getattr(iface, ch).flatten()}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", type=Path, default=FPGA / "build/ooc_sound")
    ap.add_argument("--core", type=Path, default=SOUND_CORE, help="the core's netlist (vexgen/gen.sh, flag snd)")
    a = ap.parse_args()
    a.out = a.out.resolve()
    a.out.mkdir(parents=True, exist_ok=True)
    src, top = Sources(), Module()
    hp = hp_interface()
    audio = wishbone.Interface(data_width=32, address_width=32, addressing="word")
    pcm = wishbone.Interface(data_width=32, address_width=32, addressing="word")
    top.submodules.snd = snd = SoundCPU(src, hp, audio, pcm, core=a.core.resolve())
    ios = _signals(hp) | _signals(audio) | _signals(pcm) | _signals(snd.cart)
    (a.out / "zm_sound_top.v").write_text(str(convert(top, ios=ios, name="zm_sound_top")))
    files = [str(a.out / "zm_sound_top.v"), *src.files]
    subprocess.run([str(FPGA / "tools/vivado_ooc.sh"), "zm_sound_top", str(a.out), "", *files], check=True)


if __name__ == "__main__":
    main()
