#!/usr/bin/env bash
# Run ONE firmware image in the cycles sim (soc/cycles_sim.py) and keep its UART.
#
#   tools/cycles_sim.sh <main_ram.init> <run-dir> [timeout-seconds]
#
# The Verilated model reads sim_main_ram.init from its working directory, so
# each run gets its own directory: the image, plus links to the model's other
# runtime files. Only the two sim modules this SoC uses are linked, because the
# harness dlopen()s every module it finds. stdin is a pipe that stays open:
# the UART console module polls it, and it cannot poll /dev/null.
# Writes <run-dir>/uart.txt; exit status is the firmware's "ZM END" code, or 124
# on a timeout, or 125 if the firmware never reported an end.
set -uo pipefail
FPGA="$(cd "$(dirname "$0")/.." && pwd)"
GW="$FPGA/build/soc_cycles/gateware"
img=$1 run=$2 limit=${3:-86400}
[ -x "$GW/obj_dir/Vsim" ] || { echo "cycles_sim: no model, run make -C fpga cycles-sim" >&2; exit 2; }
rm -rf "$run" && mkdir -p "$run/modules"
for f in sim_config.js sim_mem.init sim_sram.init; do ln -s "$GW/$f" "$run/$f"; done
for m in clocker serial2console; do ln -s "$GW/modules/$m.so" "$run/modules/$m.so"; done
cp "$img" "$run/sim_main_ram.init"
cd "$run" || exit 2
# A `sleep` holds stdin open; it is killed as soon as the sim ends.
exec 3< <(exec sleep "$limit")
holder=$!
timeout "$limit" stdbuf -o0 "$GW/obj_dir/Vsim" <&3 >uart.txt 2>sim.err
rc=$?
kill "$holder" 2>/dev/null
[ $rc -eq 124 ] && exit 124
end=$(grep -a '^ZM END ' uart.txt | tail -1 | cut -d' ' -f3)
[ -n "$end" ] || exit 125
exit "$end"
