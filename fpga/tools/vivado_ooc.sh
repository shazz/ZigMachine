#!/bin/bash
# vivado_ooc.sh TOP OUTDIR "DEFINES" FILE... : one block's size with Vivado, out of context (no pins,
# no bitstream), the figure the SoC budget is kept in (docs/FPGA_SOUND_CPU.md). Paths may be relative.
# PERIOD=<ns> (env) constrains the clock port CLOCK (env, default sys_clk) and reports WNS: a synthesis
# estimate with no routing delay, unless IMPL=1, which also places and routes.
# FLATTEN=none keeps every module's logic in it (an honest per-module bill, a little larger in total).
# HIER=1 also writes OUTDIR/hier.rpt, the utilisation by submodule (where the LUTs go).
# Prints "TOP LUT FF BRAM-tiles DSP" (a tile = one RAMB36 or two RAMB18); the full report is OUTDIR/util.rpt. DEFINES like "FOO=1" (no -D).
# e.g. PERIOD=10 IMPL=1 CLOCK=clk tools/vivado_ooc.sh zm_pokey build/ooc_pokey "" rtl/audio/zm_audio_frac.v rtl/audio/zm_pokey*.v
# MAXTHREADS=<n> (env, default 2) caps Vivado's threads. Takes the lock itself: never wrap it in another flock on the same file (that deadlocks).
# Runs under the MAIN checkout's fpga/build/vivado.lock (found through git's common dir, so a worktree
# takes the same lock): the one lock every Vivado run on this box takes. Keep OUTDIR
# under fpga/build/ooc_<block>/ so it never touches a SoC build's directory.
# Needs /opt/vivado/2026.1, ~/.Xilinx/Xilinx.lic, and the ncurses5 shims in ~/.local/lib/vivado-compat.
set -euo pipefail
top=$1 out=$2 defs=$3; shift 3
fpga=$(cd "$(dirname "$0")/.." && pwd)
lock="$(cd "$(git -C "$fpga" rev-parse --git-common-dir)/.." && pwd)/fpga/build/vivado.lock"
mkdir -p "$out"
out=$(cd "$out" && pwd)
files=(); for f in "$@"; do files+=("$(realpath "$f")"); done; set -- "${files[@]}"
{
    echo "set_param general.maxThreads ${MAXTHREADS:-2}" # Vivado beside a sim was OOM-killed: 2 threads
    for f in "$@"; do echo "read_verilog {$f}"; done
    vdefs=""; for d in $defs; do vdefs="$vdefs -verilog_define $d"; done
    echo "synth_design -top $top -part xc7z010clg400-1 -mode out_of_context -include_dirs {$fpga/gen} $vdefs${FLATTEN:+ -flatten_hierarchy $FLATTEN}"
    if [ -n "${PERIOD:-}" ]; then
        echo "create_clock -period $PERIOD -name ${CLOCK:-sys_clk} [get_ports ${CLOCK:-sys_clk}]"
        if [ -n "${IMPL:-}" ]; then echo "opt_design"; echo "place_design"; echo "route_design"; fi
    fi
    echo "report_utilization -file {$out/util.rpt}" # after routing with IMPL=1: what the block really takes
    if [ -n "${HIER:-}" ]; then echo "report_utilization -hierarchical -hierarchical_depth 4 -file {$out/hier.rpt}"; fi
    if [ -n "${PERIOD:-}" ]; then
        echo "report_timing_summary -file {$out/timing.rpt}"
        echo "report_timing -max_paths 5 -file {$out/paths.rpt}"
    fi
} > "$out/build.tcl"
export PATH=/opt/vivado/2026.1/Vivado/bin:$PATH LD_LIBRARY_PATH=$HOME/.local/lib/vivado-compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
(cd "$out" && flock "$lock" vivado -mode batch -nojournal -log vivado.log -source build.tcl > /dev/null)
# The used column of a "| Name | Used | ..." row of the report's first tables.
used() { awk -F'|' -v k="$1" '$2 ~ "^ *"k" *$" {gsub(/ /, "", $3); print $3; exit}' "$out/util.rpt"; }
wns=""; [ -n "${PERIOD:-}" ] && wns=" WNS $(awk '/WNS\(ns\)/{getline; getline; print $1; exit}' "$out/timing.rpt")"
echo "$top $(used 'Slice LUTs\*?') $(used 'Slice Registers') $(used 'Block RAM Tile') $(used 'DSPs')$wns"
