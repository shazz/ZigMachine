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
/* One bare mailbox command (no song), waited for to its ACK: the BARD queue's open and close
 * (cycles/bsound_bardq.c). cycles/bsound.c only. */
void bsound_command(uint32_t op, uint32_t arg, uint32_t ptr);
/* ...with C_LEN too (BARD jobs' open: cycles/bsound_job.c). */
void bsound_command_len(uint32_t op, uint32_t arg, uint32_t ptr, uint32_t len);

#endif
