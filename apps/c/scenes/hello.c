// ---------------------------------------------------------------------------
// ZigMachine "hello world" — written in C, compiled to a sealed-machine app.
//
// Proof that apps are language-agnostic: this talks to the SAME sealed
// machine-video.wasm as the Zig demo, over the SAME memory-mapped ABI
// (hw/sdk/memmap.zig). It imports exactly two machine functions and writes
// 8-bit palette indices straight into the shared video region.
//
// Build: see apps/c/build.sh  (zig cc, bundled lld). Output: docs/demo-c.wasm
// Run:   docs/sealed.html?demo=demo-c.wasm
// ---------------------------------------------------------------------------

// --- ABI geometry (mirror of hw/sdk/memmap.zig; the console's identity) ---
#define OFF_REG          0x0000
#define REG_BACKGROUND   0x04      // u32 RGBA border/background
#define OFF_PAL          0x0100    // palette 0: 256 x RGBA u32
#define OFF_VRAM         0x1100    // plane 0 framebuffer (reset FB_BASE)
#define WIDTH            320
#define HEIGHT           200

typedef unsigned char  u8;
typedef unsigned int   u32;

// --- imports resolved by the loader against the machine / JS "env" module ---
__attribute__((import_module("env"), import_name("hwVideoBase")))
extern int hwVideoBase(void);
__attribute__((import_module("env"), import_name("consoleLogJS")))
extern void consoleLogJS(const char *ptr, int len);

// --- the ROM chip: GEM, called from C (rom/sdk/rom.zig) ---
//
// This is the claim the machine/rom split rests on — that a ROM is a module
// linked against the HW ABI, so ANY language can call it. Nothing but numbers
// crosses: a u32 handle, coordinates, a (pointer, length) for text.
//
// guiOpenPlane is what makes that true. The Zig entry point, guiOpen, wants the
// addresses of the caller's ZigOS and LogicalFB — which quietly requires the
// caller to BE a Zig program. C has neither, so it names a PLANE instead and the
// ROM reads that plane's framebuffer out of the video registers itself.
#define ROM_IMPORT(name) __attribute__((import_module("env"), import_name(name)))
ROM_IMPORT("guiOpenPlane") extern unsigned guiOpenPlane(unsigned plane, int w, int h);
ROM_IMPORT("romInstallPalettePlane") extern void romInstallPalettePlane(unsigned plane);
ROM_IMPORT("guiRect")  extern void guiRect(unsigned h, int x, int y, int w, int hh, unsigned color);
ROM_IMPORT("guiFrame") extern void guiFrame(unsigned h, int x, int y, int w, int hh, unsigned color);
ROM_IMPORT("guiText")  extern void guiText(unsigned h, const char *p, unsigned len,
                                           int x, int y, unsigned ink, unsigned paper);

#define GEM_BLACK 0
#define GEM_WHITE 1

static unsigned gui = 0;           // the ROM handle; 0 = no context

static int   video_base = 0;       // base of the shared video hardware region
static u8    tri[256];             // triangle-wave LUT (a libm-free "sine")
static u8    plane0_on = 0;
static u32   frame_counter = 0;

static inline u8 *reg(void)  { return (u8 *)(video_base + OFF_REG); }
static inline u8 *pal(void)  { return (u8 *)(video_base + OFF_PAL); }
static inline u8 *vram(void) { return (u8 *)(video_base + OFF_VRAM); }

// HSV(h, 1, 1) -> RGB, integer sextant method. Fills palette 0 with a rainbow so
// scrolling the index produces moving colour bands.
static void build_rainbow(void) {
    u8 *p = pal();
    for (int i = 0; i < 256; i++) {
        int seg = i / 43;                 // 0..5
        int rem = (i - seg * 43) * 6;     // 0..~255
        int q = 255 - rem, t = rem;
        int r = 0, g = 0, b = 0;
        switch (seg) {
            case 0: r = 255; g = t;   b = 0;   break;
            case 1: r = q;   g = 255; b = 0;   break;
            case 2: r = 0;   g = 255; b = t;   break;
            case 3: r = 0;   g = q;   b = 255; break;
            case 4: r = t;   g = 0;   b = 255; break;
            default:r = 255; g = 0;   b = q;   break;
        }
        p[i * 4 + 0] = (u8)r;
        p[i * 4 + 1] = (u8)g;
        p[i * 4 + 2] = (u8)b;
        p[i * 4 + 3] = 255;               // ALPHA 255 = opaque (else invisible)
    }
}

__attribute__((export_name("boot")))
void boot(void) {
    const char msg[] = "Hello, world - from C on ZigMachine!";
    consoleLogJS(msg, (int)sizeof(msg) - 1);

    video_base = hwVideoBase();
    *(u32 *)(reg() + REG_BACKGROUND) = 0xFF000000u;   // opaque black border
    build_rainbow();
    for (int i = 0; i < 256; i++) tri[i] = (u8)(i < 128 ? i * 2 : (255 - i) * 2);
    plane0_on = 1;                                     // enable plane 0

    // Ask the ROM for a drawing context over plane 0. From here on this C program
    // draws GEM widgets with the same toolkit the Zig desktop uses, in the same
    // binary, over the shared memory — no ZigOS, no Zig, just the flat ABI.
    gui = guiOpenPlane(0, WIDTH, HEIGHT);
    if (gui) {
        // GEM draws in PALETTE INDICES (0 = black, 1 = white), so a caller with
        // its own palette gets correct pixels in the wrong colours — this app's
        // rainbow renders the whole panel solid red. Let the ROM install GEM's
        // entries. It only writes the ones GEM owns, so the plasma keeps the rest.
        romInstallPalettePlane(0);
        const char ok[] = "C app opened a GEM context from the ROM chip";
        consoleLogJS(ok, (int)sizeof(ok) - 1);
    } else {
        const char bad[] = "C app could NOT open a GEM context";
        consoleLogJS(bad, (int)sizeof(bad) - 1);
    }
}

// A GEM panel drawn BY THE ROM, on top of the plasma this program rendered
// itself. Everything inside comes from rom.wasm: the fills, the double border
// GEM draws round a panel, and the 8x8 system font.
static void draw_rom_panel(void) {
    if (!gui) return;
    const char title[] = "GEM FROM C";
    const char line1[] = "rom.wasm drew this panel";
    const char line2[] = "and this text, for a C app";
    const int x = 40, y = 68, w = 240, h = 64;

    guiRect(gui, x, y, w, h, GEM_WHITE);                 // panel face
    guiFrame(gui, x, y, w, h, GEM_BLACK);                // GEM's double border
    guiFrame(gui, x + 1, y + 1, w - 2, h - 2, GEM_BLACK);
    guiRect(gui, x + 3, y + 3, w - 6, 10, GEM_BLACK);    // title bar, inverse
    guiText(gui, title, sizeof(title) - 1, x + 8, y + 4, GEM_WHITE, GEM_BLACK);
    guiText(gui, line1, sizeof(line1) - 1, x + 8, y + 22, GEM_BLACK, GEM_WHITE);
    guiText(gui, line2, sizeof(line2) - 1, x + 8, y + 34, GEM_BLACK, GEM_WHITE);
}

__attribute__((export_name("frame")))
void frame(float elapsed_ms) {
    (void)elapsed_ms;
    frame_counter++;
    u32 t = frame_counter;
    u8 *fb = vram();
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            int v = tri[(x + t) & 255]
                  + tri[(y * 2 + t) & 255]
                  + tri[(x + y + 2 * t) & 255];
            fb[y * WIDTH + x] = (u8)((v >> 2) & 255);  // plasma -> palette index
        }
    }
    draw_rom_panel(); // ...then let the ROM draw GEM over the top
}

// The host gates blits on this — plane 0 only.
__attribute__((export_name("isPlaneEnabled")))
int isPlaneEnabled(int id) { return id == 0 ? plane0_on : 0; }

// Optional ABI surface — no-op stubs so a keypress/HBL never hits a missing export.
__attribute__((export_name("hblDispatch")))
void hblDispatch(u32 id, u32 plane, u32 line, u32 x) { (void)id;(void)plane;(void)line;(void)x; }
__attribute__((export_name("skipBoot")))    void skipBoot(void) {}
__attribute__((export_name("setShadeMode"))) void setShadeMode(u32 m) { (void)m; }
__attribute__((export_name("pointer")))     void pointer(int x, int y, u32 b) { (void)x;(void)y;(void)b; }
__attribute__((export_name("input")))       void input(u8 dir) { (void)dir; }
