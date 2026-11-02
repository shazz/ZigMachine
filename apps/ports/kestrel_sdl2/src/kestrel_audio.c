/* See kestrel_audio.h. Integers only past dt's own conversion: ZIGGY has no f64, and this runs a frame. */
#include <string.h>
#include "kestrel_audio.h"

__attribute__((import_module("env"), import_name("hostMicros"))) extern uint32_t hostMicros(void);
__attribute__((import_module("env"), import_name("hostAudioStreamStart"))) extern void hostAudioStreamStart(float rate);
__attribute__((import_module("env"), import_name("hostAudioFeed"))) extern void hostAudioFeed(const void *p, int len);

#define US 1000000u
/* A block a feed: the browser keeps the last 32 feeds to pre-fill the ring once sound is on
 * (docs/sealed-loader.js recentChunks, "32 blocks = 16 KiB = half the ring"), so a feed stays <= 512. */
#define BLOCK 512

static uint32_t last_us;   /* hostMicros() at the last frame, 0 = no clock yet */
static uint64_t owed;      /* rate x microseconds not yet a whole sample */
static int started;
static int16_t mixbuf[BLOCK * 2];
static int8_t outbuf[BLOCK];

uint32_t kestrel_frame_us(float elapsed_ms, uint32_t cap_ms)
{
    uint32_t now = hostMicros(), us;
    if (now != 0 && last_us != 0) us = now - last_us; /* wraps every ~71 min: unsigned difference */
    else us = elapsed_ms > 0.0f ? (uint32_t)(elapsed_ms < 1e6f ? elapsed_ms * 1000.0f : 1e9f) : 0u;
    last_us = now;
    return us > cap_ms * 1000u ? cap_ms * 1000u : us;
}

static void feed_silence(uint32_t n)
{
    memset(outbuf, 0, sizeof outbuf);
    for (; n > 0; n -= n < BLOCK ? n : BLOCK) hostAudioFeed(outbuf, (int)(n < BLOCK ? n : BLOCK));
}

void kestrel_audio_pump(uint32_t us, uint32_t rate, uint32_t lead_ms, kestrel_mix_fn mix, void *ctx)
{
    if (rate == 0) return;
    if (!started) {
        hostAudioStreamStart((float)rate);
        feed_silence(rate * lead_ms / 1000u);
        started = 1;
    }
    owed += (uint64_t)us * rate;
    uint32_t n = (uint32_t)(owed / US);
    owed %= US;
    while (n > 0) {
        int k = (int)(n < BLOCK ? n : BLOCK);
        mix(ctx, mixbuf, k);
        for (int i = 0; i < k; i++) {
            int m = ((int)mixbuf[2 * i] + (int)mixbuf[2 * i + 1]) >> 9; /* (L+R)/2, 16 -> 8 bits */
            outbuf[i] = (int8_t)(m > 127 ? 127 : m < -128 ? -128 : m);
        }
        hostAudioFeed(outbuf, k);
        n -= (uint32_t)k;
    }
}
