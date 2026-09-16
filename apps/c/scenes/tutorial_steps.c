// ---------------------------------------------------------------------------
// tutorial_steps.c: the tutorial screen, stopped at any step of docs/TUTORIAL.md.
//
// The C twin of apps/zig/scenes/tutorial_steps.zig — see that file for WHY this
// is a copy of tutorial.c rather than a flag inside it (short version: every
// snippet in docs/TUTORIAL.md is quoted verbatim from tutorial.c, and gates in
// there would make the tutorial's own code untrue). The copy is held to the
// original by apps/tutorial_steps_check.mjs, which asserts that this cart at
// step 7 renders frames byte-identical to demo-c-tutorial.wasm.
//
// The step arrives via setShadeMode (the sealed ABI's per-scene mode switch),
// which the host calls for ?step=N. It cannot arrive before boot(), so boot()
// only sets fields and every step-dependent decision is made in stage(), on the
// first frame() — still before the host renders a plane, so no wrong frame shows.
//
// Build: bash apps/c/build.sh tutorial_steps
// Run:   docs/index.html?demo=demo-c-tutorial_steps.wasm&step=3
// ---------------------------------------------------------------------------
#include "../zigmachine_music.h" // from exactly ONE .c file: it defines exports

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;

// --- the sealed ABI: one import, and offsets from machine/sdk/memmap.zig ---
__attribute__((import_module("env"), import_name("hwVideoBase")))
extern int hwVideoBase(void);

#define OFF_PAL        0x0100 // plane 0 palette: 256 x RGBA u32
#define OFF_VRAM       0x1100 // plane 0 framebuffer: 320 x 200 palette indices
#define REG_BACKGROUND 0x04   // u32: the border/background colour
#define REG_FB_HBL_ID  0x20   // u16 per plane: 0 = no HBL
#define REG_FB_HBL_POS 0x28   // u16 per plane: the column the HBL fires at
#define W 320
#define H 200

// palette indices
#define SKY         0
#define FLOOR_DARK  1
#define FLOOR_LIGHT 2
#define BLOCK       3
#define TEXT_INK    4

#define FLOOR_Y    160
#define BLOCK_SIZE 24
#define BAR_H      16

static int video_base;
static int block_x, block_y, block_dx, block_dy;
static int bar_y, bar_dy;
static u32 copper[H]; // the SKY colour of each visible line
static int scroll_x;

static inline u8 *vram(void) { return (u8 *)(video_base + OFF_VRAM); }
static inline u32 *palette(void) { return (u32 *)(video_base + OFF_PAL); }
static inline u32 rgba(u32 r, u32 g, u32 b) { return 0xFF000000u | b << 16 | g << 8 | r; }

static void fill_rect(int x, int y, int w, int h, u8 index) {
    for (int j = y; j < y + h; j++)
        for (int i = x; i < x + w; i++) vram()[j * W + i] = index;
}

static void draw_floor(void) {
    for (int y = FLOOR_Y; y < H; y++)
        for (int x = 0; x < W; x++)
            vram()[y * W + x] = ((x / 20 + y / 10) & 1) ? FLOOR_LIGHT : FLOOR_DARK;
}

static void move_block(void) {
    block_x += block_dx;
    block_y += block_dy;
    if (block_x <= 0 || block_x >= W - BLOCK_SIZE) block_dx = -block_dx;
    if (block_y <= 28 || block_y >= FLOOR_Y - BLOCK_SIZE) block_dy = -block_dy;
}

// One colour per line: a sky gradient, with a copper bar over it.
static void build_copper(void) {
    for (int line = 0; line < H; line++) {
        u32 c = rgba(0, line / 4, 40 + line / 2);
        int d = line - bar_y;
        if (d >= 0 && d < BAR_H) {
            int k = d < BAR_H / 2 ? d + 1 : BAR_H - d; // 1..8..1: bright in the middle
            c = rgba(k * 31, k * 24, k * 8);
        }
        copper[line] = c;
    }
    bar_y += bar_dy;
    if (bar_y <= 24 || bar_y >= FLOOR_Y - BAR_H) bar_dy = -bar_dy;
}

// A 5x7 font holding only the letters TEXT uses: one byte per row, bit 4 = left.
static const char GLYPHS[] = "ACEFGHILMNORSTUYZ*";
static const u8 FONT[][7] = {
    {0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11}, // A
    {0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E}, // C
    {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F}, // E
    {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10}, // F
    {0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F}, // G
    {0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11}, // H
    {0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E}, // I
    {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F}, // L
    {0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11}, // M
    {0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11}, // N
    {0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E}, // O
    {0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11}, // R
    {0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E}, // S
    {0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04}, // T
    {0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E}, // U
    {0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04}, // Y
    {0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F}, // Z
    {0x00, 0x15, 0x0E, 0x1F, 0x0E, 0x15, 0x00}, // *
};
static const char TEXT[] = "HELLO FROM C * THIS IS YOUR FIRST ZIGMACHINE SCREEN * ";
#define TEXT_LEN (int)(sizeof(TEXT) - 1)
#define SCALE    2  // each font pixel is drawn 2x2
#define ADVANCE  12 // 5 columns x 2, plus a 2-pixel gap

static int glyph_of(char c) {
    for (int g = 0; GLYPHS[g]; g++)
        if (GLYPHS[g] == c) return g;
    return -1;
}

static void draw_char(char c, int x, int y) {
    int g = glyph_of(c);
    if (g < 0) return; // a space, or a letter the font lacks
    for (int row = 0; row < 7; row++)
        for (int col = 0; col < 5; col++) {
            if (!(FONT[g][row] & (0x10 >> col))) continue;
            for (int sy = 0; sy < SCALE; sy++)
                for (int sx = 0; sx < SCALE; sx++) {
                    int px = x + col * SCALE + sx;
                    if (px >= 0 && px < W) vram()[(y + row * SCALE + sy) * W + px] = TEXT_INK;
                }
        }
}

static void draw_scroller(void) {
    for (int i = 0;; i++) {
        int x = i * ADVANCE - scroll_x;
        if (x >= W) break;
        if (x > -ADVANCE) draw_char(TEXT[i % TEXT_LEN], x, 8);
    }
    scroll_x = (scroll_x + 2) % (TEXT_LEN * ADVANCE);
}

// --- the step gate ---------------------------------------------------------
#define LAST_STEP 7
static u32 step = LAST_STEP;
static int restage = 1;

// Everything tutorial.c does in boot(), gated by how far the reader has got.
static void stage(void) {
    if (step >= 7) zm_request_song("sos.sndh"); // step 7: music

    *(u32 *)(video_base + REG_BACKGROUND) = rgba(0, 0, 0);
    if (step < 2) return; // step 1: an empty cart that boots, and nothing else

    u32 *pal = palette(); // step 2: a plane and a palette
    pal[SKY] = rgba(0, 0, 40);
    pal[FLOOR_DARK] = rgba(60, 20, 90);
    pal[FLOOR_LIGHT] = rgba(140, 60, 180);
    pal[BLOCK] = rgba(255, 210, 0);
    pal[TEXT_INK] = rgba(255, 255, 255);

    fill_rect(0, 0, W, H, SKY);
    if (step >= 3) draw_floor(); // step 3: the checkerboard floor

    if (step >= 5) { // step 5: arm plane 0's HBL for the copper bar
        for (int i = 0; i < H; i++) copper[i] = pal[SKY];
        *(u16 *)(video_base + REG_FB_HBL_ID + 0 * 2) = 1;
        *(u16 *)(video_base + REG_FB_HBL_POS + 0 * 2) = 0;
    } else {
        *(u16 *)(video_base + REG_FB_HBL_ID + 0 * 2) = 0; // 0 = no HBL
    }
}

__attribute__((export_name("boot")))
void boot(void) {
    video_base = hwVideoBase();
    block_x = 40; block_y = 40; block_dx = 2; block_dy = 1;
    bar_y = 24; bar_dy = 2;
    scroll_x = 0;
    restage = 1; // stage() runs on the first frame, once the step is known
}

__attribute__((export_name("frame")))
void frame(float dt) {
    (void)dt;
    if (restage) { stage(); restage = 0; }
    if (step < 4) return; // steps 1-3 are static: stage() drew them already

    fill_rect(0, 0, W, FLOOR_Y, SKY); // wipe last frame's sky
    move_block();                     // step 4: the block moves
    fill_rect(block_x, block_y, BLOCK_SIZE, BLOCK_SIZE, BLOCK);
    if (step >= 5) build_copper();
    if (step >= 6) draw_scroller();
}

// Step 1 is a cart that boots and draws nothing, so plane 0 stays off.
__attribute__((export_name("isPlaneEnabled")))
int isPlaneEnabled(int id) { return id == 0 && step >= 2; }

// The machine calls this before it draws each line of plane 0. `line` is the
// LOGICAL line, 0..199, on a normal plane. Only armed from step 5.
__attribute__((export_name("hblDispatch")))
void hblDispatch(u32 id, u32 plane, u32 line, u32 x) {
    (void)id; (void)plane; (void)x;
    palette()[SKY] = copper[line];
}

// The host's ?step=N. Out of range is REFUSED, not clamped: a bad step means a
// broken link on the tutorial page and a silent fallback would hide it.
// Returns whether it was taken, so the loader can warn when a cart has no steps.
__attribute__((export_name("setShadeMode")))
int setShadeMode(u32 m) {
    if (m < 1 || m > LAST_STEP) return 0;
    step = m;
    restage = 1;
    return 1;
}

__attribute__((export_name("skipBoot"))) void skipBoot(void) {}
__attribute__((export_name("pointer")))  void pointer(int x, int y, u32 b) { (void)x; (void)y; (void)b; }
__attribute__((export_name("input")))    void input(u8 dir) { (void)dir; }
