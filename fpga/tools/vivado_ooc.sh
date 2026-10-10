#!/bin/bash
# vivado_ooc.sh TOP OUTDIR MHZ FILE... : one block out of context (no pins, no board) with Vivado,
# synthesised, placed and routed on the 7010 against a clock `clk` at MHZ, for its real cost and WNS.
# Run it under the main checkout's lock (shared by every worktree):
#   flock ~/projects/ZigMachine/fpga/build/vivado.lock tools/vivado_ooc.sh zm_pokey build/ooc/zm_pokey 100 rtl/audio/zm_audio_frac.v rtl/audio/zm_pokey*.v
# Needs /opt/vivado/2026.1, ~/.Xilinx/Xilinx.lic, and the ncurses5 shims (as tools/vivado_bit.sh).
set -euo pipefail
top=$1 out=$2 mhz=$3; shift 3
mkdir -p "$out"
out=$(cd "$out" && pwd)
inc=$(cd "$(dirname "$0")/.." && pwd)/gen
period=$(awk "BEGIN { printf \"%.3f\", 1000 / $mhz }")
{
    for f in "$@"; do echo "read_verilog {$(realpath "$f")}"; done
    echo "synth_design -top $top -part xc7z010clg400-1 -mode out_of_context -include_dirs {$inc}"
    echo "create_clock -name clk -period $period [get_ports clk]"
    echo "report_utilization -file {$out/synth_util.rpt}"
    echo "opt_design; place_design; route_design"
    echo "report_utilization -file {$out/utilization.rpt}"
    echo "report_timing_summary -file {$out/timing.rpt}"
} > "$out/ooc.tcl"
export PATH=/opt/vivado/2026.1/Vivado/bin:$PATH LD_LIBRARY_PATH=$HOME/.local/lib/vivado-compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
cd "$out" && vivado -mode batch -nojournal -log vivado.log -source ooc.tcl > /dev/null
for k in "Slice LUTs" "Slice Registers" "Block RAM Tile" "DSPs"; do grep -m1 "^| $k " "$out/utilization.rpt" | cut -d'|' -f2,3; done
grep -A3 "WNS(ns)" "$out/timing.rpt" | sed -n 3p
