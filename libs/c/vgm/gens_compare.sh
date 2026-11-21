#!/bin/sh
# LOCAL tool (libs/c/vgm/README.md "Accuracy"): our engine's FM against the Gens reference, tune by tune.
# The reference is libvgm's vgm2wav forced to the Gens YM2612 core (prototypes/gens_fm/ref: GPL-2, built on
# Matt's machine, never committed); only the numbers come out. Not in the gate: it needs that binary.
#   libs/c/vgm/gens_compare.sh [div 1|2] <tune.vgm>...
#     div 1: ours at the chip's 53,267 Hz against Gens at 53,267; div 2 (the BARD player's): 26,634 against 26,634
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
REF=${GENS_REF:-$ROOT/../../../prototypes/gens_fm/ref/vgm2wav_gens}
[ -x "$REF" ] || REF=/home/matt/projects/ZigMachine/prototypes/gens_fm/ref/vgm2wav_gens
[ -x "$REF" ] || { echo "gens_compare: no reference renderer ($REF)"; exit 2; }
DIV=1
case "${1:-}" in 1|2) DIV=$1; shift ;; esac
RATE=$((53267 / DIV))
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cc -O2 -DZM_VGM_DIV=$DIV -DZM_VGM_PSG_GAIN=0 -o "$TMP/vr" "$ROOT/fpga/tools/vgm_render.c" "$ROOT"/libs/c/vgm/*.c \
    "$ROOT"/libs/c/ym2612/*.c "$ROOT/libs/c/sn76489/sn76489.c"
for t in "$@"; do
    GENS_RATE=$RATE MUTE_PSG=1 "$REF" --loops 1 --fade 0 "$t" "$TMP/ref.wav" >/dev/null 2>&1
    "$TMP/vr" "$t" 21 -o "$TMP/ours.wav" >/dev/null
    printf '%s: ' "$(basename "$t")"
    uv run -q --with numpy --with scipy python "$ROOT/libs/c/vgm/gens_compare.py" "$TMP/ref.wav" "$TMP/ours.wav" 20 | sed -n 2p
done
