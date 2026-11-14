#!/bin/bash
# ooc_video_out.sh OUTDIR [DEFINES]: zm_video_out out of context, placed + routed, clk 8 ns /
# pix_clk 25 ns (asynchronous groups), the recipe decisions.md 2026-11-08 measured the desk mode
# with. DEFINES like "ZM_SDPRAM_LANES" select the RTL shape under test. Takes the Vivado lock.
set -euo pipefail
out=$2; defs=${3:-}; mkdir -p "$out"; out=$(realpath "$out")
fpga=$(cd "$(dirname "$0")/../../fpga" && pwd)
rtl=$fpga/rtl/video
srcs="zm_video_sdpram.v zm_video_dcram.v zm_video_regs.v zm_video_fetch.v zm_video_bg.v zm_video_tcfade.v zm_video_paint.v
zm_video_latch.v zm_video_plane.v zm_video_planepath.v zm_video_mix.v zm_video_rowio.v zm_video_copchk.v zm_video_copper.v
zm_video_palwb.v zm_video_pass.v zm_video_comp.v zm_video_scanfetch.v zm_video_desk.v zm_video_scan.v zm_vtiming.v
zm_video_sync.v zm_video_out.v"
vdefs=""; for d in $defs; do vdefs="$vdefs -verilog_define $d"; done
{
  echo "set_param general.maxThreads 2"
  for s in $srcs; do echo "read_verilog {$rtl/$s}"; done
  echo "synth_design -top zm_video_out -part xc7z010clg400-1 -mode out_of_context -include_dirs {$fpga/gen $rtl}$vdefs"
  echo "create_clock -period 8 -name clk [get_ports clk]"
  echo "create_clock -period 25 -name pix_clk [get_ports pix_clk]"
  echo "set_clock_groups -asynchronous -group clk -group pix_clk"
  echo "report_utilization -file {$out/util_synth.rpt}"
  echo "opt_design"; echo "place_design"; echo "route_design"
  echo "report_utilization -file {$out/util.rpt}"
  echo "report_utilization -hierarchical -hierarchical_depth 3 -file {$out/hier.rpt}"
  echo "report_timing_summary -file {$out/timing.rpt}"
  echo "report_timing -max_paths 5 -file {$out/paths.rpt}"
} > "$out/build.tcl"
export PATH=/opt/vivado/2026.1/Vivado/bin:$PATH LD_LIBRARY_PATH=$HOME/.local/lib/vivado-compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
cd "$out" && flock /home/matt/projects/ZigMachine/fpga/build/vivado.lock vivado -mode batch -nojournal -log vivado.log -source build.tcl > /dev/null
echo "== $out ($defs)"
grep -E "Slice LUTs|Slice Registers|Block RAM Tile|RAMB18  |RAMB36/FIFO|DSPs" "$out/util.rpt" | head -6
grep -A3 "WNS(ns)" "$out/timing.rpt" | head -4
