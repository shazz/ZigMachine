/* vsynth's host: machine-video alone (vsynth.h), driven like fpga/host/main.c's
 * frame loop and recorded by vdump_rec.c, so its dumps replay like a cart's.
 *
 *   vsynth <outdir> <scenario>      writes <outdir>/f1.* .. f<frames>.* */
#include <stdio.h>
#include <string.h>

#include "machine.h"
#include "vdump.h"
#include "vsynth.h"
#include "wasm-rt-exceptions.h"
#include "wasm-rt-impl.h"

/* The whole environment of a cart-less machine: memory, and the HBL route. */
struct w2c_env {
    wasm_rt_memory_t memory;
    w2c_machine machine;
};

static struct w2c_env g_env;
static const vs_scenario* g_sc;
uint8_t* vs_region;

wasm_rt_memory_t* w2c_env_memory(struct w2c_env* e) { return &e->memory; }

void w2c_env_hblDispatch(struct w2c_env* e, u32 id, u32 plane, u32 line, u32 x) {
    (void)x;
    vd_hbl(&e->memory, VD_PRE, line);
    g_sc->hbl(id, plane, line);
    vd_hbl(&e->memory, VD_POST, line);
}

void vs_w8(uint32_t off, uint32_t v) { vs_region[off] = (uint8_t)v; }
void vs_w16(uint32_t off, uint32_t v) { vs_w8(off, v), vs_w8(off + 1, v >> 8); }
void vs_w32(uint32_t off, uint32_t v) { vs_w16(off, v), vs_w16(off + 2, v >> 16); }
uint32_t vs_r16(uint32_t off) { return vs_region[off] | (uint32_t)vs_region[off + 1] << 8; }

uint32_t vs_rnd(void) {
    static uint32_t s = 0x2545F491u;
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    return s;
}

void vs_fill(uint32_t off, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) vs_region[off + i] = (uint8_t)vs_rnd();
}

void vs_palette(int plane) {
    for (uint32_t i = 0; i < ZM_PAL_ENTRIES; i++)
        vs_w32(ZM_OFF_PAL + (uint32_t)plane * ZM_PAL_BYTES + i * 4, 0xFF000000u | (vs_rnd() & 0xFFFFFFu));
}

void vs_plane(int p, int mode, int stride, uint32_t base, int hpos) {
    vs_w8(ZM_REG_FB_MODE + (uint32_t)p, (uint32_t)mode);
    vs_w16(ZM_REG_FB_STRIDE + (uint32_t)p * 2, (uint32_t)stride);
    vs_w32(ZM_REG_FB_BASE + (uint32_t)p * 4, base);
    vs_w16(ZM_REG_FB_HBL_ID + (uint32_t)p * 2, (uint32_t)p + 1);
    vs_w16(ZM_REG_FB_HBL_POS + (uint32_t)p * 2, (uint32_t)hpos);
}

/* One frame: fpga/host/main.c's order, the scenario standing in for the cart. */
static void frame(const char* dir, int f) {
    wasm_rt_memory_t* m = &g_env.memory;
    vd_begin(m, dir, f);
    vd_pass_start(m, 0);
    w2c_machine_hwClear(&g_env.machine);
    vd_pass_end(m);
    vd_dump_pfb(m);
    g_sc->frame(f);
    vd_dump_mem(m);
    for (uint32_t p = 0; p < ZM_NB_PLANES; p++) {
        if (!((g_sc->planes >> p) & 1)) continue;
        vd_pass_start(m, p + 1);
        w2c_machine_hwRenderPlane(&g_env.machine, p);
        vd_pass_end(m);
        vd_dump_pfb(m);
    }
    vd_end(m, g_sc->planes);
}

int main(int argc, char** argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: vsynth <outdir> <scenario>\n");
        return 2;
    }
    for (g_sc = vs_scenarios; g_sc->name && strcmp(g_sc->name, argv[2]); g_sc++) {}
    if (!g_sc->name) {
        fprintf(stderr, "vsynth: no scenario %s\n", argv[2]);
        return 2;
    }
    wasm_rt_init();
    if (wasm_rt_impl_try()) {
        fprintf(stderr, "vsynth: %s: the machine trapped\n", argv[2]);
        return 1;
    }
    wasm_rt_allocate_memory(&g_env.memory, ZM_SHARED_PAGES, ZM_SHARED_PAGES, false, WASM_DEFAULT_PAGE_SIZE);
    wasm2c_machine_instantiate(&g_env.machine, &g_env);
    w2c_machine_hwInit(&g_env.machine);
    vs_region = g_env.memory.data + ZM_HW_VIDEO_BASE;
    g_sc->setup();
    for (int f = 1; f <= g_sc->frames; f++) frame(argv[1], f);
    return 0;
}
