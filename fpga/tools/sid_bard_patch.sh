#!/usr/bin/env bash
# The BARD SID study (fpga/review/SID_BARD_STUDY.md): a patched copy of libcRSID 1.58 in
# prototypes/sid_re/src_prof (local; from tools/sid_bard_fetch.sh), passed to sid_bard_bench.sh as SID_LIB
# with -DSID_PROF -include src_prof/sidprof.h. Always: cycle-counter probes between the phases of
# cRSID_emulateC64 (sidbench.c prints them: cpu = 6502+CIA+VIC(+ADSR), wave = HQ oscillators,
# filt = filter/output stage). ADSR=1 also splits the ADSRs out (two reads per 6502 step, +5 %).
# FAST=1: the two bit-exact divide patches (ZDIV, ZRECIP). CURVE_RATE=<hz>: the light engine's cutoff
# table regenerated for that output rate by cRSID's own curvegen.
#   [FAST=1] [ADSR=1] [CURVE_RATE=22050] tools/sid_bard_patch.sh
set -eu
P="$(cd "$(dirname "$0")/../.." && pwd)/prototypes/sid_re"
mkdir -p "$P/build/cg"
rm -rf "$P/src_prof" && cp -r "$P/src/cRSID-1.58/libcRSID" "$P/src_prof"
C="$P/src_prof/C64/C64.c"
sed -i '179s/{$/{ SIDPROF_T(0);/' "$C"
sed -i '237s/$/ SIDPROF_T(1);/' "$C"
sed -i '246s/^/ SIDPROF_T(2);/' "$C"
sed -i '267s/^/ SIDPROF_T(3);/' "$C"
if [ "${ADSR:-0}" = 1 ]; then
    sed -i '229s/$/ SIDPROF_T(1);/' "$C"
    sed -i '235s/^/ SIDPROF_T(4);/' "$C"
fi
if [ "${FAST:-0}" = 1 ]; then
    # Bit-exact: a runtime divide by a run-constant divisor becomes a switch to constant divides,
    # which gcc turns into multiplies (Zmmul has mulh). 5/6 oversamples a sample, attenuation 13.
    R="$P/src_prof/C64/C64_SIDrouting.c"
    sed -i 's/\(cRSID_C64\.SID\[[0-9]\]\.[A-Za-z]*\) \/= HQsampleCount;/\1 = ZDIV(\1, HQsampleCount);/g' "$R"
    sed -i 's/Output\.\([LR]\) \/= cRSID_C64\.Attenuation;/Output.\1 = ZDIV(Output.\1, cRSID_C64.Attenuation);/g' "$R"
    grep -c ZDIV "$R"
    # The light pulse's edge steepness divides per sample by the voice's frequency step: memoise it.
    sed -i 's|PHASEACCU_MAX/PhaseAccuStep|ZRECIP(SID, Channel, PHASEACCU_MAX, PhaseAccuStep)|' "$P/src_prof/C64/SID_OscWaves.c"
    grep -c ZRECIP "$P/src_prof/C64/SID_OscWaves.c"
fi
if [ -n "${CURVE_RATE:-}" ]; then
    # The light engine's cutoff table is generated for 44.1 kHz: regenerate it for the bench's rate.
    sed "s/samplerate=44100/samplerate=$CURVE_RATE/" "$P/src_prof/tools/curvegen.c" >"$P/build/cg/curvegen_r.c"
    gcc -O2 -I"$P/src_prof/tools" -o "$P/build/cg/curvegen_r" "$P/build/cg/curvegen_r.c" -lm
    "$P/build/cg/curvegen_r" "$P/src_prof/C64/SID_FilterCurves.h" >/dev/null
    grep -m1 "CutoffMul8580_44100Hz" "$P/src_prof/C64/SID_FilterCurves.h"
fi
sed -n '179p;229p;235p;237p;246p;267p' "$C"
cat >"$P/src_prof/sidprof.h" <<'EOF'
#ifndef __ASSEMBLER__
#include <stdint.h>
__attribute__((weak)) uint32_t sidprof_acc[5], sidprof_last;
#ifdef ZM_SND
#include "snd_mailbox.h"
#define SIDPROF_NOW() SND_REG(SND_CYCLES)
#else
#define SIDPROF_NOW() 0u
#endif
#define ZDIV(x, d) ((d) == 5 ? (x) / 5 : (d) == 6 ? (x) / 6 : (d) == 13 ? (x) / 13 : (x) / (d))
static inline unsigned zrecip(const void *sid, int ch, unsigned num, unsigned step) {
    static const void *s[16];
    static unsigned st[16], q[16];
    if (s[ch] != sid || st[ch] != step) s[ch] = sid, st[ch] = step, q[ch] = num / step;
    return q[ch];
}
#define ZRECIP(sid, ch, num, step) zrecip(sid, ch, num, step)
#define SIDPROF_T(i) do { uint32_t n_ = SIDPROF_NOW(); if (i) sidprof_acc[i] += n_ - sidprof_last; sidprof_last = n_; } while (0)
#endif
EOF
