/* The Sega SN76489 (sn76489.h), written from the chip's documented behaviour: Texas Instruments'
 * SN76489AN data sheet (register format, tone counters at clock / 16, 2 dB attenuation steps) and the
 * Sega variant's details as SMS Power's "SN76489" notes (Maxim) record them: a 16-bit LFSR with white
 * noise taps on bits 0 and 3, reset to 0x8000 on a noise write; noise at clock / 16 / (2 x 0x10, 0x20,
 * 0x40) or half tone 2's rate; periods 0 and 1 hold a tone high; the Game Gear stereo port. Our own code. */
#include "sn76489.h"

#include "../vgm/zm_mem.h"

/* 8191 x 10^(-i / 10): 2 dB steps of a 13-bit peak; 15 is off. */
static const int32_t VOL[16] = {8191, 6506, 5168, 4105, 3261, 2590, 2057, 1634,
                                1298, 1031, 819,  651,  517,  411,  326,  0};

void sn76489_reset(sn76489 *p, uint32_t clock, uint32_t rate, int32_t gain) {
    memset(p, 0, sizeof *p);
    p->span = (int32_t)(((uint64_t)clock << 8) / (16ull * (rate ? rate : 44100u))); /* reset only */
    if (p->span < 1) p->span = 1;
    p->recip = (int32_t)((1u << 24) / (uint32_t)p->span);
    p->gain = gain;
    p->lfsr = 0x8000;
    p->stereo = 0xFF;
    for (uint32_t c = 0; c < 4; c++) p->att[c] = 15, p->cnt[c] = 256;
    p->period[3] = 0x10;
}

static uint32_t noise_period(const sn76489 *p) {
    uint32_t nf = p->noise & 3u;
    if (nf < 3) return 0x10u << nf;
    return p->period[2] ? p->period[2] : 1u;
}

void sn76489_write(sn76489 *p, uint32_t byte) {
    if (byte & 0x80u) p->latch = byte >> 4 & 7u;
    uint32_t c = p->latch >> 1;
    if (p->latch & 1u) {
        p->att[c] = byte & 15u;
    } else if (c < 3) {
        uint32_t per = p->period[c];
        per = byte & 0x80u ? (per & 0x3F0u) | (byte & 15u) : (per & 15u) | (byte & 0x3Fu) << 4;
        p->period[c] = per;
        if (c == 2 && (p->noise & 3u) == 3u) p->period[3] = noise_period(p);
    } else {
        p->noise = byte & 7u;
        p->period[3] = noise_period(p);
        p->lfsr = 0x8000;
    }
}

void sn76489_stereo(sn76489 *p, uint32_t byte) { p->stereo = byte & 0xFFu; }

static uint32_t shift(uint32_t lfsr, uint32_t white) {
    uint32_t fb = white ? (lfsr ^ lfsr >> 3) & 1u : lfsr & 1u;
    return lfsr >> 1 | fb << 15;
}

/* Counter c over one sample: the Q8 ticks its output was high. A tone's output is its flip-flop; the
 * noise's is the LFSR's bit 0, the LFSR shifting as its flip-flop rises. */
static int32_t run(sn76489 *p, uint32_t c) {
    uint32_t per = p->period[c];
    if (c < 3 && per <= 1u) return p->span; /* held high */
    int32_t step = (int32_t)(per << 8), left = p->span, high = 0, cnt = p->cnt[c];
    uint32_t lv = p->level[c], white = p->noise & 4u;
    while (cnt <= left) {
        uint32_t out = c < 3 ? lv : p->lfsr & 1u;
        if (out) high += cnt;
        left -= cnt;
        lv ^= 1u;
        if (c == 3 && lv) p->lfsr = shift(p->lfsr, white);
        cnt = step;
    }
    if (c < 3 ? lv : p->lfsr & 1u) high += left;
    p->cnt[c] = cnt - left;
    p->level[c] = lv;
    return high;
}

static int16_t sat(int32_t v) { return (int16_t)(v > 32767 ? 32767 : v < -32768 ? -32768 : v); }

void sn76489_mix(sn76489 *p, int16_t *lr, uint32_t n) {
    int32_t amp[4];
    uint32_t live = 0;
    for (uint32_t c = 0; c < 4; c++) {
        amp[c] = (VOL[p->att[c]] * p->gain) >> 13;
        live |= amp[c] != 0;
    }
    if (!live) return; /* all off: nothing to add (the counters stand still) */
    for (uint32_t i = 0; i < n; i++) {
        int32_t l = 0, r = 0;
        for (uint32_t c = 0; c < 4; c++) {
            int32_t m = ((2 * run(p, c) - p->span) * p->recip) >> 8; /* Q16 mean, -1..1 */
            int32_t v = (amp[c] * m) >> 16;
            if (p->stereo >> (c + 4) & 1u) l += v;
            if (p->stereo >> c & 1u) r += v;
        }
        lr[2 * i] = sat(lr[2 * i] + l);
        lr[2 * i + 1] = sat(lr[2 * i + 1] + r);
    }
}
