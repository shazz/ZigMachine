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
