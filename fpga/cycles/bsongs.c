/* The backend's song store (haudio.h audio_song) where the songs are linked into the
 * image (tools/song_pack.py's zm_songs): the cart CPU's firmware, and the sound CPU's
 * bench (cycles/sound/). */
#include <stdio.h>
#include <string.h>

#include "baudio.h"
#include "haudio.h"

int32_t audio_song(const char* name, uint8_t* dst, uint32_t cap) {
    for (const zm_song* s = zm_songs; s->name; s++) {
        if (strcmp(s->name, name) != 0) continue;
        uint32_t n = s->len < cap ? s->len : cap;
        memcpy(dst, s->data, n);
        return (int32_t)n;
    }
    printf("ZM SONG MISSING %s\n", name);
    return -1;
}
