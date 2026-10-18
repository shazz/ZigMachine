/* The dirty-line proof (cycles/vdirty.h), native: the host's frame loop
 * (host/main.c, scene_hash.mjs's), with the board's double-buffered picture
 * beside it. Every frame:
 *   - the reference: the PFB after each enabled plane, folded over the tube as
 *     the board's mixer folds it (rtl/video/zm_video_mix.v), every line;
 *   - the board's: the picture of this frame's parity, where only the lines the
 *     planner did not skip are copied from the reference;
 *   - the two compared, whole: a skipped row that a full composite would have
 *     painted differently is a MISMATCH.
 * The planner sees what the board's sequencer sees (vplan.c): the background
 * after the global handler (the span hooks, host/vdirty_spans.h), the planes
 * asked once before the first is composited (again in video.zig's place when a
 * plane has a handler), the region after cart.frame().
 * ZM_VD_CURSOR=1 draws over 16 rows of each picture after the compare, as
 * cycles/bcursor.c does, and reports them (vd_overdrawn).
 *
 *   host_vdirty <cart> [frames=600] [--call F:export:args] [--disk X.zmd]
 * prints "VDIRTY <cart> frames F lines L skipped S unknown U moved V mismatched M", exit 1 if M. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "boot.h"
#include "host_io.h"
#include "vdirty.h"
#include "vdirty_spans.h"
#include "wasm-rt-exceptions.h"
#include "wasm-rt-impl.h"

#define W ZM_RASTER_WIDTH
#define RB (W * 4u)

static struct w2c_env g_env;
static uint32_t g_ref[VD_LINES][W], g_pic[2][VD_LINES][W];
static uint32_t g_bg[VD_LINES];
static uint8_t g_beam[VD_LINES], g_skip[VD_LINES];
static int g_clear_line = -1, g_span[64], g_depth;

static uint8_t* region(void) { return g_env.memory.data + ZM_HW_VIDEO_BASE; }
static uint32_t r16(uint32_t o) { return region()[o] | region()[o + 1] << 8; }
static uint32_t r32(uint32_t o) { return r16(o) | r16(o + 2) << 16; }

/* The global handler of line g_clear_line returned: what the BG pass reads. */
void vdh_span_enter(int kind) { g_span[g_depth++ & 63] = kind; }
void vdh_span_leave(void) {
    int kind = g_span[--g_depth & 63];
    if (kind != HOST_SPAN_CART || g_clear_line < 0 || g_clear_line >= (int)VD_LINES) return;
    g_bg[g_clear_line] = r32(ZM_REG_BACKGROUND);
    g_beam[g_clear_line++] = r16(ZM_REG_BEAM_COUNT) != 0;
}

/* hwClear, recording what vseq_clear records. */
static int clear(void) {
    uint32_t gid = r16(ZM_REG_GLOBAL_HBL_ID), bc = r16(ZM_REG_BEAM_COUNT);
    memset(g_beam, 0, sizeof g_beam);
    g_bg[0] = r32(ZM_REG_BACKGROUND), g_beam[0] = bc != 0;
    g_clear_line = gid ? 0 : -1;
    w2c_machine_hwClear(&g_env.machine);
    g_clear_line = -1;
    if (!gid) /* no handler: line 0 consumed the BEAM writes, every later line has its carry */
        for (uint32_t y = 1; y < VD_LINES; y++) g_bg[y] = r32(ZM_REG_BACKGROUND);
    return !gid && !bc;
}

/* zm_video_mix.v, one canvas over the picture: P = round(c a / 255), D = P + (D (256 - a) >> 8). */
static void fold(int first) {
    const uint8_t* pfb = g_env.memory.data + w2c_machine_hwPhysicalPtr(&g_env.machine);
    for (uint32_t i = 0; i < VD_LINES * W; i++) {
        const uint8_t* c = pfb + 4 * i;
        uint32_t a = c[3], d = first ? 0x101012u : (&g_ref[0][0])[i], o = 0;
        for (int k = 0; k < 3; k++) {
            uint32_t r = c[k] * a + 128, p = (r + (r >> 8)) >> 8;
            uint32_t ov = ((d >> (8 * k)) & 255) * (256 - a);
            o |= ((p + (ov >> 8)) & 255) << (8 * k);
        }
        (&g_ref[0][0])[i] = o;
    }
}

/* One frame; returns the rows of the board's picture that differ from the reference. */
static uint32_t frame(long f, u32 planes, uint32_t* composited) {
    struct w2c_env* e = &g_env;
    int fill = clear(), pic = (int)(f & 1);
    w2c_cart_frame(&e->cart, 16.6f);
    host_io_disk_frame(e, f);
    unsigned on = 0;
    for (u32 p = 0; p < planes; p++) on |= w2c_cart_isPlaneEnabled(&e->cart, p) ? 1u << p : 0u;
    vd_frame fr = {e->memory.data, (uint32_t)e->memory.size, on, fill, g_bg, g_beam};
    if (f == 10 && getenv("ZM_VD_INFO")) /* why a cart's frames are UNKNOWN */
        for (u32 p = 0; p < planes; p++)
            fprintf(stderr, "vdirty: plane %u on %u hbl %u mode %u stride %u\n", (unsigned)p, (on >> p) & 1,
                    (unsigned)r16(ZM_REG_FB_HBL_ID + 2 * p), region()[ZM_REG_FB_MODE + p], (unsigned)r16(ZM_REG_FB_STRIDE + 2 * p));
    int handler = vd_plan(&fr);
    *composited = (uint32_t)vd_target(pic, g_skip);
    int first = 1;
    for (u32 p = 0; p < planes; p++) {
        int en = (on >> p) & 1;
        if (handler && en != !!w2c_cart_isPlaneEnabled(&e->cart, p)) en = !en, vd_mask_moved();
        if (!en) continue;
        w2c_machine_hwRenderPlane(&e->machine, p);
        fold(first);
        first = 0;
    }
    if (first) fold(1);
    uint32_t bad = 0;
    for (uint32_t y = 0; y < VD_LINES; y++) {
        if (!g_skip[y]) memcpy(g_pic[pic][y], g_ref[y], RB);
        else if (memcmp(g_pic[pic][y], g_ref[y], RB) && bad++ < 4) fprintf(stderr, "vdirty: frame %ld row %u differs\n", f, (unsigned)y);
    }
    const char* cur = getenv("ZM_VD_CURSOR");
    if (cur && *cur == '1') { /* bcursor.c: 16 rows drawn over, somewhere new each frame */
        uint32_t y0 = (uint32_t)(f * 37) % (VD_LINES - 16);
        for (uint32_t y = y0; y < y0 + 16; y++) g_pic[pic][y][(f * 13 + y) % W] ^= 0x00FFFFFFu;
        vd_overdrawn(pic, y0, 16);
    }
    return bad;
}

int main(int argc, char** argv) {
    const char* pos[2] = {NULL, "600"};
    int npos = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--call") == 0 && i + 1 < argc) host_io_parse_call(argv[++i]);
        else if (strcmp(argv[i], "--disk") == 0 && i + 1 < argc) host_io_mount_disk(argv[++i]);
        else if (npos < 2) pos[npos++] = argv[i];
    }
    if (!pos[0]) { fprintf(stderr, "usage: host_vdirty <cart> [frames] [--call F:name:args] [--disk X.zmd]\n"); return 2; }
    long n = strtol(pos[1], NULL, 10);
    wasm_rt_init();
    wasm_rt_trap_t trap = wasm_rt_impl_try();
    if (trap) { fprintf(stderr, "host_vdirty: %s: trap: %s\n", pos[0], wasm_rt_strerror(trap)); return 1; }
    host_boot(&g_env);
    u32 planes = w2c_machine_hwPlanesNumber(&g_env.machine);
    uint64_t lines = 0, comp = 0, bad = 0;
    for (long f = 1; f <= n; f++) {
        host_io_run_calls(&g_env, f);
        uint32_t c = 0;
        bad += frame(f, planes, &c);
        lines += VD_LINES, comp += c;
    }
    printf("VDIRTY %s frames %ld lines %llu skipped %llu unknown %u moved %u mismatched %llu\n", pos[0], n,
           (unsigned long long)lines, (unsigned long long)(lines - comp), (unsigned)vd.unknown, (unsigned)vd.mask_moved,
           (unsigned long long)bad);
    return bad != 0;
}
