/* The native host's audio (host/audio_soft.c): built into `host_audio` only
 * (cycles/audio.mk), the oracle for the board's audio core. */
#ifndef ZM_HAUDIO_SOFT_H
#define ZM_HAUDIO_SOFT_H

#include "host.h"

void audio_soft_boot(void);
void audio_soft_frame(struct w2c_env* e);
void audio_soft_close(void);

#endif
