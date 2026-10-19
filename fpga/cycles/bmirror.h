/* The audio-state mirror on the cart CPU (cycles/aud_state.h says what and why): where the
 * cart keeps the fields, and the per-frame write into them.
 *
 * Force-included (cycles/board.mk STREAM_*) into the generated env.c of the monolithic image
 * and sys_env.c of the split one, so tools/host_bridges.py's HOST_AUDIO_MIRROR hook reaches
 * audio_mirror_bind: from host/boot.c right after the cart's instantiation (monolithic), or
 * from the lean cart's instantiate through the system table's hostAudioMirror entry (1.2).
 * Anywhere else the hook is the generated no-op, so the native host and scene_hash.mjs, which
 * play no audio, keep their pictures. */
#ifndef ZM_BMIRROR_H
#define ZM_BMIRROR_H

#include <stdint.h>

#include "aud_state.h"

/* The cart's memory (`size` bytes: it never moves) and its getYmRegsPointer / getAudioModePointer /
 * getSongMsPointer, as offsets in it; 0 for one the cart does not export (a C or Rust cart), and
 * one that falls outside the memory (or a misaligned song_ms) is dropped. */
void audio_mirror_bind(uint8_t* mem, uint64_t size, uint32_t ym, uint32_t mode, uint32_t ms);

/* After the cart's frame: the fields that differ from `s`, written; the others untouched.
 * Returns the number of stores made (the firmware's cost: stores, ~27 cycles each). */
uint32_t audio_mirror_frame(const aud_state* s);

/* Expanded in the generated env.c / sys_env.c, where struct w2c_env is whole. */
#define HOST_AUDIO_MIRROR(e, ym, mode, ms) audio_mirror_bind((e)->memory.data, (e)->memory.size, (ym), (mode), (ms))

/* Only on the board, where the music is heard: a sim's frames are hashed against the browser's
 * scene_hash.mjs, which has no audio (ZM_AUDIO_MIRROR=1 turns it on in a sim). */
#if defined(ZM_BOARD) || defined(ZM_AUDIO_MIRROR)
#define ZM_MIRROR_ON 1
#else
#define ZM_MIRROR_ON 0
#endif

#endif
