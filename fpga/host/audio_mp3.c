/* The MP3 stream where the players run (BARD, the native host_audio, ZIGGY with ZM_AUDIO=1): a cart's
 * zg.mp3Ctl / mp3Feed, carried as effects (host/audio_bridge.c audio_mp3_*), applied as the worklet's
 * "mp3Ctl" / "mp3Feed" messages (docs/audio-worklet-sealed.js): a feed's bytes are copied from the
 * cart's memory into the player's staging, a staging's worth at a time, then appended to its ring
 * (libs/zig/players/mp3.zig). And zg.mp3Status where the players are this side's. */
#include <string.h>

#include "haudio.h"

int audio_mp3_effect(const audio_fx* fx) {
    w2c_audio* p = &g_aud.player;
    if (fx->op == FX_MP3_CTL) {
        w2c_audio_audioMp3Ctl(p, fx->a, fx->rate);
        return 1;
    }
    if (fx->op != FX_MP3_FEED) return 0;
    const uint8_t* src = (const uint8_t*)fx->pcm;
    uint32_t at = w2c_audio_audioMp3FeedPtr(p), max = w2c_audio_audioMp3FeedMax(p);
    for (uint32_t done = 0; done < fx->len;) {
        uint32_t n = fx->len - done < max ? fx->len - done : max;
        memcpy(g_aud.memory.data + at, src + done, n);
        w2c_audio_audioMp3Feed(p, n);
        done += n;
    }
    return 1;
}

/* Where the players are this side's (the board's cart CPU reads BARD's words: cycles/bsound.c). */
uint32_t audio_mp3_status(uint32_t which) {
    return audio_live() ? w2c_audio_audioMp3Status(&g_aud.player, which) : 0u;
}
