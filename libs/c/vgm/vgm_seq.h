/* The VGM sequencer (libs/c/vgm/README.md): a VGM 1.00-1.71 command stream for one YM2612 and one
 * SN76489, written from the VGM format specification (vgmrips.net "VGM Specification", v1.71).
 * Time: the file's waits count 44.1 kHz samples; the chips render at `rate` (the YM2612's clock / 288,
 * 26,634 Hz NTSC). The commands due are applied, then the chips render the whole chip samples that
 * have elapsed, so writes inside one chip sample collapse (the last wins, as the chip itself only sees
 * one value a sample).
 * Handled: 0x52/0x53 YM2612, 0x50 PSG, 0x4F Game Gear stereo, 0x61-0x63 / 0x7n waits, 0x66 end + the
 * loop, 0x67 data blocks of type 0 (YM2612 PCM; up to VGM_BANKS of them, one bank as the spec appends
 * them), 0x8n DAC write + wait, 0xE0 PCM seek, 0x90-0x95 DAC stream control (one stream, to the
 * YM2612's DAC). Skipped: every other chip's commands. */
#ifndef ZM_VGM_SEQ_H
#define ZM_VGM_SEQ_H

#include <stdint.h>

#include "../sn76489/sn76489.h"
#include "../ym2612/ym2612.h"

#define VGM_BANKS 16

typedef struct {
    const uint8_t *at[VGM_BANKS]; /* each type-0 block's bytes, in file order */
    uint32_t len[VGM_BANKS], n, total;
} vgm_bank;

typedef struct {
    uint32_t setup, on, step, base, data_start, data_len, pos, freq, acc, mode;
} vgm_stream; /* 0x90-0x95: the DAC fed from the bank at `freq` Hz */

typedef struct {
    const uint8_t *d;
    uint32_t len, pos, start, loop; /* loop: 0 = none */
    uint32_t rate, acc, due;        /* acc: 44.1 kHz samples x rate not yet a whole chip sample */
    uint32_t pcm_pos, loops, ended, unknown, waited; /* waited: a wait since the last loop jump */
    uint32_t has_ym, has_psg;
    vgm_bank bank;
    vgm_stream st;
    ym2612 ym;
    sn76489 psg;
} vgm_seq;

/* 0: ok; else 1 not a VGM, 2 neither chip, 3 truncated. `d` is kept while it plays. Clocks from the
 * header; `div` the YM2612's (1 or 2); the gains: the YM2612's Q8 and one PSG channel's peak. */
int vgm_open(vgm_seq *v, const uint8_t *d, uint32_t len, uint32_t div, int32_t ym_gain, int32_t psg_gain);
/* `n` chip samples, interleaved L R, the file's commands applied at their times; loops forever. */
void vgm_fill(vgm_seq *v, int16_t *lr, uint32_t n);
uint32_t vgm_u32(const uint8_t *p);
/* Benches only: every command up to 44.1 kHz sample t44 applied, nothing rendered (envelopes stand
 * still: notes keyed before t44 are heard from their attack). */
void vgm_seek(vgm_seq *v, uint32_t t44);
/* The bank's byte at `off` (its blocks appended in file order); 0x80 (silence) past its end. */
uint32_t vgm_bank_byte(const vgm_bank *b, uint32_t off);
void vgm_stream_cmd(vgm_seq *v, const uint8_t *p); /* 0x90-0x95 (vgm_stream.c) */
void vgm_stream_tick(vgm_seq *v);                 /* after each chip sample while a stream plays */

#endif
