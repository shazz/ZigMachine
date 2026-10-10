#!/usr/bin/env bash
# pnr_slot.sh CMD...: run CMD (one openXC7 container) holding one of the box's TWO P&R slots.
#
# The box (15 GB, 8 cores) takes two 6 GB containers at once. Slot 0 is the lock every
# P&R target already takes (`flock build/fable_timing3/.container.lock`, the Makefile's
# HDMI_LOCK), so a job here is serialised against all of those; slot 1 is the second
# container. CMD gets the first free slot, waiting for one if both are taken.
# PNR_SLOTS=1 limits it to slot 0 (one container, as the plain flock).
set -euo pipefail
FPGA="$(cd "$(dirname "$0")/.." && pwd)"
SLOTS=("$FPGA/build/fable_timing3/.container.lock" "$FPGA/build/.container.slot1.lock")
n=${PNR_SLOTS:-2}
mkdir -p "$FPGA/build/fable_timing3"
while true; do
    for s in "${SLOTS[@]:0:$n}"; do
        exec 9>>"$s"
        if flock -n 9; then
            echo "pnr_slot: $(basename "$s") -> $*" >&2
            exec "$@"  # fd 9, and the lock, live as long as CMD
        fi
    done
    sleep 3
done
