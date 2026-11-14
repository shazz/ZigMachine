/* Where the players' scopes go on the board (host/audio_scope.h): the cart's zigos.scopes. On BARD
 * (ZM_SND) the address comes in C2S word C_SCOPES (cycles/snd_mailbox.h, written by cycles/bsound.c);
 * with the players on the cart CPU it is the mirror's own (cycles/bmirror.c). Followed before each
 * render, rebound only when it changes (a new target starts from zeroed rings, as the cart's statics). */
#ifndef ZM_BSCOPE_H
#define ZM_BSCOPE_H

#include <stdint.h>

#include "audio_scope.h"

#ifdef ZM_SND
#include <stdio.h>

#include "snd_mailbox.h"
/* An address BARD may write: 4-aligned, past its own image, the 2 KiB under its RAM (the cart's data). */
static inline uint32_t bscope_ok(uint32_t at) {
    return !(at & 3u) && at >= SND_BASE + SND_IMAGE_MAX && at <= SND_CART_END - ZSC_BYTES ? at : 0u;
}
static inline uint32_t bscope_wanted(void) {
    static uint32_t refused;
    uint32_t raw = SND_REG(SND_C2S + C_SCOPES), at = bscope_ok(raw);
    if (raw && !at && raw != refused) printf("ZM SCOPES refused %08lx\n", (unsigned long)(refused = raw)); /* loud, once */
    return at;
}
#else
#include "bmirror.h"
static inline uint32_t bscope_wanted(void) { return ZM_MIRROR_ON ? audio_mirror_scopes_at() : 0u; }
#endif

static inline void bscope_follow(void) {
    static uint32_t bound;
    uint32_t at = bscope_wanted();
    if (at == bound) return;
    bound = at;
    zsc_target((volatile uint32_t*)(uintptr_t)at);
}

#endif
