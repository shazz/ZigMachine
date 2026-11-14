/* The Paula channels' oscilloscopes (host/audio_scope.h): engine.zig's Channel.mixInto, minus
 * the mix. Per sample, as mixInto: a looping channel wraps (while pos >= loop end, pos -= loop
 * length), a one-shot stops at its end, the 4th-sample counter (scope_ctr, a u2) captures when
 * it is 0, and pos += step. Between captures nothing is read, so a run of four samples that
 * cannot reach the end is taken in one step (the fast path).
 *
 * Integer only and no divide (BARD is rv32i + Zmmul: a `/` is a 400-cycle libgcc call). */
#include "audio_scope.h"

#include <string.h>

#define MAX_FRAMES 4096u /* engine.zig MAX_FRAMES: machineMixPaula clamps its piece to it */

typedef struct {
    uint32_t data, len, ls, ll, step, active, ctr, w;
    uint32_t vsign, vexp, vman; /* the volume's f32, split (vol_split) */
    uint32_t vbits, tab_ok;     /* the volume's bits; tab holds its products, until it changes */
    uint32_t tab[129];          /* mul_s8(a, volume) for a = |s| in 0..128 */
    uint64_t pos; /* 16.16, as engine.zig's */
} zsc_ch;

static zsc_ch g_ch[ZSC_CHANNELS];
static volatile uint32_t* g_dst;

/* The volume's f32 split once (zsc_vol): sign, biased exponent, 24-bit mantissa; mantissa 0 for a
 * zero (or a denormal, inf, NaN, which no player sets: the product is then a signed zero). */
static void vol_split(zsc_ch* c, uint32_t bits) {
    uint32_t e = bits >> 23 & 0xFFu;
    c->vsign = bits & 0x80000000u;
    c->vexp = e;
    c->vman = e && e != 0xFFu ? (bits & 0x7FFFFFu) | 0x800000u : 0u;
}

/* (s / 128) * vol as f32 bits, rounded to nearest even: the engine's `s * self.volume`, where
 * s = i8 / 128 is exact. |s| * mantissa < 2^31, so one integer multiply and a rounding shift. */
static uint32_t mul_s8(int32_t s, const zsc_ch* c) {
    uint32_t sign = (s < 0 ? 0x80000000u : 0u) ^ c->vsign, a = s < 0 ? (uint32_t)-s : (uint32_t)s;
    if (!a || !c->vman) return sign;
    uint32_t p = a * c->vman, r = 0; /* p in [2^23, 2^31) */
    if (p >= 1u << 27) r += 4;
    if (p >= 1u << (25 + r)) r += 2;
    if (p >= 1u << (24 + r)) r += 1;
    uint32_t m = p >> r;
    if (r) {
        uint32_t rem = p & ((1u << r) - 1u), half = 1u << (r - 1u);
        if (rem > half || (rem == half && (m & 1u))) m++;
        if (m == 1u << 24) m >>= 1, r++;
    }
    int32_t e = (int32_t)(c->vexp + r) - 7; /* value = 1.m * 2^(23 + r + vexp - 127 - 30) */
    return e <= 0 ? sign : sign | (uint32_t)e << 23 | (m & 0x7FFFFFu); /* below 2^-126: a zero */
}

/* A new volume: split, and its table rebuilt at its first capture (a MOD sets a channel's volume about
 * once a tick, an XM or a sample once: a lookup a capture instead of a multiply and a rounding). */
static void set_vol(zsc_ch* c, uint32_t bits) {
    if (bits == c->vbits) return; /* zeroed (init) is the volume 0.0 split, its table not built */
    vol_split(c, bits);
    c->vbits = bits;
    c->tab_ok = 0;
}

static void build_tab(zsc_ch* c) {
    for (uint32_t a = 0; a <= 128u; a++) c->tab[a] = mul_s8((int32_t)a, c);
    c->tab_ok = 1;
}

uint32_t zsc_f32(int32_t s, uint32_t vol_bits) {
    zsc_ch c;
    vol_split(&c, vol_bits);
    return mul_s8(s, &c);
}

static void clear_rings(void) {
    for (uint32_t c = 0; c < ZSC_CHANNELS; c++) g_ch[c].w = 0;
    if (g_dst)
        for (uint32_t i = 0; i < ZSC_CHANNELS * ZSC_LEN; i++) g_dst[i] = 0;
}

void zsc_target(volatile uint32_t* dst) {
    g_dst = dst;
    clear_rings();
}

void zsc_init(void) {
    memset(g_ch, 0, sizeof g_ch);
    for (uint32_t c = 0; c < ZSC_CHANNELS; c++) set_vol(&g_ch[c], 0x3F800000u); /* volume 1.0 */
    clear_rings();
}

void zsc_reset(void) {
    for (uint32_t c = 0; c < ZSC_CHANNELS; c++) g_ch[c].active = 0;
    clear_rings();
}

void zsc_clear(void) { clear_rings(); }

void zsc_trigger(uint32_t ch, uint32_t data, uint32_t len, uint32_t ls, uint32_t ll) {
    if (ch >= ZSC_CHANNELS) return;
    zsc_ch* c = &g_ch[ch];
    c->data = data, c->len = len, c->ls = ls, c->ll = ll, c->pos = 0, c->active = 1;
}

void zsc_step(uint32_t ch, uint32_t step) {
    if (ch < ZSC_CHANNELS) g_ch[ch].step = step;
}
void zsc_vol(uint32_t ch, uint32_t vol_bits) {
    if (ch < ZSC_CHANNELS) set_vol(&g_ch[ch], vol_bits);
}
void zsc_pos(uint32_t ch, uint32_t pos) {
    if (ch < ZSC_CHANNELS) g_ch[ch].pos = (uint64_t)pos << 16;
}
void zsc_active(uint32_t ch, uint32_t on) {
    if (ch < ZSC_CHANNELS) g_ch[ch].active = on != 0;
}

/* One channel over `n` samples. The read past `len` that a looping channel's bad loop could
 * make (the engine would trap) reads 0 here. */
static void mix_one(zsc_ch* c, const uint8_t* mem, volatile uint32_t* ring, uint32_t n) {
    const int8_t* d = (const int8_t*)(mem + c->data);
    if (!c->tab_ok) build_tab(c);
    const int loop = c->ll > 1;
    const uint64_t span = (uint64_t)c->ll << 16, step = c->step, step3 = 3u * step, step4 = 4u * step;
    const uint64_t end = loop ? (uint64_t)(c->ls + c->ll) << 16 : (uint64_t)c->len << 16;
    uint64_t p = c->pos;
    uint32_t ctr = c->ctr, w = c->w, i = 0;
    while (i < n) {
        if (p >= end) {
            if (!loop) {
                c->active = 0;
                break;
            }
            do p -= span; while (p >= end);
        }
        if (ctr == 0) {
            uint32_t at = (uint32_t)(p >> 16);
            int32_t sv = at < c->len ? d[at] : 0; /* (s / 128) * volume: the table's, signed */
            ring[w] = c->tab[sv < 0 ? -sv : sv] ^ (sv < 0 ? 0x80000000u : 0u);
            w = (w + 1u) & (ZSC_LEN - 1u);
            if (n - i >= 4u && p + step3 < end) { /* the next three samples neither wrap nor end */
                p += step4, i += 4u;
                continue;
            }
        }
        ctr = (ctr + 1u) & 3u, p += step, i++;
    }
    c->pos = p, c->ctr = ctr, c->w = w;
}

#ifdef ZM_SND_SCOPES /* the bench's share (cycles/sound/smain.c "SC"): BARD's cycle counter around each piece */
#include "snd_mailbox.h"
uint32_t zsc_cycles;
#define ZSC_T0() uint32_t t0 = SND_REG(SND_CYCLES)
#define ZSC_T1() zsc_cycles += SND_REG(SND_CYCLES) - t0
#else
#define ZSC_T0() (void)0
#define ZSC_T1() (void)0
#endif

void zsc_mix(const uint8_t* mem, uint32_t off, uint32_t len) {
    if (!g_dst || off >= MAX_FRAMES) return;
    ZSC_T0();
    uint32_t n = len < MAX_FRAMES - off ? len : MAX_FRAMES - off;
    for (uint32_t ch = 0; ch < ZSC_CHANNELS; ch++) {
        zsc_ch* c = &g_ch[ch];
        if (c->active && c->len) mix_one(c, mem, g_dst + ZSC_LEN * ch, n);
    }
    ZSC_T1();
}
