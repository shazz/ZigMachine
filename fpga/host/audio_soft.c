/* The native host's audio backend (haudio.h): the machine's own chips
 * (machine-audio.wasm through wasm2c, -n maud) play what the players ask, the
 * reference the RTL is compared with, and every write the board would queue is
 * logged with its sample stamp.
 *
 *   ZM_AUDIO_LOG=<prefix> host_audio <cart> [frames] [every]
 *     <prefix>.w     "L ts writes name" per song started, "W ts addr data" per register write
 *     <prefix>.pcm   the machine's samples: int16 L, R interleaved, floor(x * 32768)
 *                    clamped (zm_audio_mix's conversion)
 *   ZM_MUSIC_DIR     where the songs are (default HOST_MUSIC_DIR, the repo's docs/music)
 *   ZM_AUDIO_SPLIT   render each frame in pieces of this many samples (default: one piece)
 *
 * The frame is 1/60 s, so 735 samples a frame, rendered after the cart's frame
 * and its song requests: docs/sealed-loader.js's order. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "haudio.h"
#include "haudio_soft.h"
#include "maud.h"

#ifndef HOST_MUSIC_DIR
#define HOST_MUSIC_DIR "docs/music"
#endif
#define FRAME_SAMPLES 735u

w2c_maud g_maud;
static FILE *g_w, *g_pcm;

void audio_backend_boot(void) { wasm2c_maud_instantiate(&g_maud, &g_aud); }
void audio_backend_start(void) {}
static uint32_t g_writes;

void zma_put(uint32_t addr, uint32_t data) {
    g_writes++;
    if (g_w) fprintf(g_w, "W %u %03x %08x\n", (unsigned)zma_ts(), (unsigned)addr, (unsigned)data);
}

void audio_song_loaded(const char* name) {
    if (g_w) fprintf(g_w, "L %u %u %s\n", (unsigned)zma_ts(), (unsigned)g_writes, name);
}

int32_t audio_song(const char* name, uint8_t* dst, uint32_t cap) {
    const char* dir = getenv("ZM_MUSIC_DIR");
    char path[512];
    snprintf(path, sizeof path, "%s/%s", dir ? dir : HOST_MUSIC_DIR, name);
    FILE* f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "host_audio: no song %s\n", path);
        return -1;
    }
    size_t n = fread(dst, 1, cap, f);
    fclose(f);
    return (int32_t)n;
}

static FILE* open_log(const char* prefix, const char* ext, const char* mode) {
    char path[512];
    snprintf(path, sizeof path, "%s.%s", prefix, ext);
    FILE* f = fopen(path, mode);
    if (!f) {
        fprintf(stderr, "host_audio: cannot write %s\n", path);
        exit(1);
    }
    return f;
}

void audio_soft_boot(void) {
    const char* prefix = getenv("ZM_AUDIO_LOG");
    if (prefix) {
        g_w = open_log(prefix, "w", "w");
        g_pcm = open_log(prefix, "pcm", "wb");
    }
    audio_boot();
}

static int16_t to_s16(float x) {
    float v = floorf(x * 32768.0f);
    return (int16_t)(v >= 32767.0f ? 32767 : v <= -32768.0f ? -32768 : v);
}

static void dump(uint32_t n) {
    const float* l = (const float*)(g_aud.memory.data + w2c_maud_audioLeftPtr(&g_maud));
    const float* r = (const float*)(g_aud.memory.data + w2c_maud_audioRightPtr(&g_maud));
    for (uint32_t i = 0; i < n && g_pcm; i++) {
        int16_t s[2] = {to_s16(l[i]), to_s16(r[i])};
        fwrite(s, sizeof s, 1, g_pcm);
    }
}

/* ZM_AUDIO_SPLIT=k renders the frame in pieces of k samples: a player whose writes
 * change with the pieces would not play on the board as here (the board renders
 * whatever the sound's lead asks for), so this is how that is checked. */
void audio_soft_frame(struct w2c_env* e) {
    static uint32_t split;
    if (!split) split = getenv("ZM_AUDIO_SPLIT") ? (uint32_t)atoi(getenv("ZM_AUDIO_SPLIT")) : FRAME_SAMPLES;
    audio_bridge(e);
    for (uint32_t done = 0; done < FRAME_SAMPLES; done += split) {
        uint32_t n = FRAME_SAMPLES - done < split ? FRAME_SAMPLES - done : split;
        audio_render(n);
        dump(n);
    }
}

void audio_soft_close(void) {
    if (g_w) fclose(g_w);
    if (g_pcm) fclose(g_pcm);
    g_w = g_pcm = NULL;
}
