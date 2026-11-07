#!/usr/bin/env bash
# The BARD MP3 study (fpga/review/MP3_BARD_STUDY.md): build one decoder for the host (accuracy against
# ffmpeg, the per-frame PCM hashes) and for BARD (the snd-cbench image, run it with tools/cycles_sim.sh
# on a soc_hp_snd model). Needs tools/mp3_bard_fetch.sh and tools/mp3_bard_streams.sh first.
#   tools/mp3_bard_bench.sh helix [host|bard|all] [extra CFLAGS for both builds]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P="$ROOT/prototypes/mp3_bard_re"
DEC=${1:-helix} WHAT=${2:-all} XCFLAGS=${3:-}
B="$P/build/$DEC"
mkdir -p "$B"
case "$DEC" in
helix)
    S="$P/src/helix/src"
    INC="-I$S/pub -I$S/real"
    SRC="$S/mp3dec.c $S/mp3tabs.c $(echo "$S"/real/*.c)"
    HOSTCC="gcc"
    ADA="$ROOT/fpga/cycles/sound/mp3a_helix.c" ;;
pv)
    S="$P/src/pvmp3"
    INC="-I$S/include -I$S/src -include $ROOT/fpga/cycles/sound/mp3a_pv_shim.h"
    SRC="$(ls "$S"/src/*.cpp | tr '\n' ' ')"
    HOSTCC="g++ -x c++"
    ADA="$ROOT/fpga/cycles/sound/mp3a_pv.c" ;;
*) echo "decoder: helix | pv" >&2; exit 2 ;;
esac
if [ "$WHAT" != bard ]; then
    # shellcheck disable=SC2086 # INC/SRC/XCFLAGS are word lists
    $HOSTCC -O2 -w -I"$ROOT/fpga/cycles/sound" $INC $XCFLAGS -o "$B/host" "$ROOT/fpga/tools/mp3_bard_host.c" "$ADA" -x none $SRC
    for s in s44_128 s32_128 m44_64 s44_320; do
        "$B/host" "$P/streams/$s.mp3" "$B/$s.raw" >"$B/$s.txt"
        ch=$(awk 'NR==1{print $7}' "$B/$s.txt")
        uv run -q --with numpy python "$ROOT/fpga/tools/mp3_bard_snr.py" "$P/streams/$s.mp3" "$B/$s.raw" "$ch"
    done
fi
if [ "$WHAT" != host ]; then
    make -C "$ROOT/fpga" snd-cbench CBENCH_CFLAGS="$INC $XCFLAGS" \
        CBENCH_SRC="cycles/sound/mp3bench.c $ADA $SRC $P/streams/streams.c"
    cp "$ROOT/fpga/build/hcycles/snd/cbench/zm_ddr.init" "$B/zm_ddr.init"
    riscv64-unknown-elf-size "$ROOT/fpga/build/hcycles/snd/cbench/snd.elf" | tee "$B/size.txt"
fi
