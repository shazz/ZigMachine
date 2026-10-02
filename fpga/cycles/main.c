/* The rv32 twin of host/main.c, for the cycles sim: the same boot and frame
 * loop as apps/scene_hash.mjs, with every span timed (prof.h) and a line per
 * frame on the UART. Frame count and hash period are compile-time, because a
 * bare core has no argv:
 *
 *   ZM_FRAMES   frames to run
 *   ZM_EVERY    hash every Nth frame, as scene_hash.mjs's `every`. Hashing is
 *               slow on rv32 and runs untimed (owner IDLE), so it costs sim time
 *               but no measured cycle.
 *   ZM_CART     the label echoed into the JSON
 *
 * Lines: "ZM CAL ...", "ZM BOOT ...", "ZM F ..." per frame, the scene_hash JSON,
 * "ZM FL ..." (float build), "ZM MIS ...", "ZM END rc". tools/cycles_report.py
 * parses them; their fields are documented there. */
#include <stdio.h>
#include <stdlib.h>

#include "boot.h"
#include "fcount.h"
#include "prof.h"
#include "sha256.h"
#include "trap.h"
#include "wasm-rt-exceptions.h"
#include "wasm-rt-impl.h"

static struct w2c_env g_env;
static char g_hashes[ZM_FRAMES / ZM_EVERY + 1][65];

static void print_owner(int owner) {
    const prof_acc* a = &prof[owner];
    for (int i = 0; i < ZM_NCOUNT; i++) printf(" %lu", (unsigned long)a->c[i]);
    printf(" %lu %lu", (unsigned long)a->n_in, (unsigned long)a->n_out);
}

static void print_line(const char* tag, long f) {
    printf("ZM %s %ld", tag, f);
    for (int owner = PROF_CART; owner < PROF_N; owner++) print_owner(owner);
    fcount_print_frame();
    printf("\n");
}

/* host/main.c frame(), with owners. isPlaneEnabled and the hashing stay IDLE. */
static void frame(sha256_ctx* h, u32 planes, u32 size) {
    struct w2c_env* e = &g_env;
    prof_enter(PROF_MACH);
    w2c_machine_hwClear(&e->machine);
    prof_leave();
    prof_enter(PROF_CART);
    w2c_cart_frame(&e->cart, 16.6f);
    prof_leave();
    for (u32 p = 0; p < planes; p++) {
        if (!w2c_cart_isPlaneEnabled(&e->cart, p)) {
            char off[16];
            if (h) sha256_update(h, off, (size_t)snprintf(off, sizeof off, "off%u", (unsigned)p));
            continue;
        }
        prof_enter(PROF_MACH);
        w2c_machine_hwRenderPlane(&e->machine, p);
        prof_leave();
        u32 ptr = w2c_machine_hwPhysicalPtr(&e->machine);
        if ((uint64_t)ptr + size > e->memory.size) board_finish(5);
        if (h) sha256_update(h, e->memory.data + ptr, size);
    }
}

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
        prof_clear();
        fcount_clear();
        frame(sample ? &h : NULL, planes, size);
        print_line("F", f);
        if (!sample) continue;
        sha256_hex(&h, g_hashes[f / ZM_EVERY - 1]);
        sha256_update(&total, g_hashes[f / ZM_EVERY - 1], 64);
    }
    char hex[65];
    sha256_hex(&total, hex);
    print_json(hex);
}

int main(void) {
    trap_install();
    prof_calibrate(1000);
    print_line("CAL", 1000);
    fcount_calibrate();
    wasm_rt_init();
    wasm_rt_trap_t trap = wasm_rt_impl_try();
    if (trap) {
        printf("ZM WASMTRAP %s\n", wasm_rt_strerror(trap));
        board_finish(1);
    }
    uint32_t t0 = board_cycles();
    host_boot(&g_env);
    printf("ZM BOOT %lu\n", (unsigned long)(board_cycles() - t0));
    run();
    fcount_print_totals();
    printf("ZM MIS %lu %lu\n", (unsigned long)zm_misaligned[0], (unsigned long)zm_misaligned[1]);
    /* As scene_hash.mjs: a cart refused a zg.mem buffer ran on a bad pointer. */
    board_finish(w2c_machine_hwRamAllocFailures(&g_env.machine) ? 1 : 0);
}
