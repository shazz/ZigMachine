/* What the patched cRSID tree needs from us (patches/*.sed, README.md). Included before cRSID's own
 * sources: zm_sid.c includes it first, then the unity build libcRSID.c. */
#ifndef ZM_CRSID_H
#define ZM_CRSID_H

/* A runtime divide by a divisor fixed for the run (the output attenuation, 13 for one SID; the HQ
 * engine's 5 or 6 oversamples) as a constant divide: GCC with -mno-div and every wasm compiler turn a
 * constant divide into a multiply, BARD's __divsi3 costs ~400 cycles. Same result for any divisor. */
#define ZDIV(x, d) ((d) == 13 ? (x) / 13 : (d) == 5 ? (x) / 5 : (d) == 6 ? (x) / 6 : (x) / (d))

/* The light pulse's PHASEACCU_MAX / PhaseAccuStep, memoised per voice: the step only changes with
 * the voice's frequency registers. Keyed by the SID and the voice's register offset (0, 7, 14). */
static inline unsigned int zm_crsid_recip(const void *sid, unsigned char ch, unsigned int num, unsigned int step) {
    static const void *s[16];
    static unsigned int st[16], q[16];
    if (s[ch] != sid || st[ch] != step) {
        s[ch] = sid;
        st[ch] = step;
        q[ch] = num / step;
    }
    return q[ch];
}
#define ZRECIP(sid, ch, num, step) zm_crsid_recip((sid), (ch), (num), (step))

/* The output dither's LFSR (host/audio.c), out of its function so a load can reset it. */
extern int zm_crsid_lfsr;
#define LFSR zm_crsid_lfsr

#endif
