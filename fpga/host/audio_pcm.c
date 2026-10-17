/* The stream ring from this side (haudio.h audio_pcm_*): demo-audio.wasm's audioStreamStart
 * loops Paula channel 0 over RING bytes at song RAM, and something has to write them. Two
 * writers, as docs/audio-worklet-sealed.js has:
 *   the cart's feed (zg.audioStreamStart / audioFeed / audioStreamStop): bytes appended at the
 *     write cursor as the cart hands them over, paced by the cart;
 *   a whole sample (zg.samplePlay / sampleStop): the ring refilled from here before every
 *     render, CUSHION bytes ahead of the channel, from the sample's bytes in the cart's memory
 *     (on the board the sound CPU reads them in DDR), looping or ending, no cart in the loop.
 * The channel reads a byte when the core plays it, after the players' lead: a byte written at
 * render time is always ahead of it, and lead + CUSHION stays well under RING. */
#include <string.h>

#include "haudio.h"

#define RING 32768u   /* demo_audio_main.zig STREAM_RING (the worklet's RING) */
#define CUSHION 4096u /* a sample's bytes written ahead of the channel (the worklet's CUSHION) */

static uint32_t g_w; /* the ring's write cursor */
static struct {
    const uint8_t* src;
    uint32_t len, pos, step, loop, on;
    uint64_t read;    /* where the channel will be after the samples rendered, 16.16 */
    uint64_t written; /* bytes written into the ring since the start */
} g_s;

static uint8_t* ring(void) { return g_aud.memory.data + w2c_audio_audioSongPtr(&g_aud.player); }

/* `n` bytes of `src` (silence when NULL) at the write cursor, wrapping. */
static void put(const uint8_t* src, uint32_t n) {
    while (n) {
        uint32_t k = n < RING - g_w ? n : RING - g_w;
        if (src) memcpy(ring() + g_w, src, k), src += k;
        else memset(ring() + g_w, 0, k);
        g_w = (g_w + k) % RING;
        n -= k;
    }
}

static void stream_start(uint32_t rate) {
    g_s.on = 0;
    w2c_audio_audioStreamStart(&g_aud.player, (float)rate);
    g_w = 0;
}

static void stream_stop(void) {
    g_s.on = 0;
    w2c_audio_audioStreamStop(&g_aud.player);
    g_w = 0;
}

static void sample_play(const audio_fx* fx) {
    if (!fx->len) return;
    stream_start(fx->rate);
    /* The channel's own step: demo_audio_raw.zig's rate / SAMPLE_RATE * FRAC_ONE, in f32. */
    uint32_t step = (uint32_t)((float)fx->rate / 44100.0f * 65536.0f);
    g_s = (__typeof__(g_s)){.src = (const uint8_t*)fx->pcm, .len = fx->len, .step = step, .loop = fx->a != 0, .on = 1};
    audio_pcm_refill(0);
}

int audio_pcm_effect(const audio_fx* fx) {
    switch (fx->op) {
    case FX_SAMPLE: sample_play(fx); return 1;
    case FX_SAMPLE_STOP: if (g_s.on) stream_stop(); return 1;
    case FX_STREAM_START: stream_start(fx->rate); return 1;
    case FX_STREAM_FEED: put((const uint8_t*)fx->pcm, fx->len); return 1;
    case FX_STREAM_STOP: stream_stop(); return 1;
    default: return 0;
    }
}

void audio_pcm_forget(void) { g_s.on = 0; }

/* Before `n` samples: the ring written up to where the channel will have read after them, plus
 * CUSHION. Past a one-shot's end, silence; once the channel has read it all, the channel off. */
void audio_pcm_refill(uint32_t n) {
    if (!g_s.on) return;
    g_s.read += (uint64_t)n * g_s.step;
    uint64_t read = g_s.read >> 16;
    if (!g_s.loop && g_s.pos >= g_s.len && read >= g_s.len) {
        stream_stop();
        return;
    }
    while (g_s.written < read + CUSHION) {
        uint32_t k = (uint32_t)(read + CUSHION - g_s.written);
        if (g_s.pos < g_s.len) {
            if (k > g_s.len - g_s.pos) k = g_s.len - g_s.pos;
            put(g_s.src + g_s.pos, k);
            g_s.pos += k;
            if (g_s.loop && g_s.pos == g_s.len) g_s.pos = 0;
        } else {
            put(NULL, k);
        }
        g_s.written += k;
    }
}
