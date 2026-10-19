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
 * The model to test: ~1.09 Mc a plane, all of it ZIGGY waiting on the compositor. */
#include "bench.h"

#define WARM 3    /* frames after a change of planes before sampling (a picture is 2 frames old) */
#define SAMPLES 8 /* frames sampled per setting */

static const char* const NAMES[2][5] = {
    {"fr.static.p0", "fr.static.p1", "fr.static.p2", "fr.static.p3", "fr.static.p4"},
    {"fr.dirty.p0", "fr.dirty.p1", "fr.dirty.p2", "fr.dirty.p3", "fr.dirty.p4"},
};

static struct {
    int dirty, planes, n; /* the setting, and frames into it */
    uint32_t t_exit, poke;
    uint32_t s[SAMPLES], vbls[SAMPLES];
} st;

uint32_t planes_mask(void) { return (1u << st.planes) - 1u; }

/* A byte in each of a plane's 200 rows, at its own FB_BASE and stride. */
static void touch(int p) {
    uint32_t base = *(volatile uint32_t*)(g.vreg + ZM_REG_FB_BASE + 4u * (uint32_t)p);
    uint32_t stride = *(volatile uint16_t*)(g.vreg + ZM_REG_FB_STRIDE + 2u * (uint32_t)p);
    for (uint32_t y = 0; y < ZM_HEIGHT; y++) g.vreg[base + y * stride + (st.poke & 7u)] = (uint8_t)st.poke;
}

static void wait_vbl(void) {
    uint32_t v = bench_vbls();
    while (bench_vbls() == v) {
    }
}

/* The next setting: static 0..4 planes, then dirty 1..4. 0 when every one is done. */
static int advance(void) {
    bench_record(NAMES[st.dirty][st.planes], 0, 1, st.s, SAMPLES);
    uint32_t most = 0;
    for (int i = 0; i < SAMPLES; i++) most = st.vbls[i] > most ? st.vbls[i] : most;
    if (most) { /* the system's share outlasted a frame: the setting runs below 60 fps */
        char b[64], *p = fmt_str(b, "ZMBENCH-INFO ");
        p = fmt_str(p, NAMES[st.dirty][st.planes]);
        p = fmt_str(p, " vbls=");
        p = fmt_u32(p, most);
        *p = 0;
        log_text(b);
    }
    st.n = 0;
    if (++st.planes <= 4) return 1;
    if (st.dirty) return 0;
    st.dirty = 1, st.planes = 1;
    return 1;
}

/* Called first thing in frame() while the test runs; 1 while it needs more frames. */
int planes_frame(void) {
    uint32_t now = bench_cycles(), vbl = bench_vbls();
    static uint32_t vbl_exit;
    if (st.n >= WARM && st.n < WARM + SAMPLES) {
        st.s[st.n - WARM] = now - st.t_exit;
        st.vbls[st.n - WARM] = vbl - vbl_exit;
    }
    if (++st.n > WARM + SAMPLES && !advance()) return 0;
    st.poke++;
    if (st.dirty)
        for (int p = 0; p < st.planes; p++) touch(p);
    wait_vbl();
    st.t_exit = bench_cycles();
    vbl_exit = bench_vbls();
    return 1;
}
