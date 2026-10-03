"""Synthesise blocks for the 7-series (Yosys `synth_xilinx`) and report what each
costs: the measured side of the LUT budget in docs/ZIGMACHINE_IN_FPGA.md.

    uv run python tools/util.py            # every block
    uv run python tools/util.py jt49 vexriscv_std

These are Yosys numbers, pre-place-and-route: good to ~10-20 % of what Vivado or
nextpnr-xilinx will report, and directly comparable with each other.
"""

import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import pythondata_cpu_vexriscv
import yowasp_yosys

FPGA = Path(__file__).resolve().parent.parent
TP = FPGA / "third_party"
VEX = Path(pythondata_cpu_vexriscv.data_location)
SV2V = FPGA / ".tools/bin/sv2v"
XC7Z010_LUTS = 17_600


@dataclass(frozen=True)
class Block:
    name: str
    top: str
    sources: tuple[Path, ...]
    note: str
    sv: bool = False


def _glob(d: Path, pattern: str) -> tuple[Path, ...]:
    return tuple(sorted(d.glob(pattern)))


BLOCKS = [
    Block("zm_vtiming", "zm_vtiming", (FPGA / "rtl/video/zm_vtiming.v",), "ours: 800x600 timing + HBL"),
    Block("zm_video_comp", "zm_video_comp", _glob(FPGA / "rtl/video", "zm_video_*.v"), "ours: plane-major compositor + row I/O"),
    Block("zm_video_out", "zm_video_out", _glob(FPGA / "rtl/video", "zm_*.v"), "ours: comp + double buffer + scanout fetch"),
    Block("zm_tmds_enc", "zm_tmds_enc", (FPGA / "rtl/video/zm_tmds_enc.v",), "ours: one TMDS channel"),
    Block("zm_dvi_out", "zm_dvi_out", (FPGA / "rtl/video/zm_dvi_out.v", FPGA / "rtl/video/zm_tmds_enc.v"), "ours: DVI"),
    Block("zm_glass_regs", "zm_glass_regs", (FPGA / "rtl/glass/zm_glass_regs.v", FPGA / "rtl/glass/zm_glass_ptr.v"), "ours: the ARM's GP0 registers"),
    Block("zm_glass_osd", "zm_glass_osd", (FPGA / "rtl/glass/zm_glass_osd.v", FPGA / "rtl/video/zm_video_dcram.v"), "ours: OSD"),
    Block("jt49", "jt49", _glob(TP / "jt49/hdl", "jt49*.v"), "YM2149 (jotego, GPL-3)"),
    Block("fx68k", "fx68k", _glob(TP / "fx68k", "*.sv"), "68000, cycle-exact (GPL-3)", sv=True),
    # hdl-util/hdmi is not measurable here: its `real` parameters (pixel and audio
    # rates) are beyond Yosys. Measure it in Vivado, or with the yosys-slang plugin.
    Block("vexriscv_min", "VexRiscv", (VEX / "VexRiscv_Min.v",), "rv32i, no caches"),
    Block("vexriscv_lite", "VexRiscv", (VEX / "VexRiscv_Lite.v",), "rv32im, small caches"),
    Block("vexriscv_std", "VexRiscv", (VEX / "VexRiscv.v",), "rv32im, caches (LiteX default)"),
    Block("vexriscv_full", "VexRiscv", (VEX / "VexRiscv_Full.v",), "rv32im, bigger caches, MMU-less full"),
]
# The cache variants vexgen/gen.sh has generated (CYCLES.md "Memory path"), if any.
BLOCKS += [
    Block(f"vex_{v.stem.removeprefix('VexRiscv_')}", "VexRiscv", (v,), "standard, other I$/D$ (vexgen)")
    for v in sorted((FPGA / "build/vexgen").glob("VexRiscv_*.v"))
]

CELL_GROUPS = {
    "LUT": re.compile(r"^LUT\d$"),
    "FF": re.compile(r"^FD"),
    "CARRY4": re.compile(r"^CARRY4$"),
    "BRAM": re.compile(r"^RAMB(18|36)"),
    "LUTRAM": re.compile(r"^RAM(32|64|128|256)"),
    "DSP": re.compile(r"^DSP48"),
}


def _to_verilog(block: Block, out_dir: Path) -> tuple[Path, ...]:
    """SystemVerilog the Yosys parser rejects goes through sv2v first."""
    if not block.sv:
        return block.sources
    if not SV2V.exists():
        raise RuntimeError("needs sv2v: run tools/setup.sh")
    v = out_dir / f"{block.name}.v"
    with v.open("w") as f:
        subprocess.run([str(SV2V), *map(str, block.sources)], stdout=f, check=True)
    return (v,)


def synth(block: Block) -> dict[str, int]:
    """Run synth_xilinx on one block and group its cell counts."""
    out = FPGA / "build" / "util" / f"{block.name}.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    sources = _to_verilog(block, out.parent)
    reads = " ".join(str(s) for s in sources)
    script = (
        f"read_verilog -I{FPGA / 'gen'} -I{block.sources[0].parent} {reads}; "
        f"synth_xilinx -family xc7 -top {block.top} -flatten; tee -q -o {out} stat"
    )
    # From the core's own directory: fx68k's $readmemb names its microcode ROMs relatively.
    here = Path.cwd()
    os.chdir(block.sources[0].parent)
    try:
        rc = yowasp_yosys.run_yosys(["-q", "-p", script])
    finally:
        os.chdir(here)
    if rc != 0:
        raise RuntimeError(f"yosys failed on {block.name}")
    return group_cells(out.read_text())


def group_cells(stat: str) -> dict[str, int]:
    """Sum `stat`'s per-cell counts into the CELL_GROUPS buckets."""
    totals = dict.fromkeys(CELL_GROUPS, 0)
    for count, cell in re.findall(r"^\s+(\d+)\s+(\S+)\s*$", stat, re.MULTILINE):
        for group, pattern in CELL_GROUPS.items():
            if pattern.match(cell):
                totals[group] += int(count)
    return totals


def main(names: list[str]) -> int:
    chosen = [b for b in BLOCKS if not names or b.name in names]
    unknown = set(names) - {b.name for b in BLOCKS}
    if unknown:
        print(f"unknown block(s): {', '.join(sorted(unknown))}", file=sys.stderr)
        return 2
    print(f"{'block':<15}{'LUT':>7}{'%7010':>7}{'FF':>7}{'CARRY4':>8}{'BRAM':>6}{'LUTRAM':>8}{'DSP':>5}  note")
    for b in chosen:
        try:
            c = synth(b)
        except (RuntimeError, subprocess.CalledProcessError) as e:
            print(f"{b.name:<15}{'n/a':>7}  {e}")
            continue
        pct = 100 * c["LUT"] / XC7Z010_LUTS
        print(
            f"{b.name:<15}{c['LUT']:>7}{pct:>6.1f}%{c['FF']:>7}{c['CARRY4']:>8}{c['BRAM']:>6}"
            f"{c['LUTRAM']:>8}{c['DSP']:>5}  {b.note}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
