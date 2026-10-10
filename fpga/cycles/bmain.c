/* The board firmware: vmain.c's boot and frame order (the RTL compositor under
 * the sequencer, vseq.h) on the board's SoC, where main RAM is PS DDR through
 * HP0 and the video DMA is on HP1 (soc/zm_board_mem.py). The same source runs
 * in soc/hp_sim.py and on the Z7-Lite:
 *
 *   ZM_FRAMES > 0   the sim: hash the PFB every ZM_EVERY frames as
 *                   apps/scene_hash.mjs does, print its JSON, "ZM VSTAT", end.
 *   ZM_BOARD        the bitstream: ZM_FRAMES = 0, run forever, no hashing; each
 *                   finished frame is CART_BEAT, the state CART_RUNNING.
 *
 * Lines (sim): "ZM BOOT c", per frame "ZM HF f cycles", the scene_hash JSON,
 * "ZM VSTAT underrun overflow swaps vbls undrained", "ZM MIS ...", "ZM BLIT calls hw cycles" (bblit.h),
 * "ZM END rc". With the audio (cycles/baudio.c; ZM_NO_AUDIO without): per frame "ZM AF f cart audio"
 * (the cycles of cart.frame() and of the players), "ZM SONG ts name" per song, then "ZM AUD ...". */
#include <stdio.h>
#include <stdlib.h>

#include "baudio.h"
#include "bblit.h"
#include "bboard.h"
#include "bdiag.h"
#include "bmailbox.h"
#include "boot.h"
#include "sha256.h"
#include "trap.h"
#include "vboard.h"
#include "vseq.h"
#include "wasm-rt-exceptions.h"
#include "wasm-rt-impl.h"
#include "zm_memmap.h"

#define PICTURE_BYTES (ZM_RASTER_WIDTH * ZM_RASTER_HEIGHT * 4u)
#define SAMPLES (ZM_FRAMES / (ZM_EVERY ? ZM_EVERY : 1) + 1)

#ifdef ZM_NO_AUDIO
#define AUDIO(call) ((void)0)
#else
#define AUDIO(call) call
#endif

static struct w2c_env g_env;
static char g_hashes[SAMPLES][65];

/* The PFB after the plane's last row reached memory, past the CPU's stale cache. */
static void hash_pfb(sha256_ctx* h, u32 size) {
    vseq_idle();
    zmv_flush_dcache();
    sha256_update(h, g_env.memory.data + w2c_machine_hwPhysicalPtr(&g_env.machine), size);
}

static void frame(sha256_ctx* h, u32 planes, u32 size, long f) {
    struct w2c_env* e = &g_env;
    vseq_clear(e);
    uint32_t t0 = board_cycles();
    w2c_cart_frame(&e->cart, 16.6f);
    uint32_t t1 = board_cycles();
    AUDIO(baudio_frame(e)); /* the song bridge, then the players up to the sound's lead */
    printf("ZM AF %ld %lu %lu\n", f, (unsigned long)(t1 - t0), (unsigned long)(board_cycles() - t1));
    int first = 1;
    for (u32 p = 0; p < planes; p++) {
        if (!w2c_cart_isPlaneEnabled(&e->cart, p)) {
            char off[16];
            if (h) sha256_update(h, off, (size_t)snprintf(off, sizeof off, "off%u", (unsigned)p));
            continue;
        }
        vseq_plane(e, (int)p, first);
        first = 0;
        if (h) hash_pfb(h, size);
    }
    if (first) vseq_mix_only();
    mb_presenting();
    vseq_present();
}

static void print_json(char* total) {
    printf("{\"cart\":\"%s\",\"frames\":%d,\"every\":%d,\"calls\":[],\"samples\":[", ZM_CART, ZM_FRAMES, ZM_EVERY);
    for (int i = 0; i < ZM_FRAMES / ZM_EVERY; i++)
        printf("%s{\"frame\":%d,\"hash\":\"%s\"}", i ? "," : "", (i + 1) * ZM_EVERY, g_hashes[i]);
    printf("],\"total\":\"%s\"}\n", total);
}

/* ZM_FRAMES frames (forever if 0), hashing every ZM_EVERY-th. */
static void run(void) {
    u32 size = w2c_machine_hwPhysWidth(&g_env.machine) * w2c_machine_hwPhysHeight(&g_env.machine) * 4;
    u32 planes = w2c_machine_hwPlanesNumber(&g_env.machine);
    sha256_ctx total, h;
    sha256_init(&total);
    for (long f = 1; ZM_FRAMES == 0 || f <= ZM_FRAMES; f++) {
        int sample = ZM_FRAMES && f % ZM_EVERY == 0;
        uint32_t t0 = board_cycles();
        if (sample) sha256_init(&h);
        frame(sample ? &h : NULL, planes, size, f);
        board_beat((uint32_t)f);
        mb_frame_done((uint32_t)f);
        printf("ZM HF %ld %lu\n", f, (unsigned long)(board_cycles() - t0));
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
    /* The pictures at fixed addresses (bmailbox.h), black until the first swap. */
    for (uint32_t i = 0; i < PICTURE_BYTES / 4; i++) {
        ((volatile uint32_t*)ZM_FB0_ADDR)[i] = 0;
        ((volatile uint32_t*)ZM_FB1_ADDR)[i] = 0;
    }
    vseq_init(&g_env, ZM_FB0_ADDR, ZM_FB1_ADDR);
    struct w2c_machine* m = &g_env.machine;
    uint32_t pfb = (uint32_t)(uintptr_t)(g_env.memory.data + w2c_machine_hwPhysicalPtr(m));
    mb_init(pfb, w2c_machine_hwPhysWidth(m), w2c_machine_hwPhysHeight(m));
    printf("ZM MB pfb %08lx %lu x %lu\n", (unsigned long)pfb, (unsigned long)w2c_machine_hwPhysWidth(m),
           (unsigned long)w2c_machine_hwPhysHeight(m));
    AUDIO(baudio_boot());
    printf("ZM BOOT %lu\n", (unsigned long)(board_cycles() - t0));
}

int main(void) {
    trap_install(); /* first: it sets mstatus.FS, and on an FPU core (ZM_FPU=1) any F instruction before traps */
    diag_maybe(); /* the write-path diagnostic, when the ARM asked for one (bdiag.h) */
    board_state(ZM_CART_BOOTING);
    wasm_rt_init();
    wasm_rt_trap_t trap = wasm_rt_impl_try();
    if (trap) {
        printf("ZM WASMTRAP %s\n", wasm_rt_strerror(trap));
        board_finish(1);
    }
    boot();
    board_state(ZM_CART_RUNNING);
    run();
    uint32_t st = zmv_status();
    printf("ZM VSTAT %lu %lu %lu %lu %lu\n", (unsigned long)((st & ZMV_BIT(UNDERRUN)) != 0),
           (unsigned long)((st & ZMV_BIT(OVERFLOW)) != 0), (unsigned long)ZMV_REG(SWAPS),
           (unsigned long)ZMV_REG(FRAME), (unsigned long)vseq.undrained);
    printf("ZM MIS %lu %lu\n", (unsigned long)zm_misaligned[0], (unsigned long)zm_misaligned[1]);
    printf("ZM BLIT %lu %lu %lu\n", (unsigned long)bblit.calls, (unsigned long)bblit.hw, (unsigned long)bblit.cycles);
    AUDIO(baudio_report());
    board_finish(w2c_machine_hwRamAllocFailures(&g_env.machine) ? 1 : 0);
}
