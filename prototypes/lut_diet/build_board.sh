#!/bin/bash
# build_board.sh NAME [EXTRA ARGS...]: the board bitstream of this worktree, combo16's command line
# (--blit --sound-cpu --posted 8 --no-read-bypass, VexRiscv_I16w2D16w2SealFpuZmxE, BARD SndNdD16Dyn8Sx,
# fit_timing) plus EXTRA (e.g. --ziggy-reads base; prefetch is the default since v1.3), into fpga/build/NAME. Waits for a quiet box
# (no Vivado, >= 8 GB free, no zig build / build.sh / verilator), then takes the build and Vivado locks.
set -u
name=$1; shift
W=$(cd "$(dirname "$0")/../.." && pwd)
L=/home/matt/projects/ZigMachine/prototypes/_gate_logs
cd "$W/fpga" || exit 1
export PATH=/opt/vivado/2026.1/Vivado/bin:$PATH LD_LIBRARY_PATH=/home/matt/.local/lib/vivado-compat
ok=0
for i in $(seq 1 360); do
    avail=$(free -g | awk '/^Mem:/ {print $7}')
    # Real processes only: other agents' idle waiter shells carry "zig build" in their command lines
    # (memory: pgrep self-match), so match the binaries, not the words.
    busy=0
    pgrep -x zig >/dev/null && busy=1
    pgrep -x vivado >/dev/null && busy=1
    pgrep -x verilator_bin >/dev/null && busy=1
    pgrep -f "obj_dir/V[A-Za-z_]+( |$)" >/dev/null && busy=1
    pgrep -f "^(/bin/)?(ba)?sh \./build\.sh" >/dev/null && busy=1
    if [ "$avail" -ge 8 ] && [ $busy = 0 ]; then ok=1; break; fi
    sleep 30
done
[ $ok = 1 ] || { echo "GAVE UP: no 8 GB / quiet box in 3 h"; exit 1; }
echo "== start $(date) avail=$(free -g | awk '/^Mem:/ {print $7}') GB args: $*"
flock $L/build.lock flock /home/matt/projects/ZigMachine/fpga/build/vivado.lock \
    uv run python -m soc.zigmachine_soc --target z7 --build --toolchain vivado --blit --sound-cpu --posted 8 \
    --no-read-bypass --cpu-netlist build/vexgen/VexRiscv_I16w2D16w2SealFpuZmxE.v \
    --sound-core build/vexgen/VexRiscv_SndNdD16Dyn8Sx.v --vivado-directives fit_timing \
    "$@" --out "build/$name" > "build/$name.log" 2>&1 || echo VIVADO_FAILED
echo "== end $(date)"
grep -E "Bitgen Completed|ERROR" "build/$name.log" | tail -3
f="build/$name/gateware/platform_z7_timing.rpt"
[ -f "$f" ] && grep -A3 "WNS(ns)" "$f" | head -4
grep -E "Slice LUTs|Block RAM Tile|Slice Registers|^\| Slice " "build/$name/gateware/platform_z7_utilization_synth.rpt" 2>/dev/null | head -3
grep -E "Slice LUTs|Block RAM Tile|Slice Registers|^\| Slice " "build/$name/gateware/platform_z7_utilization_place.rpt" 2>/dev/null | head -4
cmp "build/$name/csr.json" "$W/prototypes/lut_diet/desk_ref/csr.json" && echo CSR-SAME-AS-DESK || echo CSR-CHANGED
