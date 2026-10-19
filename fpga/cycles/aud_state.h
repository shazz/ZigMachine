/* The audio state a cart's ZigOS mirrors (libs/zig/zigos.zig ym_regs, audio_mode, song_ms):
 * what docs/sealed-loader.js writes into the cart from the worklet's "audioState" message.
 * D-BUG's scroller and logo move on the tune's clock (song_ms), music_debug's oscillograph
 * reads the mode and the YM registers, and the VU meters of gen4_3615, swedish_newyear and
 * union_deltaforce read the registers. The board's firmware must write the same fields, or
 * those carts sit still (it never did, until the sys table's 1.2).
 *
 * Who knows the state: the CPU that runs the players. With BARD (ZM_SND) that is the sound
 * CPU, so it publishes the state in its S2C bank (soc/zm_sound_regs.py: LUTRAM, read by the
 * cart CPU past its D-cache, so no invalidate and no DDR store on either side), words
 * S_AS..S_AS+AS_WORDS-1 of cycles/snd_mailbox.h's S2C, each written only when it changed.
 * ZIGGY (cycles/bsound.c) reads it after the cart's frame and cycles/bmirror.c writes into
 * the cart only the bytes that differ. With the players on ZIGGY (ZM_AUDIO=1, cycles/baudio.c)
 * the state is read straight off them.
 *
 * Header-only: the sound image and the cart CPU's firmware both include it, and
 * tests/test_audio_mirror.py compiles it for the host over an array. */
#ifndef ZM_AUD_STATE_H
#define ZM_AUD_STATE_H

#include <stdint.h>
#include <string.h>

/* The S2C words (after S_DONE, cycles/snd_mailbox.h). MAGIC is written last at BARD's boot:
 * a reader that sees it sees a cleared block, and an older sound image (no block) never has it. */
enum { S_AS = 12, AS_MAGIC_W = 0, AS_MODE_W = 1, AS_MS_W = 2, AS_YM_W = 3, AS_WORDS = 7 };
#define AS_MAGIC 0x31534d5au /* 'ZMS1': version 1 of this block */
#define AS_YM_REGS 14u        /* the worklet posts ymRegs.subarray(0, 14) */

typedef struct aud_state {
    uint32_t mode;   /* demo-audio.wasm audioMode(): 0 none, 1 MOD/XM, 2 YM, 3 sample, 4 SNDH, 5 SAP */
    uint32_t ms;     /* audioSndhPositionMs(): ms into the SNDH, 0 when none plays */
    uint8_t ym[16];  /* the YM registers as last written (host/audio_imports.c zma_ym_regs) */
} aud_state;

static inline void aud_state_words(const aud_state* s, uint32_t w[AS_WORDS]) {
    w[AS_MAGIC_W] = AS_MAGIC;
    w[AS_MODE_W] = s->mode;
    w[AS_MS_W] = s->ms;
    memcpy(&w[AS_YM_W], s->ym, 16);
}

/* BARD's boot: the block cleared, then its magic. */
static inline void aud_state_boot(volatile uint32_t* s2c) {
    for (uint32_t i = 1; i < AS_WORDS; i++) s2c[S_AS + i] = 0;
    s2c[S_AS + AS_MAGIC_W] = AS_MAGIC;
}

/* BARD, after a render: each word compared with the bank (a register read, no DDR) and
 * stored only when it changed. Returns the number of words stored. */
static inline uint32_t aud_state_publish(volatile uint32_t* s2c, const aud_state* s) {
    uint32_t w[AS_WORDS], n = 0;
    aud_state_words(s, w);
    for (uint32_t i = AS_MODE_W; i < AS_WORDS; i++) {
        if (s2c[S_AS + i] != w[i]) {
            s2c[S_AS + i] = w[i];
            n++;
        }
    }
    return n;
}

/* ZIGGY: the block, if BARD publishes one (0: an older sound image, or none booted yet). */
static inline int aud_state_read(const volatile uint32_t* s2c, aud_state* s) {
    if (s2c[S_AS + AS_MAGIC_W] != AS_MAGIC) return 0;
    uint32_t w[AS_WORDS];
    for (uint32_t i = 0; i < AS_WORDS; i++) w[i] = s2c[S_AS + i];
    s->mode = w[AS_MODE_W];
    s->ms = w[AS_MS_W];
    memcpy(s->ym, &w[AS_YM_W], 16);
    return 1;
}

#endif
