/* The SFX device (zm_vgm.h "SFX"): a cart's timed register writes to the YM2612 and the SN76489 that play
 * the tune, on the channels the cart owns. The writes wait in a ring, each at the engine frame its stamp maps
 * to (zm_vgm_out_lead: the output stage's own arithmetic, so the map is the same on every host whatever the
 * size of its render calls), and are applied between engine frames, in the order they came.
 * Ownership (zm_vgm_own.c): a write to a channel the cart does not own is refused (counted); the tune's
 * writes to a channel the cart owns are kept aside (the tune's image) and put back when the cart lets the
 * channel go. The cart's own writes are kept too (its image), put back after a tune load resets the chips.
 * The YM2612's A4-A6 latch and the SN76489's latch are each writer's own: a cart pair never takes the tune's
 * high byte or channel. Global registers (LFO, timers, channel 3's mode, the Game Gear stereo) stay the
 * tune's. Our own code. */
#include "zm_vgm.h"
#include "zm_vgm_own.h"
#include "zm_vgm_sfx.h"

#include "zm_mem.h"

#define SFX_CAP 512u      /* writes waiting (a power of two) */
#define SFX_D_MAX 100000u /* a stamp further ahead is held there: (d x rate) stays inside 32 bits */

typedef struct {
    uint32_t s, e; /* the stamp (output frames since the device's on) and the engine frame it maps to */
    uint16_t addr, val;
} sfx_ent;

static struct {
    uint32_t on, own, out, eng, head, len, applied, refused, late;
    uint32_t hi[2]; /* the cart's A4-A6 latch, per port */
    zm_chip_img tune, cart;
    sfx_ent ring[SFX_CAP];
} zs;

static int owns(uint32_t bit) { return bit < 12u && (zs.own >> bit & 1u); }

void zm_sfx_music_ym(vgm_seq *v, uint32_t port, uint32_t reg, uint32_t val) {
    if (zs.on) {
        port &= 1u, reg &= 0xFFu, val &= 0xFFu;
        uint32_t ch = zm_ym_owner(port, reg, val);
        if (ch < 6u) {
            if (reg == 0x28) zs.tune.key[ch] = (uint8_t)(val >> 4);
            else zs.tune.ym[port][reg] = (uint8_t)val;
            if (owns(ch)) return;
        }
    }
    ym2612_write(&v->ym, port, reg, val);
}

void zm_sfx_music_psg(vgm_seq *v, uint32_t byte) {
    if (zs.on) {
        zm_psg_mirror(&zs.tune.psg, byte);
        if (owns(8u + (zs.tune.psg.latch >> 1))) return;
    }
    sn76489_write(&v->psg, byte);
}

static void cart_ym(vgm_seq *v, uint32_t port, uint32_t reg, uint32_t val) {
    uint32_t ch = zm_ym_owner(port, reg, val);
    if (ch >= 6u || !owns(ch) || (reg >= 0xA8 && reg < 0xB0)) {
        zs.refused++;
        return;
    }
    zs.applied++;
    if (reg == 0x28) {
        zs.cart.key[ch] = (uint8_t)(val >> 4);
        ym2612_write(&v->ym, 0, 0x28, val);
        return;
    }
    zs.cart.ym[port][reg] = (uint8_t)val;
    if ((reg & 0xFCu) == 0xA4) { /* the cart's own latch: the chip's stays the tune's */
        zs.hi[port] = val & 0x3Fu;
        return;
    }
    uint32_t keep = v->ym.latch_hi[port];
    v->ym.latch_hi[port] = zs.hi[port];
    ym2612_write(&v->ym, port, reg, val);
    v->ym.latch_hi[port] = keep;
}

static void cart_psg(vgm_seq *v, uint32_t byte) {
    uint32_t latch = byte & 0x80u ? byte >> 4 & 7u : zs.cart.psg.latch;
    if (!owns(8u + (latch >> 1))) {
        zs.refused++;
        return;
    }
    zs.applied++;
    zm_psg_mirror(&zs.cart.psg, byte);
    uint32_t keep = v->psg.latch;
    v->psg.latch = latch;
    sn76489_write(&v->psg, byte);
    v->psg.latch = keep;
}

/* The channels the cart owns from now: one taken is keyed off / silenced, one let go gets the tune's image. */
static void cart_own(vgm_seq *v, uint32_t mask) {
    mask &= ZM_SFX_OWNABLE;
    uint32_t got = mask & ~zs.own, gone = zs.own & ~mask;
    zs.own = mask;
    for (uint32_t ch = 0; ch < 6; ch++) {
        if (got >> ch & 1u) zm_ym_key(&v->ym, ch, 0);
        if (got >> ch & 1u && ch == 5) ym2612_write(&v->ym, 0, 0x2B, 0); /* the tune's DAC would replace the cart's FM 6 */
        if (gone >> ch & 1u) zm_ym_key(&v->ym, ch, 0), zm_ym_put(&v->ym, &zs.tune, ch);
    }
    for (uint32_t c = 0; c < 4; c++) {
        if (got >> (8 + c) & 1u) zm_psg_mute(&v->psg, c);
        if (gone >> (8 + c) & 1u) zm_psg_put(&v->psg, &zs.tune.psg, c);
    }
}

/* The tune stops (its file ends here); the cart's channels play on. */
static void tune_stop(vgm_seq *v) {
    v->ended = 1;
    v->st.on = 0;
    for (uint32_t ch = 0; ch < 6; ch++)
        if (!owns(ch)) zm_ym_key(&v->ym, ch, 0), zs.tune.key[ch] = 0;
    if (!owns(5)) ym2612_write(&v->ym, 0, 0x2B, 0), zs.tune.ym[0][0x2B] = 0;
    for (uint32_t c = 0; c < 4; c++)
        if (!owns(8 + c)) zm_psg_mute(&v->psg, c), zs.tune.psg.att[c] = 15;
}

static void apply(vgm_seq *v, const sfx_ent *x) {
    uint32_t a = x->addr, val = x->val;
    if (a < ZM_SFX_PSG) {
        cart_ym(v, a >> 8, a & 0xFFu, val & 0xFFu);
    } else if (a == ZM_SFX_PSG) {
        cart_psg(v, val & 0xFFu);
    } else if (a == ZM_SFX_OWN) {
        cart_own(v, val);
        zs.applied++;
    } else if (a == ZM_SFX_TUNE && val == ZM_SFX_TUNE_STOP) {
        tune_stop(v);
        zs.applied++;
    } else {
        zs.refused++;
    }
}

static uint32_t frame_of(uint32_t s) {
    int32_t d = (int32_t)(s - zs.out);
    uint32_t ahead = d < 0 ? 0u : (uint32_t)d > SFX_D_MAX ? SFX_D_MAX : (uint32_t)d;
    return zs.eng + (uint32_t)zm_vgm_out_lead(ahead);
}

uint32_t zm_sfx_due(vgm_seq *v, uint32_t k) {
    while (zs.len) {
        sfx_ent *x = &zs.ring[zs.head];
        int32_t ahead = (int32_t)(x->e - zs.eng);
        if (ahead > 0) return (uint32_t)ahead < k ? (uint32_t)ahead : k;
        if (ahead < 0) zs.late++;
        apply(v, x);
        zs.head = (zs.head + 1u) & (SFX_CAP - 1u);
        zs.len--;
    }
    return k;
}

void zm_sfx_rendered(uint32_t k) { zs.eng += k; }
void zm_sfx_output(uint32_t n) { zs.out += n; }

void zm_sfx_loaded(vgm_seq *v) {
    if (!zs.on) return;
    for (uint32_t i = 0; i < zs.len; i++) {
        sfx_ent *x = &zs.ring[(zs.head + i) & (SFX_CAP - 1u)];
        x->e = frame_of(x->s);
    }
    zm_img_reset(&zs.tune);
    for (uint32_t ch = 0; ch < 6; ch++)
        if (owns(ch)) zm_ym_put(&v->ym, &zs.cart, ch);
    for (uint32_t c = 0; c < 4; c++)
        if (owns(8 + c)) zm_psg_put(&v->psg, &zs.cart.psg, c);
}

void zm_sfx_switch(vgm_seq *v, uint32_t on) {
    if (zs.on && zs.own) cart_own(v, 0); /* the tune gets its channels back */
    memset(&zs, 0, sizeof zs - sizeof zs.ring);
    zm_img_reset(&zs.tune);
    zm_img_reset(&zs.cart);
    zs.on = on;
}

uint32_t zm_vgm_sfx_push(uint32_t stamp, uint32_t addr, uint32_t value) {
    if (!zs.on || zs.len == SFX_CAP) return 0;
    sfx_ent *x = &zs.ring[(zs.head + zs.len) & (SFX_CAP - 1u)];
    x->s = stamp;
    x->e = frame_of(stamp);
    x->addr = (uint16_t)addr;
    x->val = (uint16_t)value;
    zs.len++;
    return 1;
}

uint32_t zm_vgm_sfx_stat(uint32_t i) {
    const uint32_t v[] = {zs.applied, zs.refused, zs.len, zs.late, zs.out, zs.own, zs.on};
    return i < sizeof v / sizeof v[0] ? v[i] : 0;
}
