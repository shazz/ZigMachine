// ---------------------------------------------------------------------------
// CODEF screen 34 — ported to C, running on the sealed ZigMachine.
//
// The screen is MAD VISION's intro for MAXI's crack of "Fred" (30/03/90), from
// the Atari ST. Ported from NoNameNo's CODEF HTML5 remake (wab.com screen 34,
// MIT). Graphics and music are the originals' authors'; the tune is Mad Max's
// "So Watt - TCB", which the machine already carries as docs/music/sos.sndh.
//
// Why this exists in C: the seal is a wasm ABI, not a Zig API. This is the same
// machine-video.wasm the Zig scenes drive, and everything below is plain C
// writing palette indices into shared memory and poking hardware registers.
//
// It also does the hard trick from C: the screen's scroller lives at ST row 205,
// BELOW the 200-line visible screen, so this is a bottom-border screen. Opening
// that border is the real ST resolution-flicker: put the plane in OVERSCAN mode,
// register a per-plane HBL at the magic column, and flicker the resolution
// register on every scanline (see hblDispatch). Miss the column and the border
// shows garbage, exactly as on hardware.
//
// Per frame the original does only four things (screen.js `go()`):
//     fill black; logo at (320,80); flag tile 9-floor(i)%10 at (320,270);
//     scrolltext at y=410; i += 0.2
// All of those coordinates are CODEF's 640x480 canvas = 320x240 doubled, so they
// are halved here and then shifted into the 400x280 physical buffer.
// ---------------------------------------------------------------------------
#include "../assets/screens/screen34/data.h"

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;

// --- the sealed ABI --------------------------------------------------------
__attribute__((import_module("env"), import_name("hwVideoBase")))
extern int hwVideoBase(void);
__attribute__((import_module("env"), import_name("consoleLogJS")))
extern void consoleLogJS(const char *ptr, int len);

// Offsets into the video region — mirror machine/sdk/memmap.zig.
#define OFF_REG  0x0000
#define OFF_PAL  0x0100
#define OFF_VRAM 0x1100

#define REG_RESOLUTION  0x00 // u8
#define REG_FB_HBL_ID   0x20 // u16 x4
#define REG_FB_HBL_POS  0x28 // u16 x4
#define REG_FB_STRIDE   0x34 // u16 x4
#define REG_FB_MODE     0x54 // u8  x4
#define REG_RES_FLICKER 0x58 // u16

#define RES_PLANES       0
#define RES_MEDIUM       2
#define FB_MODE_OVERSCAN 4

// Physical (overscan) geometry, and where the visible 320x200 window sits in it.
#define PW 400
#define PH 280
#define BX 40 // the visible window's left edge in the 400-wide buffer
#define OVERSCAN_MAGIC_X 40 // the flicker MUST land here (+/- 4) or the line is garbage

// Where the CODEF canvas's row 0 lands on our 280-row raster.
//
// The canvas is 480 rows = 240 ST rows: the visible 200 PLUS the bottom border
// the scroller lives in. It has no TOP border, because the remake simply does
// not draw one. Our raster does (physical 0..39), so mapping canvas row 0 to the
// visible top (BY=40) pushed the whole screen 40 rows down and left a black band
// above the logo that the original does not have.
//
// Measured against the original running on wab.com: its logo occupies canvas
// rows 12..148, i.e. hard against the top of the frame. Mapping canvas row 0 to
// PHYSICAL row 0 reproduces that framing — the borders are open either way, so
// the logo simply uses the top one, exactly as the scroller uses the bottom.
#define LAYOUT_Y 0

static int video_base;
static float anim;    // the original's `i`, advancing 0.2 per frame
static float scroll;  // scroller x offset, in ST pixels

static inline u8 *reg(void) { return (u8 *)(video_base + OFF_REG); }
static inline u8 *pal(void) { return (u8 *)(video_base + OFF_PAL); }
static inline u8 *vram(void) { return (u8 *)(video_base + OFF_VRAM); }

static inline void w8(unsigned off, u8 v) { reg()[off] = v; }
static inline void w16(unsigned off, u16 v) { *(u16 *)(reg() + off) = v; }
static inline u16 r16(unsigned off) { return *(u16 *)(reg() + off); }

// The scrolltext. NOT the original's message, which is the crackers' own words —
// this names who made what instead. The original text is in the fetched
// reference at prototypes/codef/34/screen.js if it is ever wanted verbatim.
static const char TEXT[] =
    "    MAD VISION INTRO FOR MAXI'S CRACK OF FRED, 1990 ... "
    "MUSIC BY MAD MAX ... CODEF REMAKE BY NONAMENO ... "
    "THIS PORT RUNS IN C ON THE ZIGMACHINE, SAME SEALED HARDWARE AS THE ZIG SCENES, "
    "BOTTOM BORDER OPENED THE HONEST WAY ...        ";
#define TEXT_LEN (int)(sizeof(TEXT) - 1)

// Blit an indexed image into the physical buffer, index 0 transparent, clipped.
// `cx`/`cy` are the CENTRE, because CODEF calls setmidhandle() on both images.
static void blit_centred(const u8 *src, int w, int h, int cx, int cy) {
    const int x0 = cx - w / 2, y0 = cy - h / 2;
    u8 *dst = vram();
    for (int y = 0; y < h; y++) {
        const int py = y0 + y;
        if (py < 0 || py >= PH) continue;
        const int row = py * PW;
        const u8 *s = src + (unsigned)y * (unsigned)w;
        for (int x = 0; x < w; x++) {
            const int px = x0 + x;
            if (px < 0 || px >= PW) continue;
            const u8 v = s[x];
            if (v) dst[row + px] = v;
        }
    }
}

// One glyph of the 32x32 font sheet, at a top-left position.
static void blit_glyph(int glyph, int gx, int gy) {
    const u8 *src = FONT + (unsigned)glyph * (GLYPH * GLYPH);
    u8 *dst = vram();
    for (int y = 0; y < GLYPH; y++) {
        const int py = gy + y;
        if (py < 0 || py >= PH) continue;
        const int row = py * PW;
        for (int x = 0; x < GLYPH; x++) {
            const int px = gx + x;
            if (px < 0 || px >= PW) continue;
            const u8 v = src[y * GLYPH + x];
            if (v) dst[row + px] = v;
        }
    }
}

__attribute__((export_name("boot")))
void boot(void) {
    video_base = hwVideoBase();

    for (int i = 0; i < 256 * 4; i++) pal()[i] = PALETTE[i];

    // Plane 0 becomes a 400x280 OVERSCAN plane. Its framebuffer base is already
    // OFF_VRAM at reset, so only the stride and mode need setting.
    w16(REG_FB_STRIDE + 0 * 2, PW);
    w8(REG_FB_MODE + 0, FB_MODE_OVERSCAN);

    // Arm the per-plane HBL that opens the borders. Handler id is arbitrary but
    // must be non-zero; the column is NOT arbitrary (see hblDispatch).
    w16(REG_FB_HBL_ID + 0 * 2, 1);
    w16(REG_FB_HBL_POS + 0 * 2, OVERSCAN_MAGIC_X);

    anim = 0.0f;
    scroll = 0.0f;
    static const char msg[] = "screen 34 (Mad Vision / Fred) - C cart, overscan";
    consoleLogJS(msg, (int)sizeof(msg) - 1);
}

// Open the border on THIS scanline, ST-style: flicker the resolution register
// medium->planes. The sealed machine cannot trap writes to shared memory, so the
// flicker latch is bumped too — that is what it samples once per line.
__attribute__((export_name("hblDispatch")))
void hblDispatch(u32 id, u32 plane, u32 line, u32 x) {
    (void)id; (void)plane; (void)line; (void)x;
    w8(REG_RESOLUTION, RES_MEDIUM);
    w8(REG_RESOLUTION, RES_PLANES);
    w16(REG_RES_FLICKER, (u16)(r16(REG_RES_FLICKER) + 1));
}

__attribute__((export_name("frame")))
void frame(float dt) {
    (void)dt;
    u8 *dst = vram();
    for (int i = 0; i < PW * PH; i++) dst[i] = 0; // the original's fill('#000000')

    // logo: CODEF (320,80) -> ST (160,40) -> physical (+BX,+BY)
    blit_centred(LOGO, LOGO_W, LOGO_H, BX + 160, LAYOUT_Y + 40);

    // flag: CODEF (320,270) -> ST (160,135). Frame 9-floor(i)%10, i += 0.2, so
    // the animation advances one frame every five.
    int f = 9 - ((int)anim % FLAG_FRAMES);
    if (f < 0) f += FLAG_FRAMES;
    blit_centred(FLAG + (unsigned)f * (FLAG_W * FLAG_H), FLAG_W, FLAG_H,
                 BX + 160, LAYOUT_Y + 135);

    // scroller: CODEF y=410 -> ST y=205, which is BELOW the visible 200 lines.
    // It is legible only because the bottom border is open.
    const int sy = LAYOUT_Y + 205;
    const int off = (int)scroll;
    int first = off / GLYPH;
    int px = -(off % GLYPH);
    for (int slot = 0; px < PW; slot++, px += GLYPH) {
        const int ch = TEXT[(first + slot) % TEXT_LEN];
        const int g = (ch < FIRST_CHAR || ch >= FIRST_CHAR + NB_GLYPHS)
                          ? 0 // anything the font lacks shows as a space
                          : ch - FIRST_CHAR;
        if (g) blit_glyph(g, px, sy);
    }

    anim += 0.2f;                 // the original's i += 0.2
    scroll += 2.0f;               // CODEF speed 4 on a doubled canvas = 2 ST px
    if (scroll >= (float)(TEXT_LEN * GLYPH)) scroll -= (float)(TEXT_LEN * GLYPH);
}

__attribute__((export_name("isPlaneEnabled")))
_Bool isPlaneEnabled(u8 id) { return id == 0; }

__attribute__((export_name("skipBoot")))     void skipBoot(void) {}
__attribute__((export_name("setShadeMode"))) void setShadeMode(u32 m) { (void)m; }
__attribute__((export_name("pointer")))      void pointer(int x, int y, u32 b) { (void)x; (void)y; (void)b; }
__attribute__((export_name("input")))        void input(u8 dir) { (void)dir; }
