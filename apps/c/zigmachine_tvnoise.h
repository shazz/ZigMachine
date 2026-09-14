// ---------------------------------------------------------------------------
// zigmachine_tvnoise.h — the channel-change snow for a C cart.
//
// On +/- the host boots the new channel's disk and calls tuneIn(25) instead of
// skipBoot() (docs/sealed-loader.js). A Zig cart answers with 25 frames of TV
// snow, then starts (apps/zig/demo_main.zig). A cart WITHOUT tuneIn just starts,
// which is why the C and Rust screens used to cut straight in.
//
// This is that snow, BYTE-FOR-BYTE: libs/zig/tvnoise/tvnoise.zig's xorshift32,
// ramp, rolling band and tear lines, with demo_main's seed, first index and plane
// setup (a 400x280 overscan plane 0, borders flickered open on every line, its
// buffer where resetForScene + openBorders put it). apps/tunein_check.mjs proves
// the pixels and palette match a Zig cart's frame for frame.
//
// Unlike demo_main, which starts the cart AFTER the snow, a C cart has already
// run boot(). So tuneIn saves the video registers and palette 0 it is about to
// overwrite, and restores them when the snow ends: the cart's first frame then
// sees exactly the machine skipBoot() would have left it. The snow draws into
// its own buffer, never the cart's.
//
//     #include "../zigmachine_tvnoise.h"   // from exactly ONE .c file: it defines tuneIn
//     void frame(float dt)  { if (zm_tvnoise_frame()) return; ... }
//     void hblDispatch(...) { if (zm_tvnoise_hbl()) return; ... }
//     void skipBoot(void)   { zm_tvnoise_stop(); }
//
// A cart that shows a plane other than 0 must also answer isPlaneEnabled with
// `id == 0` while zm_tvnoise_active().
// ---------------------------------------------------------------------------
#ifndef ZIGMACHINE_TVNOISE_H
#define ZIGMACHINE_TVNOISE_H

__attribute__((import_module("env"), import_name("hwVideoBase")))
extern int hwVideoBase(void);

// tvnoise.zig and demo_main.zig. Change one there, change it here.
#define ZM_TV_LEVELS     8
#define ZM_TV_BAND_ROWS  24u
#define ZM_TV_BAND_BOOST 3
#define ZM_TV_FIRST      0            // demo_main NOISE_FIRST
#define ZM_TV_SEED       0x5EED7E1Eu  // demo_main NOISE_SEED
static const unsigned char zm_tv_ramp[ZM_TV_LEVELS] = { 0x00, 0x24, 0x49, 0x6d, 0x92, 0xb6, 0xdb, 0xff };

// machine/sdk/memmap.zig.
#define ZM_TV_W            400u // PHYSICAL_WIDTH
#define ZM_TV_H            280u // PHYSICAL_HEIGHT
#define ZM_TV_OFF_PAL      0x0100
#define ZM_TV_PAL_BYTES    1024
#define ZM_TV_REG_RES      0x00
#define ZM_TV_REG_BG       0x04
#define ZM_TV_REG_GHBL_ID  0x10
#define ZM_TV_REG_HBL_ID   0x20
#define ZM_TV_REG_HBL_POS  0x28
#define ZM_TV_REG_FRAME    0x30 // read-only counter: never restored
#define ZM_TV_REG_STRIDE   0x34
#define ZM_TV_REG_HSCROLL  0x3C
#define ZM_TV_REG_FB_BASE  0x44
#define ZM_TV_REG_MODE     0x54
#define ZM_TV_REG_FLICKER  0x58
#define ZM_TV_REGS         0x5C // everything below REG_CART_HIGH, which the host owns
#define ZM_TV_MODE_OVERSCAN 4
#define ZM_TV_RES_PLANES    0
#define ZM_TV_RES_MEDIUM    2
#define ZM_TV_MAGIC_X       40
// Where Zig's snow buffer lives: resetForScene allocates four 320x200 planes from
// OFF_VRAM, then openBorders gives plane 0 the next 400x280. Past any buffer a C
// cart uses at the default plane-0 base, so the cart's picture survives the snow.
#define ZM_TV_FB           (0x1100u + 4u * 64000u)

static unsigned zm_tv_state, zm_tv_roll, zm_tv_frames;
static int zm_tv_tuning = 0;  // snow on screen
static int zm_tv_started = 0; // the cart has run: tuneIn is ignored from here on
static unsigned char zm_tv_regs[ZM_TV_REGS];
static unsigned char zm_tv_pal[ZM_TV_PAL_BYTES];

static inline unsigned char *zm_tv_io(unsigned off) { return (unsigned char *)(hwVideoBase() + off); }

// tvnoise.zig Noise.next.
static unsigned zm_tv_next(void) {
    unsigned x = zm_tv_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    zm_tv_state = x;
    return x;
}

// tvnoise.zig Noise.fill, over the whole 400x280 buffer.
static void zm_tv_fill(unsigned char *buf) {
    const unsigned w = ZM_TV_W, h = ZM_TV_H, first = ZM_TV_FIRST;
    const unsigned tear_a = zm_tv_next() % h;
    const unsigned tear_b = zm_tv_next() % h;
    for (unsigned y = 0; y < h; y++) {
        unsigned char *row = buf + y * w;
        if (y == tear_a || y == tear_b) {
            const unsigned jitter = zm_tv_next() % 8;
            for (unsigned x = 0; x < w; x++) row[x] = (unsigned char)(x < jitter ? first + 2 : first);
            continue;
        }
        const int in_band = (y - zm_tv_roll) % h < ZM_TV_BAND_ROWS;
        unsigned bits = 0, left = 0;
        for (unsigned x = 0; x < w; x++) {
            if (left < 3) {
                bits = zm_tv_next();
                left = 30;
            }
            unsigned lvl = bits & 7;
            bits >>= 3;
            left -= 3;
            if (in_band && (lvl += ZM_TV_BAND_BOOST) > ZM_TV_LEVELS - 1) lvl = ZM_TV_LEVELS - 1;
            row[x] = (unsigned char)(first + lvl);
        }
    }
    zm_tv_roll = (zm_tv_roll + 3) % h;
}

static inline void zm_tv_w16(unsigned off, unsigned v) {
    zm_tv_io(off)[0] = (unsigned char)v;
    zm_tv_io(off)[1] = (unsigned char)(v >> 8);
}

// End the snow now (if any) and give the machine back to the cart. Also the
// cart's skipBoot: Escape during the snow lands in the cart, as in demo_main.
static inline void zm_tvnoise_stop(void) {
    if (zm_tv_tuning) {
        unsigned char *io = zm_tv_io(0);
        for (unsigned i = 0; i < ZM_TV_REGS; i++)
            if (i < ZM_TV_REG_FRAME || i >= ZM_TV_REG_FRAME + 4) io[i] = zm_tv_regs[i];
        for (unsigned i = 0; i < ZM_TV_PAL_BYTES; i++) io[ZM_TV_OFF_PAL + i] = zm_tv_pal[i];
    }
    zm_tv_tuning = 0;
    zm_tv_started = 1;
}

static inline int zm_tvnoise_active(void) { return zm_tv_tuning; }

// Call first thing in frame(). 1 = this frame was snow, return without drawing.
// On the frame after the last snow frame it restores the machine and returns 0,
// so the cart draws that frame: its first, exactly as after skipBoot().
static inline int zm_tvnoise_frame(void) {
    if (zm_tv_tuning && zm_tv_frames > 0) {
        zm_tv_frames--;
        zm_tv_fill(zm_tv_io(ZM_TV_FB));
        return 1;
    }
    zm_tvnoise_stop();
    return 0;
}

// Call first thing in hblDispatch(). 1 = the snow's HBL: open this line's borders.
static inline int zm_tvnoise_hbl(void) {
    if (!zm_tv_tuning) return 0;
    unsigned char *io = zm_tv_io(0);
    io[ZM_TV_REG_RES] = ZM_TV_RES_MEDIUM; // the ST resolution flicker (zigos flickerBorder)
    io[ZM_TV_REG_RES] = ZM_TV_RES_PLANES;
    zm_tv_w16(ZM_TV_REG_FLICKER, (unsigned)(io[ZM_TV_REG_FLICKER] | io[ZM_TV_REG_FLICKER + 1] << 8) + 1);
    return 1;
}

// demo_main tuneIn: `frames` frames of snow over the whole tube, then the cart.
__attribute__((export_name("tuneIn")))
void tuneIn(unsigned frames) {
    if (zm_tv_started) return; // a running cart ignores it
    if (frames == 0) {
        zm_tvnoise_stop();
        return;
    }
    unsigned char *io = zm_tv_io(0);
    if (!zm_tv_tuning) { // a second tuneIn must not save the snow as the cart's state
        for (unsigned i = 0; i < ZM_TV_REGS; i++) zm_tv_regs[i] = io[i];
        for (unsigned i = 0; i < ZM_TV_PAL_BYTES; i++) zm_tv_pal[i] = io[ZM_TV_OFF_PAL + i];
    }
    // resetForScene: planes resolution, dark grey border, no global HBL, palette 0 clear.
    io[ZM_TV_REG_RES] = ZM_TV_RES_PLANES;
    io[ZM_TV_REG_BG] = 20; io[ZM_TV_REG_BG + 1] = 20; io[ZM_TV_REG_BG + 2] = 20; io[ZM_TV_REG_BG + 3] = 255;
    zm_tv_w16(ZM_TV_REG_GHBL_ID, 0);
    for (unsigned i = 0; i < ZM_TV_PAL_BYTES; i++) io[ZM_TV_OFF_PAL + i] = 0;
    // openBorders(.all) on plane 0: overscan buffer, HBL id plane+1 at the magic column.
    zm_tv_w16(ZM_TV_REG_STRIDE, ZM_TV_W);
    zm_tv_w16(ZM_TV_REG_HSCROLL, 0);
    io[ZM_TV_REG_MODE] = ZM_TV_MODE_OVERSCAN;
    io[ZM_TV_REG_FB_BASE] = (unsigned char)ZM_TV_FB;
    io[ZM_TV_REG_FB_BASE + 1] = (unsigned char)(ZM_TV_FB >> 8);
    io[ZM_TV_REG_FB_BASE + 2] = (unsigned char)(ZM_TV_FB >> 16);
    io[ZM_TV_REG_FB_BASE + 3] = (unsigned char)(ZM_TV_FB >> 24);
    zm_tv_w16(ZM_TV_REG_HBL_ID, 1);
    zm_tv_w16(ZM_TV_REG_HBL_POS, ZM_TV_MAGIC_X);
    unsigned char *pal = io + ZM_TV_OFF_PAL;
    for (unsigned i = 0; i < ZM_TV_LEVELS; i++) {
        const unsigned e = (ZM_TV_FIRST + i) * 4;
        pal[e] = pal[e + 1] = pal[e + 2] = zm_tv_ramp[i];
        pal[e + 3] = 255;
    }
    zm_tv_state = ZM_TV_SEED; // tvnoise.zig maps only seed 0 elsewhere
    zm_tv_roll = 0;
    zm_tv_frames = frames;
    zm_tv_tuning = 1;
}

#endif
