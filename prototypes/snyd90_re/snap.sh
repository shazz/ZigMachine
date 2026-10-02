#!/bin/sh
# snap.sh FIFO SECS OUTPREFIX: SECS seconds after start, freeze a run_hatari.sh Hatari through its
# --cmd-fifo and save its RAM ($0..$80000) and a screenshot of the same moment (debugger
# commands: Hatari runs them at its next VBL, both inside the same stop).
fifo=$1; at=$2; out=$3
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt "$at" ]; do sleep 1; done
[ -p "$fifo" ] || exit 0
echo "hatari-debug savebin $out.bin \$0 \$80000" > "$fifo"
sleep 0.2
echo "hatari-debug screenshot $out.png" > "$fifo"
