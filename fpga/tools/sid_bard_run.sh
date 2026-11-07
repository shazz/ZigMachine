#!/usr/bin/env bash
# The BARD SID study: run one tools/sid_bard_bench.sh image on a soc_hp_snd model under a sim slot,
# keep BARD's uart, and check every frame's PCM hash against the host twin (tools/sid_bard_check.py).
#   tools/sid_bard_run.sh <tag> [model dir, default build/soc_hp_snd16] [slot lock, default sim-b]
set -euo pipefail
FPGA="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$FPGA/.." && pwd)"
TAG=${1:?tag} SOC=${2:-$FPGA/build/soc_hp_snd16} SLOT=${3:-sim-b}
B="$ROOT/prototypes/sid_re/build/$TAG"
LOCKS=/home/matt/projects/ZigMachine/prototypes/_gate_logs
run=/dev/shm/sid_bard_$TAG
rc=0
flock "$LOCKS/$SLOT.lock" env ZM_SOC="$SOC" ZM_INIT=sim_zm_ddr.init \
    "$FPGA/tools/cycles_sim.sh" "$B/zm_ddr.init" "$run" "${SID_SIM_LIMIT:-5400}" || rc=$?
cp "$run/uart.txt" "$B/bard_uart.txt"
rm -rf "$run"
echo "sim exit $rc"
uv run -q python "$FPGA/tools/sid_bard_check.py" "$B"
