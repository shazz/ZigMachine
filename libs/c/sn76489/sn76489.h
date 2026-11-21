/* The SN76489 PSG as the Sega chips have it (Mega Drive, Master System, Game Gear): our own model, MIT
 * (libs/c/sn76489/README.md). Three square tones and a noise channel, each a 10-bit / 3-way down counter
 * clocked at clock / 16; the noise a 16-bit LFSR (white: taps bits 0 and 3; periodic: bit 0), reset by a
 * noise write; 4-bit attenuation in 2 dB steps (15 is off); periods 0 and 1 hold the output high (the
 * PCM trick); the Game Gear's stereo register. Each output sample is the exact mean of the counters'
 * levels over its span (a box filter): no aliasing pile-up from point sampling.
 * Integers only, no divide after reset (BARD has no divider). */
#ifndef ZM_SN76489_H
#define ZM_SN76489_H

#include <stdint.h>

typedef struct {
    uint32_t period[4];   /* tones: 10 bits; noise: its reload (0x10, 0x20, 0x40 or tone 2's) */
    int32_t cnt[4];       /* Q8 ticks of clock / 16 to the counter's next toggle */
    uint32_t level[4];    /* the counter's flip-flop (tones: the output; noise: the LFSR's clock) */
    uint32_t att[4], latch, noise, lfsr, stereo;
    int32_t span;         /* Q8 ticks a sample */
    int32_t recip;        /* 2^24 / span: a sum of levels to a Q16 mean */
    int32_t gain;         /* amplitude of one channel at attenuation 0 */
} sn76489;

/* `clock` the chip's (3579545 NTSC), `rate` the output's; gain: one channel's peak at full volume. */
void sn76489_reset(sn76489 *p, uint32_t clock, uint32_t rate, int32_t gain);
/* A byte to the chip's data port (latch/data or data). */
void sn76489_write(sn76489 *p, uint32_t byte);
/* The Game Gear's stereo byte (port 0x06): bit c + 4 left, bit c right, for channel c. */
void sn76489_stereo(sn76489 *p, uint32_t byte);
/* Adds `n` samples into interleaved stereo `lr` (saturating). */
void sn76489_mix(sn76489 *p, int16_t *lr, uint32_t n);

#endif
