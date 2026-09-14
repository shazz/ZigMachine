// ---------------------------------------------------------------------------
// zigmachine_music.h — let a C cart ask the host for a tune, BY NAME.
//
// The same song bridge the Zig scenes use (libs/zig/zigos.zig requestSong /
// requestSongTune, exported by apps/zig/demo_main.zig). Nothing here plays
// music: the SNDH player (Musashi 68000 + sndh_player.zig) lives in
// demo-audio.wasm on the audio thread. This cart only leaves a request in
// shared memory; docs/sealed-loader.js polls four exports every frame, fetches
// docs/music/<name>, and the file's extension picks the player
// (.sndh / .mod / .ymraw / .raw). Nothing sounds until the user turns sound on;
// the request waits until then.
//
//     #include "../zigmachine_music.h"
//     void boot(void) { zm_request_song("sos.sndh"); ... }
//
// Include it from exactly ONE .c file per cart: it DEFINES the four exports
// (pollSongRequest, songNamePtr, songNameLen, songTune), and a cart is one
// wasm module.
// ---------------------------------------------------------------------------
#ifndef ZIGMACHINE_MUSIC_H
#define ZIGMACHINE_MUSIC_H

// Same capacity as zigos.zig's g_song_name. A longer name is REFUSED rather than
// truncated: a cut-off filename would fetch the wrong file, or none, silently.
#define ZM_SONG_NAME_MAX 64
// audioSndhPlay takes a u8, so a larger subtune cannot reach the player.
#define ZM_SONG_TUNE_MAX 255

static char zm_song_name[ZM_SONG_NAME_MAX];
static unsigned zm_song_len = 0;
static unsigned zm_song_tune = 0;
static unsigned zm_song_pending = 0;

// Request subtune `tune` of `name` (a file under docs/music/). Subtunes count
// from 1; 0 means "the image's own default". Only an SNDH has subtunes.
// A tune the file does not hold falls back to its default, inside the player.
// Returns 1 when the request was queued, 0 when refused (null/empty/too-long
// name, or tune > 255). A later request replaces a pending one.
static inline int zm_request_song_tune(const char *name, unsigned tune) {
    if (!name || tune > ZM_SONG_TUNE_MAX) return 0;
    unsigned n = 0;
    while (name[n]) {
        if (n == ZM_SONG_NAME_MAX) return 0;
        n++;
    }
    if (n == 0) return 0;
    for (unsigned i = 0; i < n; i++) zm_song_name[i] = name[i];
    zm_song_len = n;
    zm_song_tune = tune;
    zm_song_pending = 1;
    return 1;
}

// Request `name` at its default subtune.
static inline int zm_request_song(const char *name) {
    return zm_request_song_tune(name, 0);
}

// Stop whatever is playing: "none" is the host's reserved stop name.
static inline int zm_stop_song(void) {
    return zm_request_song("none");
}

// --- the exports the host polls (sealed-loader.js, once per frame) ---------
// 1 = a new request is pending; reading it clears it, so each request plays once.
__attribute__((export_name("pollSongRequest")))
unsigned pollSongRequest(void) {
    unsigned p = zm_song_pending;
    zm_song_pending = 0;
    return p;
}
__attribute__((export_name("songNamePtr")))
const char *songNamePtr(void) { return zm_song_name; }
__attribute__((export_name("songNameLen")))
unsigned songNameLen(void) { return zm_song_len; }
__attribute__((export_name("songTune")))
unsigned songTune(void) { return zm_song_tune; }

#endif
