/* The .vgm player's output stage in C (zm_vgm.h zm_vgm_render_paula): the engine's stereo at its own rate
 * converted to the mixer's 44.1 kHz and split into the four Paula channels' bytes. Exactly the Zig players'
 * stage (libs/zig/players/mp3_resample.zig's Linear, mp3_out.zig's bytes), moved here so BARD runs it natively
 * instead of through wasm2c: per output frame it was a fifth of the player's cost. apps/harness/vgm_check.mjs holds it
 * to a JavaScript copy of the Zig stage, sample for sample. Our own code. */
#include "zm_vgm.h"
#include "zm_vgm_sfx.h"

#define OUT_RATE 44100u
#define RECIP 48696u               /* ceil(2^31 / 44100): pos x RECIP >> 16 is pos / 44100 in Q15 */
#define Y_MAX (127 * 128 + 63)     /* the top of x >> 1 that a hi/lo pair can carry */
#define CHUNK 256u                 /* engine frames a refill */

static struct {
    uint32_t rate, pos, at, n, primed;
    uint32_t taken, made; /* engine frames taken by the resampler, rendered into chunks (since the reset) */
    int32_t a[2], b[2];
    int16_t chunk[2 * CHUNK];
} zo;

void zm_vgm_out_reset(uint32_t rate) {
    zo.rate = rate;
    zo.pos = zo.at = zo.n = zo.primed = 0;
    zo.taken = zo.made = 0;
    zo.a[0] = zo.a[1] = zo.b[0] = zo.b[1] = 0;
}

static void push(void) {
    if (zo.at >= zo.n) {
        zm_vgm_render(zo.chunk, CHUNK);
        zo.made += CHUNK;
        zo.at = 0;
        zo.n = CHUNK;
    }
    zo.a[0] = zo.b[0], zo.a[1] = zo.b[1];
    zo.b[0] = zo.chunk[2 * zo.at], zo.b[1] = zo.chunk[2 * zo.at + 1];
    zo.at++;
    zo.taken++;
}

static void split(int32_t x, int8_t *hi, int8_t *lo) {
    int32_t y = x >> 1;
    if (y > Y_MAX) y = Y_MAX;
    int32_t h = (y + 64) >> 7;
    *hi = (int8_t)h;
    *lo = (int8_t)(y - h * 128);
}

void zm_vgm_render_paula(int8_t *hl, int8_t *hr, int8_t *ll, int8_t *lr, uint32_t n) {
    if (!zo.primed) { /* no delay: the first output sample is the first engine sample */
        push(), push();
        zo.primed = 1;
    }
    for (uint32_t i = 0; i < n; i++) {
        uint32_t w = (zo.pos * RECIP) >> 16;
        int32_t q = (int32_t)(w > 32767u ? 32767u : w);
        split(zo.a[0] + (((zo.b[0] - zo.a[0]) * q) >> 15), &hl[i], &ll[i]);
        split(zo.a[1] + (((zo.b[1] - zo.a[1]) * q) >> 15), &hr[i], &lr[i]);
        for (zo.pos += zo.rate; zo.pos >= OUT_RATE; zo.pos -= OUT_RATE) push();
    }
    zm_sfx_output(n);
}

/* The SFX device's map (zm_vgm_sfx.h): each output frame takes the engine frames its position passes, after
 * the two a first call primes. d < 2^32 / rate (the device holds it to 100,000). */
int32_t zm_vgm_out_lead(uint32_t d) {
    uint32_t taken = zo.taken + (zo.primed ? 0u : 2u) + (zo.pos + d * zo.rate) / OUT_RATE;
    return (int32_t)(taken - zo.made);
}
