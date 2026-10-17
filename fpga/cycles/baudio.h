/* The board firmware's audio (cycles/baudio.c): the players on the cart CPU,
 * their chip calls queued to the RTL audio core (soc/zm_audio_soc.py). */
#ifndef ZM_BAUDIO_H
#define ZM_BAUDIO_H

#include <stdint.h>

#include "host.h"

/* The songs linked into the image (tools/song_pack.py), NULL-terminated. */
typedef struct zm_song {
    const char* name; /* the path under docs/music/ the cart asks for */
    const uint8_t* data;
    uint32_t len;
} zm_song;
extern const zm_song zm_songs[];
#ifdef ZM_SPLIT_SYS /* the split system image: the songs are the lean cart's (its header) */
#define zm_songs (zm_cart->song_files)
#endif

struct baudio {
    int on;            /* the bitstream has the core (its ID answered) */
    uint32_t pushed;   /* writes queued */
    uint32_t resyncs;  /* frames that fell behind the sound */
    uint32_t anchors;  /* song loads that took the stamp past the sound's lead */
    uint32_t dropped;  /* volume writes that changed nothing (host/audio_queue.h) */
    uint32_t full;     /* writes that found the queue full and waited for room */
};
extern struct baudio baudio;

void baudio_boot(void);                  /* after host_boot: the players, their reset */
void baudio_frame(struct w2c_env* e);    /* after the cart's frame: songs, then render ahead */
void baudio_pump(uint32_t min);          /* render up to the lead, if `min` samples are due */
void baudio_report(void);                /* the sim's "ZM AUD" line */
void baudio_report_log(void);            /* the sound CPU's console so far (cycles/bsound.c only) */

#endif
