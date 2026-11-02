/* A cart's Paula where the players run (HW 1.14.0, haudio.h FX_PAULA_*): the native host, the
 * board's sound CPU (BARD), or the cart CPU when the players run there. As
 * docs/audio-worklet-sealed.js cartPaula: the claim (demo-audio.wasm audioPaulaClaim stops every
 * player and zeroes chip RAM = song RAM), uploads copied into chip RAM, write batches staged and
 * queued for their samples (apps/zig/demo_audio_paula.zig). While a cart holds the channels,
 * host/audio.c refuses every song, stream and effect (audio_paula_holds). */
#include <stdio.h>
#include <string.h>

#include "haudio.h"

int audio_paula_holds(void) { return audio_live() && w2c_audio_audioPaulaClaimed(&g_aud.player) != 0; }

static void upload(const audio_fx* fx) {
    w2c_audio* p = &g_aud.player;
    uint32_t off = fx->rate, size = w2c_audio_audioPaulaChipSize(p);
    if (!audio_paula_holds() || off > size || fx->len > size - off) return;
    memcpy(g_aud.memory.data + w2c_audio_audioPaulaChipPtr(p) + off, (const void*)fx->pcm, fx->len);
}

/* The batch through the stage, a stage at a time; a write the queue could not take is counted
 * there (audioPaulaDropped). */
static void write_batch(const audio_fx* fx) {
    w2c_audio* p = &g_aud.player;
    if (!audio_paula_holds()) return;
    uint32_t cap = w2c_audio_audioPaulaStageCap(p), at = w2c_audio_audioPaulaStagePtr(p);
    const uint8_t* src = (const uint8_t*)fx->pcm;
    for (uint32_t done = 0; done < fx->len;) {
        uint32_t k = fx->len - done < cap ? fx->len - done : cap;
        memcpy(g_aud.memory.data + at, src + 16u * done, 16u * k);
        w2c_audio_audioPaulaQueue(p, k);
        done += k;
    }
}

int audio_paula_effect(const audio_fx* fx) {
    w2c_audio* p = &g_aud.player;
    switch (fx->op) {
    case FX_PAULA_CLAIM:
        audio_pcm_forget(); /* a sample refilling the ring would write over chip RAM */
        w2c_audio_audioPaulaClaim(p, fx->rate);
        printf("ZM PAULA claimed by the cart, lead %lu\n", (unsigned long)fx->rate);
        return 1;
    case FX_PAULA_UPLOAD: upload(fx); return 1;
    case FX_PAULA_WRITE: write_batch(fx); return 1;
    case FX_PAULA_RELEASE:
        w2c_audio_audioPaulaRelease(p);
        printf("ZM PAULA released\n");
        return 1;
    default: return 0;
    }
}
