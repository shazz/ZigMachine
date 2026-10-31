/* Test 9: what the system spends on a frame outside the cart, with 0..4 planes enabled.
 *
 * bmain.c's frame: binput, cart.frame(), the audio bridge, then the video (vplan.c's dirty-line
 * plan, vseq.c's passes: ZIGGY issues each line's command and spins on FRESCO's READY, DRAINED
 * and PAINTED), then PRESENT, and back to cart.frame(). This cart leaves frame() right after a
 * VBL (it spins on FRESCO's VBL counter first), so the previous picture has already swapped and
 * the sequencer never waits for the swap: the cycles from leaving frame() to entering the next
 * are the system's work alone, and the vbl count says if it fit in a frame.
 *
 *   fr.static.pN   planes 0..N-1 on and unchanged: vplan compares their rows and skips them
 *   fr.dirty.pN    one byte of every row of each enabled plane changed every frame: every line
 *                  is composited again, as on a cart that animates its whole plane
 *   fr.ilv.pN      fr.dirty with the N planes LINE-INTERLEAVED (fpga/review/PLANE_INTERLEAVE.md):
 *                  plane p's row y at BENCH_VRAM_OFF + (y * N + p) * 320, stride N * 320, so a
 *                  line's N fetches read one contiguous run of DDR. Same passes, same bytes.
 * Each setting logs three figures: the frame's system cycles (sys), `.comp` FRESCO's COMP_BUSY
 * (comp clocks a pass ran) and `.dma` the video DMA's DMA_BUSY (sys clocks a burst was active,
 * the scanout's included) over the same window. Per added plane of a line-major group, comp
 * minus the RTL's paint + mix is the fetch's own cost; sys minus comp is the sequencer's. */
#include "bench.h"

#define WARM 3    /* frames after a change of planes before sampling (a picture is 2 frames old) */
#define SAMPLES 8 /* frames sampled per setting */
#define ROW 320u  /* a normal plane's row */

enum { K_STATIC, K_DIRTY, K_ILV, K_N };
#define SETTING_NAMES(s) {"fr." s ".p0" SFX, "fr." s ".p1" SFX, "fr." s ".p2" SFX, "fr." s ".p3" SFX, "fr." s ".p4" SFX}
#define SFX ""
static const char* const NAMES[K_N][5] = {SETTING_NAMES("static"), SETTING_NAMES("dirty"), SETTING_NAMES("ilv")};
#undef SFX
#define SFX ".comp"
static const char* const CNAMES[K_N][5] = {SETTING_NAMES("static"), SETTING_NAMES("dirty"), SETTING_NAMES("ilv")};
#undef SFX
#define SFX ".dma"
static const char* const DNAMES[K_N][5] = {SETTING_NAMES("static"), SETTING_NAMES("dirty"), SETTING_NAMES("ilv")};
#undef SFX

static struct {
    int kind, planes, n; /* the setting, and frames into it */
    uint32_t t_exit, c_exit, d_exit, vbl_exit, poke;
    uint32_t s[SAMPLES], c[SAMPLES], d[SAMPLES], vbls[SAMPLES];
    uint32_t base[ZM_NB_PLANES];   /* the planes' FB_BASE before fr.ilv, put back after */
    uint16_t stride[ZM_NB_PLANES];
} st;

static inline uint32_t comp_busy(void) { return *(volatile uint32_t*)NATIVE_CSR_ZMV_COMP_BUSY; }
static inline uint32_t dma_busy(void) { return *(volatile uint32_t*)NATIVE_CSR_ZMV_DMA_BUSY; }
static inline volatile uint32_t* fb_base(int p) { return (volatile uint32_t*)(g.vreg + ZM_REG_FB_BASE + 4u * (uint32_t)p); }
static inline volatile uint16_t* fb_stride(int p) { return (volatile uint16_t*)(g.vreg + ZM_REG_FB_STRIDE + 2u * (uint32_t)p); }

uint32_t planes_mask(void) { return (1u << st.planes) - 1u; }

/* A byte in each of a plane's 200 rows, at its own FB_BASE and stride. */
static void touch(int p) {
    uint32_t base = *fb_base(p), stride = *fb_stride(p);
    for (uint32_t y = 0; y < ZM_HEIGHT; y++) g.vreg[base + y * stride + (st.poke & 7u)] = (uint8_t)st.poke;
}

/* fr.ilv's layout for planes 0..n-1 (4 x 64000 bytes fit below BENCH_BLIT_OFF); n = 0 puts back
 * the bases and strides saved when fr.ilv began (plane 0 is the ROM's results page). */
static void interleave(int n) {
    for (int p = 0; p < (int)ZM_NB_PLANES; p++) {
        if (n == 0) *fb_base(p) = st.base[p], *fb_stride(p) = st.stride[p];
        else if (p < n) *fb_base(p) = BENCH_VRAM_OFF + (uint32_t)p * ROW, *fb_stride(p) = (uint16_t)((uint32_t)n * ROW);
    }
}
_Static_assert(BENCH_VRAM_OFF + ZM_NB_PLANES * ROW * ZM_HEIGHT <= BENCH_BLIT_OFF, "fr.ilv's planes fit");

static void wait_vbl(void) {
    uint32_t v = bench_vbls();
    while (bench_vbls() == v) {
    }
}

static void record(void) {
    bench_record(NAMES[st.kind][st.planes], 0, 1, st.s, SAMPLES);
    bench_record(CNAMES[st.kind][st.planes], 0, 1, st.c, SAMPLES);
    bench_record(DNAMES[st.kind][st.planes], 0, 1, st.d, SAMPLES);
    uint32_t most = 0;
    for (int i = 0; i < SAMPLES; i++) most = st.vbls[i] > most ? st.vbls[i] : most;
    if (most) { /* the system's share outlasted a frame: the setting runs below 60 fps */
        char b[64], *p = fmt_str(b, "ZMBENCH-INFO ");
        p = fmt_str(p, NAMES[st.kind][st.planes]);
        p = fmt_str(p, " vbls=");
        p = fmt_u32(p, most);
        *p = 0;
        log_text(b);
    }
}

/* The next setting: static 0..4 planes, dirty 1..4, ilv 2..4. 0 when every one is done. */
static int advance(void) {
    record();
    st.n = 0;
    if (++st.planes <= 4) {
        if (st.kind == K_ILV) interleave(st.planes);
        return 1;
    }
    if (st.kind == K_ILV) {
        interleave(0);
        return 0;
    }
    st.kind++, st.planes = st.kind == K_ILV ? 2 : 1;
    if (st.kind == K_ILV) {
        for (int p = 0; p < (int)ZM_NB_PLANES; p++) st.base[p] = *fb_base(p), st.stride[p] = *fb_stride(p);
        interleave(st.planes);
    }
    return 1;
}

/* Called first thing in frame() while the test runs; 1 while it needs more frames. */
int planes_frame(void) {
    uint32_t now = bench_cycles(), comp = comp_busy(), dma = dma_busy(), vbl = bench_vbls();
    if (st.n >= WARM && st.n < WARM + SAMPLES) {
        int i = st.n - WARM;
        st.s[i] = now - st.t_exit, st.c[i] = comp - st.c_exit, st.d[i] = dma - st.d_exit;
        st.vbls[i] = vbl - st.vbl_exit;
    }
    if (++st.n > WARM + SAMPLES && !advance()) return 0;
    st.poke++;
    if (st.kind != K_STATIC)
        for (int p = 0; p < st.planes; p++) touch(p);
    wait_vbl();
    st.t_exit = bench_cycles(), st.c_exit = comp_busy(), st.d_exit = dma_busy(), st.vbl_exit = bench_vbls();
    return 1;
}
