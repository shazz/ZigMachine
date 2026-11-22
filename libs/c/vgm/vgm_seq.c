/* The VGM sequencer (vgm_seq.h), from the VGM specification (vgmrips.net, v1.71). Our own code. No
 * divide in the play path (BARD has no divider): waits convert through a multiply by 2^32 / 44100. */
#include "vgm_seq.h"

#include "zm_mem.h"

#define VGM_RATE 44100u

uint32_t vgm_u32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

/* x / 44100 for any 32-bit x: a multiply by floor(2^32 / 44100), then a fix-up of at most one. */
static uint32_t div44100(uint32_t x) {
    uint32_t q = (uint32_t)(((uint64_t)x * 97391u) >> 32);
    while (x - q * VGM_RATE >= VGM_RATE) q++;
    return q;
}

static void wait44(vgm_seq *v, uint32_t w) {
    while (w) { /* in pieces, so w x rate stays inside 32 bits */
        uint32_t k = w > 32768u ? 32768u : w;
        v->acc += k * v->rate;
        uint32_t q = div44100(v->acc);
        v->acc -= q * VGM_RATE;
        v->due += q;
        w -= k;
    }
}

uint32_t vgm_bank_byte(const vgm_bank *b, uint32_t off) {
    for (uint32_t i = 0; i < b->n; i++) {
        if (off < b->len[i]) return b->at[i][off];
        off -= b->len[i];
    }
    return 0x80;
}

static void dac(vgm_seq *v, uint32_t byte) { ym2612_write(&v->ym, 0, 0x2A, byte); }

/* The end, or the loop: a loop pass that waited nothing would spin for ever (a malformed loop offset), so the
 * second such pass ends the tune. */
static void end_or_loop(vgm_seq *v) {
    if (v->loop && v->loop < v->len && (v->loops == 0 || v->waited)) {
        v->pos = v->loop;
        v->loops++;
        v->waited = 0;
    } else {
        v->ended = 1;
    }
}

static void data_block(vgm_seq *v, const uint8_t *p) {
    uint32_t type = p[2], size = vgm_u32(p + 3) & 0x7FFFFFFFu, at = v->pos + 7;
    if (size > v->len - at) size = v->len - at;
    vgm_bank *b = &v->bank;
    if (type == 0x00 && b->n < VGM_BANKS) {
        b->at[b->n] = v->d + at;
        b->len[b->n++] = size;
        b->total += size;
    }
    v->pos = at + size;
}

/* Bytes after the opcode, by the specification's ranges (0 for those handled before). */
static uint32_t arg_len(uint32_t c) {
    if (c >= 0x30 && c <= 0x3F) return 1;
    if (c == 0x4F || c == 0x50 || c == 0x94) return 1;
    if (c == 0x61) return 2;
    if ((c >= 0x40 && c <= 0x4E) || (c >= 0x51 && c <= 0x5F) || (c >= 0xA0 && c <= 0xBF)) return 2;
    if (c >= 0xC0 && c <= 0xDF) return 3;
    if (c == 0x90 || c == 0x91 || c == 0x95) return 4;
    if (c == 0x92) return 5;
    if (c == 0x93) return 10;
    if (c >= 0xE0) return 4;
    return 0xFFFFFFFFu;
}

/* One command; the wait it implies, in 44.1 kHz samples. */
static uint32_t step(vgm_seq *v) {
    const uint8_t *p = v->d + v->pos;
    uint32_t c = p[0], room = v->len - v->pos;
    if ((c & 0xF0u) == 0x70u) return v->pos++, (c & 15u) + 1u;
    if ((c & 0xF0u) == 0x80u) {
        dac(v, vgm_bank_byte(&v->bank, v->pcm_pos++));
        return v->pos++, c & 15u;
    }
    if (c == 0x62) return v->pos++, 735u;
    if (c == 0x63) return v->pos++, 882u;
    if (c == 0x66) return end_or_loop(v), 0;
    if (c == 0x67) return room < 7 ? (v->ended = 1, 0) : (data_block(v, p), 0);
    uint32_t n = arg_len(c);
    if (n == 0xFFFFFFFFu || room < n + 1) return v->unknown++, v->ended = 1, 0;
    v->pos += n + 1;
    if (c == 0x52 || c == 0x53) ym2612_write(&v->ym, c & 1u, p[1], p[2]);
    else if (c == 0x50) sn76489_write(&v->psg, p[1]);
    else if (c == 0x4F) sn76489_stereo(&v->psg, p[1]);
    else if (c == 0x61) return p[1] | (uint32_t)p[2] << 8;
    else if (c == 0xE0) v->pcm_pos = vgm_u32(p + 1);
    else if (c >= 0x90 && c <= 0x95) vgm_stream_cmd(v, p);
    return 0;
}

/* The commands due now, until one implies a wait or the file ends. */
static void advance(vgm_seq *v) {
    while (!v->due && !v->ended) {
        if (v->pos >= v->len) {
            end_or_loop(v);
            continue;
        }
        uint32_t w = step(v);
        if (w) v->waited = 1, wait44(v, w);
    }
}

static void render(vgm_seq *v, int16_t *lr, uint32_t k) {
    if (v->has_ym) ym2612_render(&v->ym, lr, k);
    else memset(lr, 0, 4u * k);
    if (v->has_psg) sn76489_mix(&v->psg, lr, k);
}

void vgm_fill(vgm_seq *v, int16_t *lr, uint32_t n) {
    while (n) {
        advance(v);
        uint32_t k = v->ended ? n : (v->due < n ? v->due : n);
        if (v->st.on) k = 1; /* a DAC stream writes between chip samples: one at a time */
        render(v, lr, k);
        if (v->st.on) vgm_stream_tick(v);
        if (!v->ended) v->due -= k;
        lr += 2 * k;
        n -= k;
    }
}

void vgm_seek(vgm_seq *v, uint32_t t44) {
    uint32_t t = 0;
    while (t < t44 && !v->ended) {
        if (v->pos >= v->len) {
            end_or_loop(v);
            continue;
        }
        uint32_t w = step(v);
        t += w;
        if (w) v->waited = 1;
    }
    v->acc = v->due = 0;
}

int vgm_open(vgm_seq *v, const uint8_t *d, uint32_t len, uint32_t div, int32_t ym_gain, int32_t psg_gain) {
    memset(v, 0, sizeof *v);
    if (len < 0x40 || d[0] != 'V' || d[1] != 'g' || d[2] != 'm' || d[3] != ' ') return 1;
    uint32_t ver = vgm_u32(d + 8), eof = vgm_u32(d + 4) + 4;
    uint32_t psg_clk = vgm_u32(d + 0x0C) & 0x3FFFFFFFu, ym_clk = ver >= 0x110 ? vgm_u32(d + 0x2C) & 0x3FFFFFFFu : 0;
    if (!psg_clk && !ym_clk) return 2;
    v->d = d;
    v->len = eof >= 0x40 && eof < len ? eof : len;
    v->start = ver >= 0x150 && vgm_u32(d + 0x34) ? 0x34 + vgm_u32(d + 0x34) : 0x40;
    if (v->start >= v->len) return 3;
    v->loop = vgm_u32(d + 0x1C) ? 0x1C + vgm_u32(d + 0x1C) : 0;
    v->pos = v->start;
    v->has_ym = ym_clk != 0;
    v->has_psg = psg_clk != 0;
    v->rate = (ym_clk ? ym_clk : 7670453u) / (144u * (div == 1 ? 1u : 2u)); /* load only */
    ym2612_reset(&v->ym, div);
    v->ym.gain = ym_gain;
    sn76489_reset(&v->psg, psg_clk ? psg_clk : 3579545u, v->rate, psg_gain);
    return 0;
}
