/* ZM_SCOPE_CHECK=1 (the native host_audio and sndh_oracle, host/audio_soft.c): the scopes the
 * players' calls rebuild (host/audio_scope.c, what BARD writes into the cart on the board) held
 * to the machine's own engine (machine-audio.wasm's Channel.scope, what the browser's loader
 * mirrors), word for word, after every render. At the end:
 *
 *   ZM SCOPE renders R diff D live L moved M
 *
 * D: renders where any of the 512 words differed (the first one is printed), L: renders with a
 * non-zero word (the check saw a scope at all), M: renders that changed a word (it moves). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "audio_scope.h"
#include "haudio.h"
#include "haudio_soft.h"
#include "maud.h"

extern w2c_maud g_maud;

static uint32_t g_ring[ZSC_CHANNELS * ZSC_LEN], g_last[ZSC_CHANNELS * ZSC_LEN];
static struct {
    int on;
    uint32_t renders, diff, live, moved;
} g_sc;

void audio_scope_check_boot(void) {
    if (!getenv("ZM_SCOPE_CHECK")) return;
    g_sc.on = 1;
    zsc_target(g_ring);
}

static int same(uint32_t ch, const uint32_t* ref) {
    const uint32_t* got = g_ring + ZSC_LEN * ch;
    for (uint32_t i = 0; i < ZSC_LEN; i++) {
        if (got[i] == ref[i]) continue;
        if (!g_sc.diff)
            printf("ZM SCOPE first diff render %u ch %u [%u] got %08x engine %08x\n", (unsigned)g_sc.renders,
                   (unsigned)ch, (unsigned)i, (unsigned)got[i], (unsigned)ref[i]);
        return 0;
    }
    return 1;
}

void audio_scope_check_render(void) {
    if (!g_sc.on) return;
    int ok = 1, live = 0;
    for (uint32_t ch = 0; ch < ZSC_CHANNELS; ch++)
        ok &= same(ch, (const uint32_t*)(g_aud.memory.data + w2c_maud_audioScopePtr(&g_maud, ch)));
    for (uint32_t i = 0; i < ZSC_CHANNELS * ZSC_LEN; i++) live |= g_ring[i] != 0;
    g_sc.diff += !ok;
    g_sc.live += live;
    g_sc.moved += memcmp(g_ring, g_last, sizeof g_ring) != 0;
    memcpy(g_last, g_ring, sizeof g_ring);
    g_sc.renders++;
}

void audio_scope_check_close(void) {
    if (!g_sc.on) return;
    printf("ZM SCOPE renders %u diff %u live %u moved %u\n", (unsigned)g_sc.renders, (unsigned)g_sc.diff,
           (unsigned)g_sc.live, (unsigned)g_sc.moved);
    g_sc.on = 0;
}
