/* The video integration firmware (soc/video_sim.py): cycles/main.c's boot and
 * frame loop, with the machine's video done by the RTL compositor under the
 * sequencer (vseq.h) instead of hwClear/hwRenderPlane. The PFB the compositor
 * writes back into the region after each enabled plane is hashed as
 * apps/scene_hash.mjs hashes the machine's, so the two compare directly.
 *
 *   ZM_FRAMES, ZM_EVERY, ZM_CART   as main.c
 *
 * Lines: "ZM BOOT c", per frame "ZM VF f cart mach blit idle swapwait compbusy
 * dmabusy cpu_rd cpu_wr dma_rd dma_wr both" (cycles, and main RAM beats since
 * the frame began: tools/video_sim_run.py), the scene_hash JSON, "ZM VSTAT
 * underrun overflow swaps vbls undrained", "ZM MIS ...", "ZM END rc". */
#include <stdio.h>
#include <stdlib.h>

#include "boot.h"
#include "prof.h"
#include "sha256.h"
#include "trap.h"
#include "vboard.h"
#include "vseq.h"
#include "wasm-rt-exceptions.h"
#include "zm_memmap.h"
#include "wasm-rt-impl.h"

#define PICTURE_BYTES (ZM_RASTER_WIDTH * ZM_RASTER_HEIGHT * 4u)

static struct w2c_env g_env;
static char g_hashes[ZM_FRAMES / ZM_EVERY + 1][65];

typedef struct {
    uint32_t ram[ZMV_NRAM], comp, dma, swap;
} snap;

static void take(snap* s) {
    zmv_ram_counters(s->ram);
    s->comp = ZMV_REG(COMP_BUSY);
    s->dma = ZMV_REG(DMA_BUSY);
    s->swap = vseq.swap_wait;
}

static void print_frame(long f, const snap* a, const snap* b) {
    printf("ZM VF %ld", f);
    for (int o = PROF_CART; o <= PROF_BLIT; o++) printf(" %lu", (unsigned long)prof[o].c[0]);
    printf(" %lu %lu %lu %lu", (unsigned long)prof[PROF_IDLE].c[0], (unsigned long)(b->swap - a->swap),
           (unsigned long)(b->comp - a->comp), (unsigned long)(b->dma - a->dma));
    for (int i = 0; i < ZMV_NRAM; i++) printf(" %lu", (unsigned long)(b->ram[i] - a->ram[i]));
    printf("\n");
}

/* The PFB after the plane's last row reached memory, past the CPU's stale cache. */
static void hash_pfb(sha256_ctx* h, u32 size) {
    vseq_idle();
    zmv_flush_dcache();
    sha256_update(h, g_env.memory.data + w2c_machine_hwPhysicalPtr(&g_env.machine), size);
}

static void plane(sha256_ctx* h, u32 p, int* first, u32 size) {
    struct w2c_env* e = &g_env;
    if (!w2c_cart_isPlaneEnabled(&e->cart, p)) {
        char off[16];
        if (h) sha256_update(h, off, (size_t)snprintf(off, sizeof off, "off%u", (unsigned)p));
        return;
    }
    prof_enter(PROF_MACH);
    vseq_plane(e, (int)p, *first);
    prof_leave();
    *first = 0;
    if (h) hash_pfb(h, size);
}

#ifdef ZM_LINE_MAJOR
/* The mutant order; the PFB is hashed once per enabled plane, after the frame. */
static void frame(sha256_ctx* h, u32 planes, u32 size) {
    struct w2c_env* e = &g_env;
    w2c_cart_frame(&e->cart, 16.6f);
    unsigned mask = 0;
    for (u32 p = 0; p < planes; p++) mask |= w2c_cart_isPlaneEnabled(&e->cart, p) ? 1u << p : 0u;
    if (!mask) return; /* the mutant needs a plane: the run reports the hash it got */
    vseq_line_major(e, mask);
    for (u32 p = 0; p < planes && h; p++) {
        char off[16];
        if ((mask >> p) & 1) hash_pfb(h, size);
        else sha256_update(h, off, (size_t)snprintf(off, sizeof off, "off%u", (unsigned)p));
    }
    vseq_present();
}
#else
static void frame(sha256_ctx* h, u32 planes, u32 size) {
    struct w2c_env* e = &g_env;
    prof_enter(PROF_MACH);
    vseq_clear(e);
    prof_leave();
    prof_enter(PROF_CART);
    w2c_cart_frame(&e->cart, 16.6f);
    prof_leave();
    int first = 1;
    for (u32 p = 0; p < planes; p++) plane(h, p, &first, size);
    prof_enter(PROF_MACH);
    if (first) vseq_mix_only();
    vseq_present();
    prof_leave();
}
#endif

static void print_json(char* total) {
    printf("{\"cart\":\"%s\",\"frames\":%d,\"every\":%d,\"calls\":[],\"samples\":[", ZM_CART, ZM_FRAMES, ZM_EVERY);
    for (int i = 0; i < ZM_FRAMES / ZM_EVERY; i++)
        printf("%s{\"frame\":%d,\"hash\":\"%s\"}", i ? "," : "", (i + 1) * ZM_EVERY, g_hashes[i]);
    printf("],\"total\":\"%s\"}\n", total);
}

static void run(void) {
    u32 size = w2c_machine_hwPhysWidth(&g_env.machine) * w2c_machine_hwPhysHeight(&g_env.machine) * 4;
    u32 planes = w2c_machine_hwPlanesNumber(&g_env.machine);
    sha256_ctx total, h;
    sha256_init(&total);
    for (long f = 1; f <= ZM_FRAMES; f++) {
        int sample = f % ZM_EVERY == 0;
        if (sample) sha256_init(&h);
        snap a, b;
        take(&a);
        prof_clear();
        frame(sample ? &h : NULL, planes, size);
        take(&b);
        print_frame(f, &a, &b);
        if (!sample) continue;
        sha256_hex(&h, g_hashes[f / ZM_EVERY - 1]);
        sha256_update(&total, g_hashes[f / ZM_EVERY - 1], 64);
    }
    char hex[65];
    sha256_hex(&total, hex);
    print_json(hex);
}

static void boot(void) {
    uint32_t t0 = board_cycles();
    host_boot(&g_env);
    uint8_t* fb0 = calloc(1, PICTURE_BYTES); /* black until the first swap */
    uint8_t* fb1 = calloc(1, PICTURE_BYTES);
    if (!fb0 || !fb1) board_finish(7);
    vseq_init(&g_env, (uint32_t)(uintptr_t)fb0, (uint32_t)(uintptr_t)fb1);
    printf("ZM BOOT %lu\n", (unsigned long)(board_cycles() - t0));
}

int main(void) {
    trap_install();
    prof_calibrate(1000);
    wasm_rt_init();
    wasm_rt_trap_t trap = wasm_rt_impl_try();
    if (trap) {
        printf("ZM WASMTRAP %s\n", wasm_rt_strerror(trap));
        board_finish(1);
    }
    boot();
    run();
    uint32_t st = zmv_status();
    printf("ZM VSTAT %lu %lu %lu %lu %lu\n", (unsigned long)((st & ZMV_BIT(UNDERRUN)) != 0),
           (unsigned long)((st & ZMV_BIT(OVERFLOW)) != 0), (unsigned long)ZMV_REG(SWAPS),
           (unsigned long)ZMV_REG(FRAME), (unsigned long)vseq.undrained);
    printf("ZM MIS %lu %lu\n", (unsigned long)zm_misaligned[0], (unsigned long)zm_misaligned[1]);
    board_finish(w2c_machine_hwRamAllocFailures(&g_env.machine) ? 1 : 0);
}
