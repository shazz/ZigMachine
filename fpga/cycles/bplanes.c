/* See bplanes.h. */
#include "bplanes.h"

#include <stdio.h>
#include <string.h>

#include "bdiag.h"
#include "bmailbox.h"
#include "bsys.h"
#include "sha256.h"
#include "vboard.h"
#include "vplan.h"
#include "vseq.h"
#include "zm_memmap.h"

#if defined(ZM_BOARD) || defined(ZM_LINEMAJOR)
#define LM_DEFAULT 1
#else
#define LM_DEFAULT 0 /* a sim stays plane-major unless asked: its timings are compared run to run */
#endif

int bplanes_lm(void) { return LM_DEFAULT && !(diag_opt & DIAG_OPT_PLANE_MAJOR); }

/* Plane p is composited: vplan_frame's answer, asked again where video.zig asks (a handler ran). */
static int plane_on(struct w2c_env* e, unsigned on, unsigned p, int handler) {
    int en = (on >> p) & 1;
    if (handler && en != !!HOST_CART_PLANE_ON(e, p)) en = !en, vplan_mask_moved();
    return en;
}

int bplanes_run(struct w2c_env* e, unsigned on, unsigned planes, int handler, int lm, bplanes_hash hash) {
    int first = 1, drop = lm && !(diag_opt & DIAG_OPT_KEEP_PFB);
    for (unsigned p = 0; p < planes; p++) {
        if (!plane_on(e, on, p, handler)) {
            if (hash) hash(p, 0);
            continue;
        }
        if (!lm || vseq_plane_handler((int)p)) {
            vseq_plane(e, (int)p, first);
            first = 0;
            if (hash) hash(p, 1);
            continue;
        }
        /* The run of handler-free planes from p, up to the next handler plane (asked already: no
         * cart code runs between here and its turn, so the answer is the one video.zig gets). */
        unsigned g = 1u << p, q = p + 1;
        int next = -1;
        for (; q < planes; q++) {
            if (!plane_on(e, on, q, handler)) continue;
            if (vseq_plane_handler((int)q)) {
                next = (int)q;
                break;
            }
            g |= 1u << q;
        }
        vseq_group(e, g, first, drop && next < 0); /* nothing above it: the top layer */
        first = 0;
        if (next >= 0) vseq_plane(e, next, 0);
        p = q;
    }
    return first;
}

#ifdef ZM_LM_CHECK
#define PIC_BYTES (ZM_RASTER_WIDTH * ZM_RASTER_HEIGHT * 4u)
static char g_lm[65];
static int g_checking;
static uint32_t g_same, g_differ;

static void pic_hash(char out[65]) {
    vseq_idle();
    zmv_flush_dcache(); /* the compositor wrote the picture behind the D$ */
    uint32_t back = (zmv_status() & ZMV_BIT(FRONT)) ? ZM_FB0_ADDR : ZM_FB1_ADDR;
    sha256_ctx h;
    sha256_init(&h);
    sha256_update(&h, (const void*)(uintptr_t)back, PIC_BYTES);
    sha256_hex(&h, out);
}

void bplanes_check_pre(struct w2c_env* e, unsigned on, unsigned planes, int handler) {
    g_checking = 0;
    for (unsigned p = 0; p < planes; p++)
        if (((on >> p) & 1) && vseq_plane_handler((int)p)) return; /* a handler cannot run twice */
    if (!vseq_fill() || !on) return; /* the first layer must not load the PFB: the check rewrites it */
    const uint8_t* skip = vseq_skip;
    int (*decide)(int) = vseq_decide;
    vseq_skip = NULL, vseq_decide = NULL; /* every line, and the plan asked only by the real composite */
    bplanes_run(e, on, planes, handler, 1, NULL);
    vseq_skip = skip, vseq_decide = decide;
    pic_hash(g_lm);
    g_checking = 1;
}

void bplanes_check_post(long f) {
    if (!g_checking) return;
    char pm[65];
    pic_hash(pm);
    int same = !strcmp(pm, g_lm);
    g_same += same, g_differ += !same;
    printf("ZM LMCHK %ld %s\n", f, same ? "same" : "DIFFER");
}

void bplanes_report(void) { printf("ZM LMCHK total %lu %lu\n", (unsigned long)g_same, (unsigned long)g_differ); }
#else
void bplanes_check_pre(struct w2c_env* e, unsigned on, unsigned planes, int handler) {
    (void)e, (void)on, (void)planes, (void)handler;
}
void bplanes_check_post(long f) { (void)f; }
void bplanes_report(void) {}
#endif
