#!/usr/bin/env bash
# The MP3 player's reference decode (apps/mp3_check.mjs's pins): the vendored pvmp3 (libs/c/pvmp3)
# built for the host through the BARD study's adapter, so the player's output can be held against
# the decoder alone. s16le interleaved PCM out, the ID3 tag skipped, one hash a frame on stdout.
#   fpga/tools/mp3_ref.sh <in.mp3> <out.raw>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
U="$ROOT/libs/c/pvmp3/upstream"
EXE="$ROOT/fpga/build/tools/mp3_ref"
mkdir -p "$(dirname "$EXE")"
if [ ! -x "$EXE" ] || [ -n "$(find "$U" "$ROOT/fpga/tools/mp3_bard_host.c" "$ROOT/fpga/cycles/sound/mp3a_pv.c" -newer "$EXE" -print -quit)" ]; then
    g++ -x c++ -O2 -w -include "$ROOT/libs/c/pvmp3/config/zm_pvmp3.h" -I"$ROOT/fpga/cycles/sound" -I"$U/include" -I"$U/src" \
        -o "$EXE" "$ROOT/fpga/tools/mp3_bard_host.c" "$ROOT/fpga/cycles/sound/mp3a_pv.c" -x none "$U"/src/*.cpp
fi
"$EXE" "$1" "$2"
