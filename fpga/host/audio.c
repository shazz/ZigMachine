/* The audio side's boot, its song starts and the render loop (haudio.h), shared by
 * the native host, the board firmware and the sound CPU's (cycles/sound/). The
 * starts are the worklet's load messages (docs/audio-worklet-sealed.js) minus the
 * fetch: a song is staged at once, so it starts on the frame that asked for it; the
 * effects (audio_effects) are the worklet's sfx / sndhMode messages. The cart's side of
 * the bridge, which calls them, is host/audio_bridge.c. */
#include <stdio.h>
#include <string.h>

#include "audio_names.h"
#include "haudio.h"

#define AUDIO_PAGES 48u   /* machine/sdk/audio.zig AUDIO_PAGES: 3 MiB, initial == maximum */
#define MAX_FRAMES 4096u  /* machine/sdk/audio.zig MAX_FRAMES: the most audioRender takes */
#define NAME_MAX 64u      /* libs/zig/zigos.zig g_song_name */

struct w2c_aud g_aud;
static char g_resident[NAME_MAX + 1]; /* the SNDH playing, for zg.sndhCall; "" when none */

void audio_backend_boot(void);
void audio_backend_start(void);
void audio_backend_native(uint32_t native); /* the player audioSndhNative() names: the board's lead */

int audio_live(void) { return g_aud.memory.data != NULL; }

#ifdef ZM_SND
/* BARD: the module's memory at a measured offset in its 4 KiB page (host/mem_place.h). */
#include "mem_place.h"
#ifndef BARD_MEM_SET
#define BARD_MEM_SET 0x640u
#endif
static void audio_memory(wasm_rt_memory_t* m) { zm_mem_place(m, AUDIO_PAGES, BARD_MEM_SET); }
#else
static void audio_memory(wasm_rt_memory_t* m) {
    wasm_rt_allocate_memory(m, AUDIO_PAGES, AUDIO_PAGES, false, WASM_DEFAULT_PAGE_SIZE);
}
#endif

void audio_boot(void) {
    audio_memory(&g_aud.memory);
    audio_backend_boot(); /* the soft chips first: their data segments are the low MiB */
    wasm2c_audio_instantiate(&g_aud.player, &g_aud);
    audio_backend_start(); /* the first write is next: the backend sets the stamp */
    w2c_audio_audioInit(&g_aud.player);
    w2c_audio_audioReset(&g_aud.player); /* the host's "reset" on every cart instantiation */
}

static int ends_with(const char* s, const char* tail) {
    size_t n = strlen(s), m = strlen(tail);
    return n >= m && strcmp(s + n - m, tail) == 0;
}

/* The file into song RAM; its length, or -1 (no such file: the fetch failed). */
static int32_t stage(const char* name) {
    w2c_audio* p = &g_aud.player;
    uint8_t* song = g_aud.memory.data + w2c_audio_audioSongPtr(p);
    audio_pcm_forget(); /* the song takes song RAM, the stream ring with it */
    return audio_song(name, song, w2c_audio_audioSongCapacity(p));
}

/* worklet "loadSndh" on the `len` bytes staged: INIT with subtune `tune`, or with d0 exactly (raw). */
static void load_sndh(const char* name, int32_t len, uint32_t arg, int raw) {
    w2c_audio* p = &g_aud.player;
    g_resident[0] = 0;
    if (len < 0 || !w2c_audio_audioLoadSndh(p, (uint32_t)len)) return;
    uint32_t native = w2c_audio_audioSndhNative(p);
    audio_backend_native(native);
    if (native < sizeof NATIVE / sizeof NATIVE[0] && NATIVE[native]) printf("ZM SNDH %s %s\n", NATIVE[native], name);
    audio_song_loaded(name); /* a load is long (depack, 1 MiB zeroed): the stamp may need to move on */
    if (raw) w2c_audio_audioSndhPlayRaw(p, arg);
    else w2c_audio_audioSndhPlay(p, arg);
    strncpy(g_resident, name, NAME_MAX);
}

static void play_sndh(const char* name, uint32_t arg, int raw) { load_sndh(name, stage(name), arg, raw); }

/* An Atari SAP (libs/zig/players/sap_player.zig) on the `len` bytes staged: subsong `tune`
 * (1-based, 0 = DEFSONG). A refusal or a stop is said, with audioSapStatus's reason. */
static void load_sap(const char* name, int32_t len, uint32_t tune) {
    w2c_audio* p = &g_aud.player;
    if (len < 0) return;
    if (!w2c_audio_audioLoadSap(p, (uint32_t)len)) {
        uint32_t why = w2c_audio_audioSapStatus(p) & 0xFFu;
        printf("ZM SAP refused %s: %s\n", name, why < 8 ? SAP_REFUSED[why] : "?");
        return;
    }
    audio_backend_native(0);
    audio_song_loaded(name);
    w2c_audio_audioSapPlay(p, tune);
    uint32_t st = w2c_audio_audioSapStatus(p);
    if (st) printf("ZM SAP stopped %s: cpu %u, opcode %02x at %04x\n", name, (unsigned)(st >> 8 & 0xFF),
                   (unsigned)(st >> 16 & 0xFF), (unsigned)w2c_audio_audioSapStopPc(p));
}

/* zg.requestSongBytes (FX_SONG): the cart's image staged as a fetched file is, then loaded as the
 * worklet's loadSndh / loadSap. No named image: zg.sndhCall cannot reach it (g_resident ""). */
static void song_bytes(const audio_fx* fx) {
    w2c_audio* p = &g_aud.player;
    if (fx->a != FX_SONG_SNDH && fx->a != FX_SONG_SAP) {
        printf("ZM FX requestSongBytes: unknown kind %u\n", (unsigned)fx->a);
        return;
    }
    const char* name = fx->a == FX_SONG_SNDH ? "bytes.sndh" : "bytes.sap"; /* the extension: bsndinfo.h */
    audio_backend_song(name, fx->b);
    audio_pcm_forget(); /* the song takes song RAM, the stream ring with it */
    uint32_t cap = w2c_audio_audioSongCapacity(p), n = fx->len < cap ? fx->len : cap;
    memcpy(g_aud.memory.data + w2c_audio_audioSongPtr(p), (const void*)fx->pcm, n);
    if (fx->a == FX_SONG_SNDH) load_sndh(name, (int32_t)n, fx->b, 0);
    else load_sap(name, (int32_t)n, fx->b);
    g_resident[0] = 0;
    printf("ZM SONG bytes %s %lu mode %u\n", name, (unsigned long)n, (unsigned)w2c_audio_audioMode(p));
}

/* playSongByName: the extension picks the player; "none" stops everything. */
void audio_play(const char* name, uint32_t tune) {
    w2c_audio* p = &g_aud.player;
    audio_backend_song(name, tune);
    if (strcmp(name, "none") == 0) {
        g_resident[0] = 0;
        audio_pcm_forget();
        w2c_audio_audioReset(p);
        return;
    }
    if (!name[0] || strstr(name, "..") || name[0] == '/') return;
    if (ends_with(name, ".sndh")) {
        play_sndh(name, tune, 0);
        return;
    }
    g_resident[0] = 0;
    audio_backend_native(0);
    int32_t len = stage(name);
    if (len < 0) return;
    audio_song_loaded(name);
    if (ends_with(name, ".mod") && w2c_audio_audioLoadMod(p, (uint32_t)len)) {
        if (tune) w2c_audio_audioModPlayBpm(p, tune); /* a MOD's tune field is its start BPM */
        else w2c_audio_audioModPlay(p);
    } else if (ends_with(name, ".xm") && w2c_audio_audioLoadXm(p, (uint32_t)len)) {
        w2c_audio_audioXmPlay(p, tune); /* an XM's tune field is its start BPM too (0 = the song's own) */
    } else if (ends_with(name, ".ymraw") && w2c_audio_audioLoadYm(p, (uint32_t)len)) {
        w2c_audio_audioYmPlay(p);
    } else if (ends_with(name, ".sap")) {
        load_sap(name, stage(name), tune); /* staged again, as it always was: the same writes and stamps */
    } else if (ends_with(name, ".raw")) {
        w2c_audio_audioPlayRaw(p, (uint32_t)len, 12517.0f, 0);
    }
}

/* One zg.sndhCall: INIT with d0 on the SNDH playing if it is `name`, else load `name`
 * and make d0 its first INIT (the image is not the one playing). */
void audio_sndh_call(const char* name, uint32_t d0) {
    if (strcmp(name, g_resident) == 0) {
        w2c_audio_audioSndhCall(&g_aud.player, d0);
        return;
    }
    audio_backend_song(name, d0);
    play_sndh(name, d0, 1);
}

/* worklet "sfxPlay": the PCM into the effect buffer (0 while no MOD plays: an SNDH's RAM is
 * there), then onto the MOD's quiet channel. */
static int sfx_play(const audio_fx* fx) {
    w2c_audio* p = &g_aud.player;
    uint32_t at = w2c_audio_audioSfxBufPtr(p), cap = w2c_audio_audioSfxBufCapacity(p);
    uint32_t len = at ? (fx->len < cap ? fx->len : cap) : 0;
    if (len) memcpy(g_aud.memory.data + at, (const void*)fx->pcm, len);
    return (int)w2c_audio_audioSfxPlay(p, len, fx->rate, fx->a ? 1u : 0u);
}

/* One effect, as the worklet's message of the same name; a refusal is said, as the console's. */
static void effect(const audio_fx* fx) {
    w2c_audio* p = &g_aud.player;
    const char* missed = NULL;
    if (audio_pcm_effect(fx)) {
        /* the stream ring: host/audio_pcm.c */
    } else if (fx->op == FX_PLAY) {
        if (!sfx_play(fx)) missed = "sfxPlay";
    } else if (fx->op == FX_STOP) {
        w2c_audio_audioSfxStop(p, fx->a ? 1u : 0u);
    } else if (fx->op == FX_YM) {
        if (!w2c_audio_audioSfxYm(p, fx->a, fx->b)) missed = "ymWrite";
    } else if (fx->op == FX_GAIN) {
        if (!w2c_audio_audioModGain(p, fx->len)) missed = "requestModVolume";
    } else if (fx->op == FX_SONG) {
        song_bytes(fx);
    } else if (fx->op == FX_SNDH_MODE) {
        /* The stamp: tools/bard_fx_run.py replays the switch at this sample from the song's start. */
        uint32_t got = w2c_audio_audioSndhMode(p, fx->a);
        printf("ZM SNDH mode asked %u got %u at %lu\n", (unsigned)fx->a, (unsigned)got, (unsigned long)zma_ts());
        if (got) audio_backend_mode(got); /* 0: refused, nothing changed */
    } else {
        printf("ZM FX bad op %u\n", (unsigned)fx->op);
    }
    if (missed) printf("ZM FX %s refused (%u so far)\n", missed, (unsigned)w2c_audio_audioSfxRefused(p));
}

void audio_effects(const audio_fx* fx, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) effect(&fx[i]);
}

void audio_render(uint32_t n) {
    while (n) {
        uint32_t k = n < MAX_FRAMES ? n : MAX_FRAMES;
        uint32_t t = zma_ts();
        zma_set_ts(t);
        audio_pcm_refill(k);
        w2c_audio_audioRender(&g_aud.player, k);
        zma_set_ts(t + k);
        n -= k;
    }
}
