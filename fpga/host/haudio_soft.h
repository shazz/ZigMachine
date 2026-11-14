/* The native host's audio (host/audio_soft.c): built into `host_audio` only
 * (cycles/audio.mk), the oracle for the board's audio core. */
#ifndef ZM_HAUDIO_SOFT_H
#define ZM_HAUDIO_SOFT_H

#include "host.h"

void audio_soft_boot(void);
void audio_soft_frame(struct w2c_env* e);
void audio_soft_close(void);
void audio_soft_render(uint32_t n);    /* audio_render, and its samples to ZM_AUDIO_LOG's .pcm */
void audio_soft_digest(uint32_t frame); /* ZM_AUDIO_DIGEST: the frame's line, then a new frame */
/* ZM_SCOPE_CHECK (host/audio_scope_check.c): the rebuilt scopes held to the engine's. */
void audio_scope_check_boot(void);
void audio_scope_check_render(void);
void audio_scope_check_close(void);

#endif
