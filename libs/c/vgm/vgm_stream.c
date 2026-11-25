/* VGM 1.60's DAC stream control (0x90-0x95, vgmrips.net "VGM Specification" v1.71): the YM2612's DAC
 * fed from the data bank at a set frequency, between chip samples. One stream, to the YM2612's register
 * 0x2A (the only target the Mega Drive's logs use); a stream set up for another chip is ignored. */
#include "vgm_seq.h"
#include "zm_vgm_sfx.h"

static uint32_t bank_start(const vgm_bank *b, uint32_t block) {
    uint32_t off = 0;
    for (uint32_t i = 0; i < block && i < b->n; i++) off += b->len[i];
    return off;
}

static void start(vgm_seq *v, uint32_t at, uint32_t len, uint32_t mode) {
    vgm_stream *s = &v->st;
    s->data_start = at;
    s->data_len = len;
    s->pos = 0;
    s->acc = 0;
    s->mode = mode;
    s->on = s->freq != 0 && len != 0 && s->setup;
}

void vgm_stream_cmd(vgm_seq *v, const uint8_t *p) {
    vgm_stream *s = &v->st;
    if (p[1] != 0 && !(p[0] == 0x94 && p[1] == 0xFF)) return; /* stream 0 only */
    switch (p[0]) {
    case 0x90: s->setup = p[2] == 0x02 && p[4] == 0x2A; break; /* chip type 2: the YM2612, its DAC */
    case 0x91: s->step = p[3] ? p[3] : 1u, s->base = p[4]; break;
    case 0x92: /* at most 4 writes a chip sample: a wild rate must not stall the render */
        s->freq = vgm_u32(p + 2);
        if (s->freq > 4u * v->rate) s->freq = 4u * v->rate;
        break;
    case 0x93: {
        uint32_t at = vgm_u32(p + 2), m = p[6], n = vgm_u32(p + 7);
        if (at == 0xFFFFFFFFu) at = s->data_start;
        if ((m & 3u) == 2u) n = (uint32_t)(((uint64_t)n * s->freq) / 1000u); /* milliseconds: rare, a command */
        else if ((m & 3u) == 3u || (m & 3u) == 0u) n = v->bank.total > at ? v->bank.total - at : 0;
        start(v, at, n, m & 0x80u);
        break;
    }
    case 0x94: s->on = 0; break;
    case 0x95: {
        uint32_t blk = p[2] | (uint32_t)p[3] << 8;
        start(v, bank_start(&v->bank, blk), blk < v->bank.n ? v->bank.len[blk] : 0, p[4] & 1u ? 0x80u : 0);
        break;
    }
    default: break;
    }
}

/* After one chip sample: the stream's writes that fell due during it. */
void vgm_stream_tick(vgm_seq *v) {
    vgm_stream *s = &v->st;
    for (s->acc += s->freq; s->acc >= v->rate && s->on; s->acc -= v->rate) {
        uint32_t off = s->data_start + s->base + s->pos * s->step;
        zm_sfx_music_ym(v, 0, 0x2A, vgm_bank_byte(&v->bank, off)); /* the DAC: FM 6's owner's */
        if (++s->pos < s->data_len) continue;
        s->pos = 0;
        if (!s->mode) s->on = 0;
    }
}
