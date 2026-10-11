/* One SNDH, no cart: the audio core's writes, a digest a frame (host/audio_soft.c
 * ZM_AUDIO_DIGEST), for tests/test_sndh_native.py to hold a native replay
 * (libs/zig/players/digi.zig) to Musashi, write for write, over a whole tune.
 *
 *   sndh_oracle <song> <tune> <frames> [<call frame> <d0>]
 *     a zg.sndhCall(song, d0) before that frame's render, as a screen's would be
 *   ZM_SNDH_MUSASHI=1   every tune on Musashi (audioSndhNativeEnable(0)): the reference
 *   ZM_SNDH_MUTANT=n    a known-wrong native replay (audioSndhNativeMutant), for the test
 *   ZM_SNDH_MODES=f:m,f:m...  zg.requestSndhMode(m) before frame f's render; each prints
 *                       "ZM SNDH mode f asked m got g" (g = 0: refused; 1 for 2/3: no native driver)
 *   ZM_SNDH_MODE_AT=s:m  zg.requestSndhMode(m) at sample s from the song's first write (its "L"
 *                       line): where the board applied it (tools/bard_fx_run.py), mid-frame
 *
 * Frames are 735 samples (60 Hz), rendered whole, as the board renders them. */
#include <stdio.h>
#include <stdlib.h>

#include "haudio.h"
#include "haudio_soft.h"
#include "wasm-rt-impl.h"

const host_song_bridge host_songs = {0}; /* host.h wants one; no cart polls it */

/* ZM_SNDH_MODES: the next "f:m" at or after `*at`, applied when its frame comes. */
static void modes(const char** at, int f) {
    while (*at && **at) {
        int frame = 0, mode = 0, used = 0;
        if (sscanf(*at, "%d:%d%n", &frame, &mode, &used) != 2 || frame > f) return;
        *at += used + (( *at)[used] == ',');
        uint32_t got = w2c_audio_audioSndhMode(&g_aud.player, (uint32_t)mode);
        printf("ZM SNDH mode %d asked %d got %u\n", f, mode, (unsigned)got);
    }
}

/* A frame of 735 samples, split at ZM_SNDH_MODE_AT's sample if it falls inside. */
static void render_frame(uint32_t song0) {
    static const char* at;
    static int started;
    if (!started) at = getenv("ZM_SNDH_MODE_AT"), started = 1;
    unsigned long s = 0;
    unsigned mode = 0;
    uint32_t left = 735;
    if (at && sscanf(at, "%lu:%u", &s, &mode) == 2) {
        uint32_t pos = zma_ts() - song0;
        if (s >= pos && s < pos + left) {
            audio_soft_render((uint32_t)s - pos);
            left -= (uint32_t)s - pos;
            uint32_t got = w2c_audio_audioSndhMode(&g_aud.player, mode);
            printf("ZM SNDH mode at %lu asked %u got %u\n", s, mode, (unsigned)got);
            at = NULL;
        }
    }
    audio_soft_render(left);
}

int main(int argc, char** argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: sndh_oracle <song> <tune> <frames> [<call frame> <d0>]\n");
        return 2;
    }
    int frames = atoi(argv[3]);
    int call_at = argc > 5 ? atoi(argv[4]) : -1;
    uint32_t call_d0 = argc > 5 ? (uint32_t)strtoul(argv[5], NULL, 0) : 0;
    wasm_rt_init();
    audio_soft_boot();
    if (getenv("ZM_SNDH_MUSASHI")) w2c_audio_audioSndhNativeEnable(&g_aud.player, 0);
    if (getenv("ZM_SNDH_MUTANT")) w2c_audio_audioSndhNativeMutant(&g_aud.player, (uint32_t)atoi(getenv("ZM_SNDH_MUTANT")));
    audio_play(argv[1], (uint32_t)atoi(argv[2]));
    uint32_t song0 = zma_ts();
    printf("ZM ORACLE native %u\n", (unsigned)w2c_audio_audioSndhNative(&g_aud.player));
    audio_soft_digest(0); /* the load's writes: frame 0 */
    const char* plan = getenv("ZM_SNDH_MODES");
    for (int f = 1; f <= frames; f++) {
        if (f == call_at) audio_sndh_call(argv[1], call_d0);
        modes(&plan, f);
        render_frame(song0);
        audio_soft_digest((uint32_t)f);
    }
    audio_soft_close();
    return 0;
}
