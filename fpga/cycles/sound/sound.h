/* The sound CPU's board layer (cycles/sound/sboard.c). */
#ifndef ZM_SOUND_H
#define ZM_SOUND_H

/* The end: S_DONE = code + 1 for the cart CPU, which ends the sim; then a spin. */
__attribute__((noreturn)) void sound_finish(int code);

#endif
