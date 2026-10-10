#!/bin/bash
# vivado_bit.sh TOP OUTDIR XDC "DEFINES" FILE... : a small board top to a bitstream with Vivado (non-project),
# the reference toolchain next to openXC7 (tools/openxc7.sh bit). DEFINES like "HDMI_ODDR FOO=1" (no -D).
# Needs /opt/vivado/2026.1, ~/.Xilinx/Xilinx.lic, and the ncurses5 shims in ~/.local/lib/vivado-compat.
set -euo pipefail
top=$1 out=$2 xdc=$3 defs=$4; shift 4
mkdir -p "$out"
inc=$(cd "$(dirname "$0")/.." && pwd)/gen
{
    for f in "$@"; do echo "read_verilog {$f}"; done
    echo "read_xdc {$xdc}"
    vdefs=""; for d in $defs; do vdefs="$vdefs -verilog_define $d"; done
    echo "synth_design -top $top -part xc7z010clg400-1 -include_dirs {$inc} $vdefs"
    echo "opt_design; place_design; route_design"
    echo "report_timing_summary -file {$out/timing.rpt}"
    echo "write_bitstream -force {$out/$top.bit}"
} > "$out/build.tcl"
export PATH=/opt/vivado/2026.1/Vivado/bin:$PATH LD_LIBRARY_PATH=$HOME/.local/lib/vivado-compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
cd "$out" && vivado -mode batch -nojournal -log vivado.log -source build.tcl > /dev/null
grep -A3 "WNS(ns)" "$out/timing.rpt" | sed -n 3p
