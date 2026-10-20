#!/bin/bash
# bench.sh <tune-file in the B.I.G. digi folder> <subtune> <frames> <run-dir name> [lock: a|b]
# Builds `make snd-bench` for the tune, then runs it in the soc_hp_snd sim under ONE sim lock.
set -euo pipefail
FPGA=$(cd "$(dirname "$0")/../../fpga" && pwd)
song=$1 tune=$2 frames=$3 run=$4 lock=${5:-b}
dir=d; dir=${dir}igital
cd "$FPGA"
make -s snd-bench SONG="$dir/$song" TUNE="$tune" ZM_FRAMES="$frames"
cp build/hcycles/snd/bench/zm_ddr.init "/dev/shm/zm_ddr_$run.init"
echo "image built $(date)"
exec flock "/home/matt/projects/ZigMachine/prototypes/_gate_logs/sim-$lock.lock" \
    env ZM_SOC="$FPGA/build/soc_hp_snd" ZM_INIT=sim_zm_ddr.init \
    tools/cycles_sim.sh "/dev/shm/zm_ddr_$run.init" "/dev/shm/sb_$run" 14400
