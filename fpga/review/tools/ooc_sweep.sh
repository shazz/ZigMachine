#!/bin/bash
# Out-of-context Vivado synth + opt + place + route of one RTL block, at one target period.
#   ooc_sweep.sh <top> <period_ns> <output_dir> <file1> [file2 ...]
# <top> must expose a `clk` port, which is constrained to <period_ns>. Absolute file paths
# are resolved against the caller's cwd, so it can be launched from anywhere.
# Writes in <output_dir>: run.tcl, vivado.log/jou, timing_summary.rpt, util.rpt, hier.rpt.
set -e
CAND="$1"; PERIOD="$2"; OUT="$3"; shift 3
INCS='{/home/matt/projects/ZigMachine/fpga/gen /home/matt/projects/ZigMachine/fpga/rtl/video /home/matt/projects/ZigMachine/fpga/rtl/blitter /home/matt/projects/ZigMachine/fpga/rtl/audio /home/matt/projects/ZigMachine/fpga/third_party/jt49/hdl}'
mkdir -p "$OUT"
{
echo 'set files {'
for f in "$@"; do echo "  $(readlink -f "$f")"; done
echo '}'
echo 'read_verilog $files'
echo "set_property include_dirs $INCS [current_fileset]"
echo "synth_design -top $CAND -part xc7z010clg400-1 -mode out_of_context"
echo 'opt_design -directive Explore'
echo "create_clock -period $PERIOD -name clk_ooc [get_ports clk]"
echo 'place_design -directive ExtraTimingOpt'
echo 'route_design -directive MoreGlobalIterations'
echo "report_timing_summary -file $OUT/timing_summary.rpt"
echo "report_utilization -file $OUT/util.rpt"
echo "report_utilization -hierarchical -file $OUT/hier.rpt"
echo "write_checkpoint -force $OUT/ooc_$CAND.dcp"
} > "$OUT/run.tcl"
export PATH=/opt/vivado/2026.1/Vivado/bin:$PATH LD_LIBRARY_PATH=$HOME/.local/lib/vivado-compat
cd "$OUT" && vivado -mode batch -source run.tcl -log vivado.log -journal vivado.jou >/dev/null 2>&1
test -s timing_summary.rpt && test -s hier.rpt
echo "OOC $CAND @$PERIOD ns ok -> $OUT"
