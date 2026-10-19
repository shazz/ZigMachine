#!/usr/bin/env python3
"""vivado_perf_sweep.py: Vivado Out-Of-Context (OOC) Timing & Performance Sweeper for ZigMachine FPGA.

Runs out-of-context synthesis and P&R with AMD/Xilinx Vivado ML Standard (2026.1)
on critical RTL blocks to extract exact WNS, Fmax, LUTs, FFs, BRAM, DSP, and critical path details.
"""

from __future__ import annotations
import argparse
import json
import os
import re
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, List, Optional


FPGA_DIR = Path(__file__).resolve().parent.parent.parent
BUILD_DIR = FPGA_DIR / "build"
REVIEW_BUILD_DIR = BUILD_DIR / "ooc_review"
LOCK_FILE = BUILD_DIR / "vivado.lock"
VIVADO_BIN = "/opt/vivado/2026.1/Vivado/bin/vivado"
COMPAT_LIB = os.path.expanduser("~/.local/lib/vivado-compat")


@dataclass
class OOCCandidate:
    name: str
    top: str
    clock_port: str
    periods_ns: List[float]  # Periods to sweep (e.g. [10.0, 8.0, 6.67])
    sources: List[str]
    defines: str = ""


# Target modules to benchmark
CANDIDATES: Dict[str, OOCCandidate] = {
    "zm_video_plane": OOCCandidate(
        name="zm_video_plane",
        top="zm_video_plane",
        clock_port="clk",
        periods_ns=[10.0, 8.0, 6.67],  # 100 MHz, 125 MHz, 150 MHz
        sources=["rtl/video/zm_video_plane.v"],
    ),
    "zm_video_mix": OOCCandidate(
        name="zm_video_mix",
        top="zm_video_mix",
        clock_port="clk",
        periods_ns=[8.0, 6.67],  # 125 MHz, 150 MHz
        sources=["rtl/video/zm_video_mix.v", "rtl/video/zm_video_sdpram.v"],
    ),
    "zm_blit_px": OOCCandidate(
        name="zm_blit_px",
        top="zm_blit_px",
        clock_port="clk",
        periods_ns=[10.0, 8.0, 6.67],  # 100 MHz, 125 MHz, 150 MHz
        sources=["rtl/blitter/zm_blit_px.v", "rtl/blitter/zm_blit_pxq.v"],
    ),
    "zm_blit_core": OOCCandidate(
        name="zm_blit_core",
        top="zm_blit_core",
        clock_port="clk",
        periods_ns=[10.0, 8.0],  # 100 MHz, 125 MHz
        sources=[
            "rtl/blitter/zm_blit_core.v",
            "rtl/blitter/zm_blit_clip.v",
            "rtl/blitter/zm_blit_chk.v",
            "rtl/blitter/zm_blit_htbit.v",
            "rtl/blitter/zm_blit_blit.v",
            "rtl/blitter/zm_blit_fill.v",
            "rtl/blitter/zm_blit_line.v",
            "rtl/blitter/zm_blit_tri.v",
            "rtl/blitter/zm_blit_row.v",
            "rtl/blitter/zm_blit_div.v",
            "rtl/blitter/zm_blit_px.v",
            "rtl/blitter/zm_blit_pxq.v",
        ],
    ),
    "zm_audio_soc": OOCCandidate(
        name="zm_audio_soc",
        top="zm_audio_soc",
        clock_port="sys_clk",
        periods_ns=[10.0],  # 100 MHz
        sources=[
            "rtl/audio/zm_audio_soc.v",
            "rtl/audio/zm_audio_core.v",
            "rtl/audio/zm_audio_fifo.v",
            "rtl/audio/zm_audio_frac.v",
            "rtl/audio/zm_audio_mix.v",
            "rtl/audio/zm_audio_pcm.v",
            "rtl/audio/zm_audio_sched.v",
            "rtl/audio/zm_audio_ym.v",
            "rtl/audio/zm_pokey.v",
            "rtl/audio/zm_pokey_pair.v",
            "rtl/audio/zm_pokey_poly.v",
            "third_party/jt49/hdl/jt49.v",
            "third_party/jt49/hdl/jt49_bus.v",
            "third_party/jt49/hdl/jt49_cen.v",
            "third_party/jt49/hdl/jt49_div.v",
            "third_party/jt49/hdl/jt49_eg.v",
            "third_party/jt49/hdl/jt49_exp.v",
            "third_party/jt49/hdl/jt49_noise.v",
        ],
    ),
}


@dataclass
class SweepRunResult:
    candidate: str
    target_period_ns: float
    target_freq_mhz: float
    wns_ns: float
    achievable_fmax_mhz: float
    luts: int
    ffs: int
    bram_tiles: float
    dsps: int
    timing_met: bool
    critical_path_source: str
    critical_path_dest: str
    critical_path_delay_ns: float
    logic_levels: int


def parse_util_rpt(rpt_file: Path) -> dict:
    util = {"LUT": 0, "FF": 0, "BRAM": 0.0, "DSP": 0}
    if not rpt_file.exists():
        return util

    text = rpt_file.read_text()
    # Parse Slice LUTs
    m_lut = re.search(r"\|\s*Slice LUTs\*?\s*\|\s*(\d+)\s*\|", text)
    if m_lut:
        util["LUT"] = int(m_lut.group(1))

    # Parse Slice Registers (FFs)
    m_ff = re.search(r"\|\s*Slice Registers\s*\|\s*(\d+)\s*\|", text)
    if m_ff:
        util["FF"] = int(m_ff.group(1))

    # Parse Block RAM Tile
    m_bram = re.search(r"\|\s*Block RAM Tile\s*\|\s*([\d\.]+)\s*\|", text)
    if m_bram:
        util["BRAM"] = float(m_bram.group(1))

    # Parse DSPs
    m_dsp = re.search(r"\|\s*DSPs\s*\|\s*(\d+)\s*\|", text)
    if m_dsp:
        util["DSP"] = int(m_dsp.group(1))

    return util


def parse_timing_rpt(rpt_file: Path, target_period: float) -> tuple[float, bool]:
    if not rpt_file.exists():
        return -999.0, False

    text = rpt_file.read_text()
    m_wns = re.search(r"WNS\(ns\)\s+TNS\(ns\)[^\n]+\n\s*-+\s+-+[^\n]+\n\s*([-\d\.]+)", text)
    if m_wns:
        wns = float(m_wns.group(1))
        return wns, (wns >= 0.0)

    return -999.0, False


def parse_paths_rpt(rpt_file: Path) -> tuple[str, str, float, int]:
    if not rpt_file.exists():
        return "unknown", "unknown", 0.0, 0

    text = rpt_file.read_text()
    source, dest = "unknown", "unknown"
    data_delay = 0.0
    levels = 0

    m_src = re.search(r"Source:\s+([^\n\(\s]+)", text)
    if m_src:
        source = m_src.group(1)

    m_dst = re.search(r"Destination:\s+([^\n\(\s]+)", text)
    if m_dst:
        dest = m_dst.group(1)

    m_del = re.search(r"Data Path Delay:\s+([\d\.]+)ns", text)
    if m_del:
        data_delay = float(m_del.group(1))

    m_lev = re.search(r"Logic Levels:\s+(\d+)", text)
    if m_lev:
        levels = int(m_lev.group(1))

    return source, dest, data_delay, levels


def run_vivado_ooc(candidate: OOCCandidate, period_ns: float, run_dir: Path) -> SweepRunResult:
    run_dir.mkdir(parents=True, exist_ok=True)
    tcl_file = run_dir / "run.tcl"
    log_file = run_dir / "vivado.log"

    # Resolve all sources
    abs_sources = [(FPGA_DIR / s).resolve() for s in candidate.sources]

    # Build TCL script
    tcl_content = []
    for s in abs_sources:
        tcl_content.append(f"read_verilog {{{s}}}")

    vdefs = candidate.defines
    vdefs_arg = f"-verilog_define {vdefs}" if vdefs else ""
    inc_dir = (FPGA_DIR / "gen").resolve()

    tcl_content.append(
        f"synth_design -top {candidate.top} -part xc7z010clg400-1 -mode out_of_context "
        f"-include_dirs {{{inc_dir}}} {vdefs_arg}"
    )
    tcl_content.append(f"create_clock -period {period_ns:.3f} -name {candidate.clock_port} [get_ports {candidate.clock_port}]")
    tcl_content.append("opt_design")
    tcl_content.append("place_design")
    tcl_content.append("route_design")
    tcl_content.append(f"report_utilization -file {{{(run_dir / 'util.rpt').resolve()}}}")
    tcl_content.append(f"report_timing_summary -file {{{(run_dir / 'timing.rpt').resolve()}}}")
    tcl_content.append(f"report_timing -max_paths 1 -file {{{(run_dir / 'paths.rpt').resolve()}}}")
    tcl_content.append("quit")

    tcl_file.write_text("\n".join(tcl_content))

    env = os.environ.copy()
    env["PATH"] = f"/opt/vivado/2026.1/Vivado/bin:{env.get('PATH', '')}"
    env["LD_LIBRARY_PATH"] = f"{COMPAT_LIB}:{env.get('LD_LIBRARY_PATH', '')}"

    cmd = [
        "flock", str(LOCK_FILE),
        VIVADO_BIN,
        "-mode", "batch",
        "-nojournal",
        "-log", str(log_file),
        "-source", str(tcl_file),
    ]

    print(f"  -> Running Vivado P&R for {candidate.name} @ {1000.0/period_ns:.1f} MHz (T={period_ns:.2f}ns)...")
    res = subprocess.run(cmd, cwd=run_dir, capture_output=True, env=env)

    # Parse reports
    util = parse_util_rpt(run_dir / "util.rpt")
    wns, met = parse_timing_rpt(run_dir / "timing.rpt", period_ns)
    src, dst, delay, levels = parse_paths_rpt(run_dir / "paths.rpt")

    # Achievable fmax = 1000.0 / (period - wns)
    achievable_period = period_ns - wns
    achievable_fmax = 1000.0 / achievable_period if achievable_period > 0 else 0.0

    return SweepRunResult(
        candidate=candidate.name,
        target_period_ns=period_ns,
        target_freq_mhz=round(1000.0 / period_ns, 2),
        wns_ns=round(wns, 3),
        achievable_fmax_mhz=round(achievable_fmax, 2),
        luts=util["LUT"],
        ffs=util["FF"],
        bram_tiles=util["BRAM"],
        dsps=util["DSP"],
        timing_met=met,
        critical_path_source=src,
        critical_path_dest=dst,
        critical_path_delay_ns=delay,
        logic_levels=levels,
    )


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--candidate", choices=list(CANDIDATES.keys()), help="Run specific candidate only")
    p.add_argument("--period", type=float, help="Override target clock period in ns")
    p.add_argument("--json", help="Path to write JSON summary output")
    args = p.parse_args()

    REVIEW_BUILD_DIR.mkdir(parents=True, exist_ok=True)
    (BUILD_DIR / "vivado.lock").touch()

    to_run = [CANDIDATES[args.candidate]] if args.candidate else list(CANDIDATES.values())

    results: List[SweepRunResult] = []

    print("=" * 88)
    print("VIVADO 2026.1 OUT-OF-CONTEXT PERFORMANCE & TIMING BENCHMARK")
    print("Device: Zynq XC7Z010-1CLG400 | Flow: synth_design -> opt -> place -> route")
    print("=" * 88)

    for cand in to_run:
        periods = [args.period] if args.period else cand.periods_ns
        for per in periods:
            run_dir = REVIEW_BUILD_DIR / f"{cand.name}_{per:.2f}ns"
            res = run_vivado_ooc(cand, per, run_dir)
            results.append(res)
            status_str = "MET" if res.timing_met else "MISSED"
            print(f"     Status: {status_str} | WNS: {res.wns_ns:+.3f} ns | Fmax: {res.achievable_fmax_mhz:.1f} MHz")
            print(f"     Resources: {res.luts} LUTs, {res.ffs} FFs, {res.bram_tiles} BRAM, {res.dsps} DSPs")
            print(f"     Critical Path: {res.critical_path_source} -> {res.critical_path_dest} ({res.critical_path_delay_ns:.2f} ns, {res.logic_levels} levels)")

    print("=" * 88)
    print(f"{'Module':<18} | {'Target (MHz)':<12} | {'WNS (ns)':<9} | {'Fmax (MHz)':<11} | {'LUTs':<6} | {'DSPs':<5} | {'Levels':<6}")
    print("-" * 88)
    for r in results:
        print(f"{r.candidate:<18} | {r.target_freq_mhz:>12.1f} | {r.wns_ns:>9.3f} | {r.achievable_fmax_mhz:>11.1f} | {r.luts:>6} | {r.dsps:>5} | {r.logic_levels:>6}")
    print("=" * 88)

    if args.json:
        with open(args.json, "w") as f:
            json.dump([asdict(x) for x in results], f, indent=2)
        print(f"Wrote timing sweep JSON to {args.json}")


if __name__ == "__main__":
    main()
