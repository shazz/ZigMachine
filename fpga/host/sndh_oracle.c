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
 *   ZM_SNDH_RAM=<file>  the 68000's RAM after the last frame (a rip's starting point)
 *   ZM_SNDH_TIMERS=1    "ZM ORACLE subtunes n", then "ZM TIMERS f a b c d" whenever the MFP timers'
 *                       rates (Hz) change: how many interrupts a frame the tune asks of BARD
 *                       (tools/bard_load_survey.py); `make sndh-survey`'s build also prints
 *                       "ZM COUNT f insns calls" a frame: Musashi's 68000 instructions and calls
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

/* The 68000 instructions Musashi ran, and the calls into the tune (play, interrupts) that reached
 * the return stub at zm_survey_ret: counted only in `make sndh-survey`'s players (weak: absent here). */
extern unsigned long long zm_survey_insns __attribute__((weak)), zm_survey_calls __attribute__((weak));
extern unsigned zm_survey_ret __attribute__((weak));

/* ZM_SNDH_TIMERS: the four timers' rates, printed when they change. */
static void timers(int f) {
    static uint32_t last[4] = {~0u, ~0u, ~0u, ~0u};
    int changed = 0;
    uint32_t r[4];
    for (uint32_t t = 0; t < 4; t++) {
        r[t] = w2c_audio_audioSndhTimerRate(&g_aud.player, t);
        changed |= r[t] != last[t];
        last[t] = r[t];
    }
    if (changed) printf("ZM TIMERS %d %u %u %u %u\n", f, (unsigned)r[0], (unsigned)r[1], (unsigned)r[2], (unsigned)r[3]);
}

/* The survey's counters: "ZM COUNT f insns calls", frame f's 68000 instructions and calls (0: none). */
static void counts(int f) {
    static unsigned long long insns, calls;
    if (f > 0) printf("ZM COUNT %d %llu %llu\n", f, zm_survey_insns - insns, zm_survey_calls - calls);
    insns = zm_survey_insns, calls = zm_survey_calls;
}

/* ZM_SNDH_TIMERS: each running MFP timer's handler (at the vector VR=$40 puts it) and its first
 * 64 bytes, "ZM HANDLER t addr hex": how tunes that share a replay are found. */
static void handlers(void) {
    const uint8_t* ram = g_aud.memory.data + w2c_audio_audioSongPtr(&g_aud.player);
    static const uint32_t slot[4] = {0x134, 0x120, 0x114, 0x110};
    uint32_t cap = w2c_audio_audioSongCapacity(&g_aud.player);
    for (int t = 0; t < 4; t++) {
        const uint8_t* v = ram + slot[t];
        uint32_t at = (uint32_t)v[0] << 24 | (uint32_t)v[1] << 16 | (uint32_t)v[2] << 8 | v[3];
        if (!w2c_audio_audioSndhTimerRate(&g_aud.player, (uint32_t)t) || at == 0 || at + 64 > cap) continue;
        printf("ZM HANDLER %d %06x ", t, (unsigned)at);
        for (int i = 0; i < 64; i++) printf("%02x", ram[at + i]);
        printf("\n");
    }
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
    if (&zm_survey_ret) zm_survey_ret = w2c_audio_audioSongCapacity(&g_aud.player) - 0x100; /* RETURN_PC */
    audio_play(argv[1], (uint32_t)atoi(argv[2]));
    uint32_t song0 = zma_ts();
    printf("ZM ORACLE native %u\n", (unsigned)w2c_audio_audioSndhNative(&g_aud.player));
    audio_soft_digest(0); /* the load's writes: frame 0 */
    const char* plan = getenv("ZM_SNDH_MODES");
    int trace = getenv("ZM_SNDH_TIMERS") != NULL;
    if (trace) printf("ZM ORACLE subtunes %u\n", (unsigned)w2c_audio_audioSndhSubtunes(&g_aud.player));
    if (trace && &zm_survey_insns) counts(0); /* the load's are not a frame's */
    for (int f = 1; f <= frames; f++) {
        if (f == call_at) audio_sndh_call(argv[1], call_d0);
        modes(&plan, f);
        render_frame(song0);
        audio_soft_digest((uint32_t)f);
        if (trace) timers(f);
        if (trace && &zm_survey_insns) counts(f);
    }
    if (trace) handlers();
    if (getenv("ZM_SNDH_RAM")) { /* the 68000's RAM after the last frame, for a static rip */
        FILE* f = fopen(getenv("ZM_SNDH_RAM"), "wb");
        if (f) fwrite(g_aud.memory.data + w2c_audio_audioSongPtr(&g_aud.player), 1,
                      w2c_audio_audioSongCapacity(&g_aud.player), f), fclose(f);
    }
    audio_soft_close();
    return 0;
}
