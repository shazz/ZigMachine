/* The YM2612 (OPN2, the Mega Drive's FM chip): our own fixed-point model, MIT (libs/c/ym2612/README.md).
 * Six 4-operator FM channels, the 8 algorithms, op 1 feedback, the 4-state envelope generator with its
 * rate table and key scaling, detune and multiple, the LFO (AM and PM), channel 3's special mode, SSG-EG,
 * and the 8-bit DAC on channel 6. Not modelled: the timers and CSM key-on, the status register, the 9-bit
 * DAC's ladder distortion (an analogue artefact of the discrete chip).
 * Integers only, no divide: it runs on BARD (rv32i + Zmmul, no FPU, no divider), in machine-audio.wasm
 * and natively, sample for sample the same. The chip's own rate is clock / 144 (53,267 Hz NTSC);
 * `div` 2 renders every other chip sample (26,634 Hz: phases, envelopes and the LFO advance two chip
 * samples a render), the rate the BARD player uses. */
#ifndef ZM_YM2612_H
#define ZM_YM2612_H

#include <stdint.h>

enum { YM_ATTACK = 0, YM_DECAY = 1, YM_SUSTAIN = 2, YM_RELEASE = 3 };

typedef struct {
    uint32_t phase;           /* 20 bits: the top 10 index the sine */
    uint32_t inc;             /* the phase increment a render (already x div) */
    int32_t att;              /* 10-bit attenuation, 0 loudest, 0x3FF silent */
    uint8_t state, key, ssg_inv, am_on;
    uint8_t dt, mul, ks, ar, d1r, d2r, rr, ssg;
    uint16_t tl3, sl;         /* TL << 3; sustain level as an attenuation */
    uint16_t eatt;            /* the attenuation heard before AM: SSG-adjusted att + TL (ym_op_eatt) */
    uint8_t rate[4];          /* effective rate (0..63) of each EG state, key scaling applied */
    uint8_t eg_rate, eg_shift; /* the current state's rate and update shift; eg_mask = 2^shift - 1 */
    uint16_t eg_mask;
    uint32_t fnum, block, kc; /* this operator's pitch (channel 3's special mode gives each its own) */
} ym_op;

typedef struct {
    ym_op op[4];              /* register order: S1, S3, S2, S4 (offsets 0, 4, 8, C) */
    int32_t fb1, fb2;         /* op 1's last two outputs (feedback) */
    int32_t mem;              /* the one-sample delayed link of algorithms 0-2 */
    int32_t pm;               /* the LFO's PM now: depth x signed step (fnum x pm >> 16 is the deviation) */
    uint32_t fnum, block, kc;
    uint8_t alg, fb, ams, pms, pan; /* pan: bit 1 left, bit 0 right */
    uint8_t live;             /* 0: every operator released to silence (the render skips it) */
} ym_ch;

typedef struct {
    ym_ch ch[6];
    uint32_t div;             /* chip samples a render: 1 or 2 */
    uint32_t eg_acc, eg_cnt;  /* chip samples toward the next EG tick (every 3); EG ticks so far */
    uint32_t lfo_on, lfo_inc, lfo_pos, lfo_cnt; /* the LFO: Q16 advance a render, Q16 position, its 7-bit step */
    uint32_t am;              /* the LFO's AM triangle, 0..126 attenuation units */
    uint32_t ch3_mode, dac_on;
    int32_t dac;              /* the DAC's sample, signed, in operator units */
    uint32_t latch_hi[2], latch3_hi; /* the A4-A6 / AC-AE latches (written before A0-A2 / A8-AA) */
    uint32_t fnum3[3], block3[3];   /* channel 3's special frequencies: A9 op1, AA op2, A8 op3 */
    int32_t gain;             /* Q8: the 6 channels' sum to s16 */
} ym2612;

/* Power-on: every register 0 (pans both on), silent. `div` 1 or 2 (anything else is 2). */
void ym2612_reset(ym2612 *y, uint32_t div);
/* A register write: `port` 0 (channels 1-3 and the globals) or 1 (channels 4-6), `reg` 0x21..0xB6. */
void ym2612_write(ym2612 *y, uint32_t port, uint32_t reg, uint32_t val);
/* `n` renders, interleaved L R s16, into `lr` (written, not added). */
void ym2612_render(ym2612 *y, int16_t *lr, uint32_t n);

/* Internal, shared by ym2612.c and ym2612_eg.c. */
void ym_op_pitch(const ym2612 *y, const ym_ch *c, ym_op *o);
void ym_op_rates(ym_op *o);
void ym_eg_tick(ym2612 *y);
void ym_key(ym_op *o, uint32_t on);
void ym_ch_pm(ym2612 *y, ym_ch *c);
void ym_op_eatt(ym_op *o);

#endif
