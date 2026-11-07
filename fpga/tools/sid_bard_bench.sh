#!/usr/bin/env bash
# The BARD SID study (fpga/review/SID_BARD_STUDY.md): build cRSID for the host (the per-frame PCM hashes
# BARD must match, plus a 60 s WAV of each tune to listen to) and for BARD (the snd-cbench image; run it
# with tools/cycles_sim.sh on a soc_hp_snd model). Needs tools/sid_bard_fetch.sh first.
#   tools/sid_bard_bench.sh <tag> [host|bard|all] [extra CFLAGS for both builds, e.g. -DSID_HQ=0]
# SID_BARD_CFLAGS: BARD-only flags, e.g. "-march=rv32im -mno-div" (GCC then turns constant divides into
# MULH; with -march=rv32i_zmmul it calls __divsi3 for them. The link keeps the rv32i multilib).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P="$ROOT/prototypes/sid_re"
L=${SID_LIB:-$P/src/cRSID-1.58/libcRSID} # SID_LIB: a patched copy (the profile)
TAG=${1:?tag} WHAT=${2:-all} XCFLAGS=${3:-}
FRAMES=${SID_FRAMES:-6} WAVSEC=${SID_WAVSEC:-60} LIST=${SID_LIST:-$P/tunes.list}
B="$P/build/$TAG"
mkdir -p "$B" "$P/wav"
# The tunes as C arrays (sidbench.h sid_tunes), in tunes.list order.
{
    echo '#include "sidbench.h"'
    n=0
    while read -r f sub _; do
        echo "static const uint8_t t$n[] = {$(od -An -v -tu1 "$P/tunes/$f" | tr -s ' \n' ',' | sed 's/^,//;s/,$//')};"
        n=$((n + 1))
    done <"$LIST"
    echo 'const sid_tune_t sid_tunes[] = {'
    n=0
    while read -r f sub _; do
        echo "    {\"${f%.sid}\", t$n, sizeof t$n, $sub},"
        n=$((n + 1))
    done <"$LIST"
    echo '};'
    echo "const int sid_ntunes = $n;"
} >"$B/tunes.c"
if [ "$WHAT" != bard ]; then
    # shellcheck disable=SC2086 # XCFLAGS is a word list
    gcc -std=gnu99 -O2 -w $XCFLAGS -I"$L" -I"$ROOT/fpga/cycles/sound" -o "$B/host" \
        "$ROOT/fpga/tools/sid_bard_host.c" "$L/libcRSID.c"
    earlier=() # cRSID keeps state across tunes: the host replays what BARD played before (sid_bard_host.c)
    while read -r f sub _; do
        "$B/host" "$P/wav/${f%.sid}_$TAG.wav" $((WAVSEC * 60)) "$FRAMES" "${earlier[@]}" "$P/tunes/$f" "$sub" \
            >"$B/${f%.sid}.txt"
        grep -E 'SIDINFO|HOSTTIME' "$B/${f%.sid}.txt"
        earlier+=("$P/tunes/$f" "$sub")
    done <"$LIST"
fi
if [ "$WHAT" != host ]; then
    make -C "$ROOT/fpga" snd-cbench CBENCH_CFLAGS="-I$L -DSID_FRAMES=$FRAMES $XCFLAGS ${SID_BARD_CFLAGS:-}" \
        CBENCH_SRC="cycles/sound/sidbench.c cycles/sound/cbdiv.c $L/libcRSID.c $B/tunes.c"
    cp "$ROOT/fpga/build/hcycles/snd/cbench/zm_ddr.init" "$B/zm_ddr.init"
    riscv64-unknown-elf-size "$ROOT/fpga/build/hcycles/snd/cbench/snd.elf" | tee "$B/size.txt"
fi
