/* The machine's audio side for the native host and the board firmware: the
 * open players (demo-audio.wasm: MOD, YM dump, SNDH = the tune's own 68000 code
 * on Musashi) through wasm2c, in their own 3 MiB memory, driven the way
 * docs/audio-worklet-sealed.js drives them, and fed from the cart's song bridge
 * (zg.requestSong, zg.sndhCall) the way docs/sealed-loader.js forwards it.
 *
 * The players drive the chips through the `machine*` imports (host/audio_imports.c),
 * which become the audio core's register writes (host/audio_regs.h), each
 * stamped with the sample it lands before. Where they go is the backend's:
 *   host/audio_soft.c  native: also the machine's own chips (machine-audio.wasm), and logs
 *   cycles/baudio.c    the board: the RTL's timestamped write queue */
#ifndef ZM_HOST_AUDIO_H
#define ZM_HOST_AUDIO_H

#include <stdint.h>

#include "aplayer.h" /* wasm2c: demo-audio.wasm -n audio, imports renamed env -> aud */
#include "host.h"

struct w2c_aud {
    wasm_rt_memory_t memory; /* the players' memory: AUDIO_PAGES, song RAM at SONG_BASE */
    w2c_audio player;
};

extern struct w2c_aud g_aud;

/* The sample clock of the write stream: `zma_ts()` is the sample the next write
 * lands before (host/audio_imports.c). audio_render advances it. */
uint32_t zma_ts(void);
void zma_set_ts(uint32_t t);

/* Instantiate the players and reset them (audioInit + audioReset, as the
 * worklet and the host's per-cart "reset" message do). */
void audio_boot(void);

/* After the cart's frame: its song request (a LOAD of a file by name), then its
 * zg.sndhCall's, in the cart's order. Returns 1 when a song was (re)started. */
int audio_bridge(struct w2c_env* e);

/* playSongByName: start the file `name` (its extension picks the player; "none"
 * stops everything); `tune` is an SNDH's subtune or a MOD's start BPM. */
void audio_play(const char* name, uint32_t tune);

/* zg.sndhCall: INIT with `d0` on the SNDH `name` if it is the one playing, else load
 * it and make d0 its first INIT. */
void audio_sndh_call(const char* name, uint32_t d0);

/* zg.sfxPlay / sfxStop / ymWrite / requestModVolume / requestSndhMode: one entry of the cart's
 * effects queue (libs/zig/sfx_queue.zig Entry), as docs/sealed-loader.js postSfx reads it. A
 * play's PCM is `pcm`, already a pointer this side can read (the cart's memory, bounds-checked). */
enum { FX_PLAY = 1, FX_STOP = 2, FX_YM = 3, FX_GAIN = 4, FX_SNDH_MODE = 5 };
typedef struct {
    uint8_t op, a, b; /* sfx_queue.zig: op; a (loop / loop only / register / mode); b (the YM value) */
    uintptr_t pcm;    /* play: the bytes */
    uint32_t len;     /* play: their length; gain: the MOD's gain x 65536 */
    uint32_t rate;    /* play: Hz */
} audio_fx;

/* The frame's effects, in the cart's order, applied as docs/audio-worklet-sealed.js applies
 * each message: after the frame's song request and sndhCalls (audio_bridge's order). */
void audio_effects(const audio_fx* fx, uint32_t n);

/* Render `n` samples (any n: chunks of MAX_FRAMES), advancing zma_ts() by n. */
void audio_render(uint32_t n);

/* The backend's song store: copy the file `name` (a path under docs/music/) to
 * `dst` (at most `cap` bytes) and return its length, or -1 if there is none. */
int32_t audio_song(const char* name, uint8_t* dst, uint32_t cap);

/* The backend's hook, once per song (re)start: the file `name` is staged and loaded,
 * its player is about to start (its first write is next, at zma_ts()). The board
 * moves the stamp on if the load took it past the sound's lead; both log
 * "ts writes-so-far name", the anchor tools/audio_sim_compare.py aligns on. */
void audio_song_loaded(const char* name);

#endif
