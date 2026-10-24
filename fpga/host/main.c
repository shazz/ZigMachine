/* The native twin of apps/scene_hash.mjs: same arguments, same frame loop, same
 * JSON on stdout, so the two outputs compare with `scene_hash.mjs --compare`.
 *
 *   host <cart-label> [frames=1200] [every=10] [--call F:export:arg,...] [--disk X.zmd]
 *        [--data-disk X.zmd [--program]]
 *
 * --disk mounts X.zmd in the drive (host/disk.h), as scene_hash.mjs --disk and the
 * browser do; without it diskReadBlock answers 0, scene_hash.mjs's stub. --data-disk
 * mounts a data disk and plays the browser's GEM-over-a-data-disk step (host/disk_app.h);
 * --program: the cart is a program launched off it, which gets no listing. --bootsec X.zmd runs
 * X's executable boot sector in the cart's place (host/bootsec_host.h), the board's interpreter
 * against scene_hash.mjs given the same X.zmd.
 *
 * <cart-label> is only echoed into the JSON (the cart is linked in).
 *
 *   ZM_GLASS_KEYS=F:event,...  the glass's key FIFO as a script: before frame F, the KEY_*
 *                              event (hex, fpga/glass/src/map.zig) goes through the board
 *                              firmware's router (host/input_bridge.c), as cycles/binput.c
 *                              hands it the FIFO: how the board's input is tested here.
 *   ZM_GLASS_POINTER=F:word,...  the mouse the same way: before frame F, the ARM writes `word`
 *                              (hex, REG_POINTER's x | y<<10 | buttons<<20) and the CSR, its SEQ
 *                              bumped, goes through glass_pointer() as binput.c polls it. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "boot.h"
#include "bootsec_host.h"
#include "host_io.h"
#include "sha256.h"
#include "wasm-rt-exceptions.h" /* wasm_rt_impl_try needs wasm_rt_set_unwind_target */
#include "wasm-rt-impl.h"

#ifdef HOST_WALLCLOCK
#include <time.h>
#endif

/* host_audio (cycles/audio.mk): the same host plus the machine's audio side. */
#ifdef HOST_AUDIO
#include "haudio_soft.h"
#define AUDIO(call) call
#else
#define AUDIO(call) ((void)0)
#endif

static struct w2c_env g_env; /* static: 7 MiB of memory is heap, the instances are not */
static const char* g_bootsec;  /* --bootsec: the disk whose boot sector runs instead of the cart */


/* One frame of the host loop (docs/sealed-loader.js): clear, frame, then render
 * every ENABLED plane. HBL handlers only run inside hwRenderPlane, so planes are
 * rendered every frame, sampled or not. */
/* HOST_WARP_MS=<ms>: frame 1's dt instead of 16.6, the firmware's ZM_WARP_MS (cycles/bmain.c). */
static float frame_dt(long f) {
    const char* warp = f == 1 ? getenv("HOST_WARP_MS") : NULL;
    return warp && atof(warp) > 0 ? (float)atof(warp) : 16.6f;
}

static void frame(sha256_ctx* h, u32 planes, u32 size, long f) {
    struct w2c_env* e = &g_env;
    w2c_machine_hwClear(&e->machine);
    w2c_cart_frame(&e->cart, frame_dt(f));
    host_io_disk_frame(e, f); /* --data-disk: before the song bridge, as the browser's step */
    AUDIO(audio_soft_frame(e));
    for (u32 p = 0; p < planes; p++) {
        if (!w2c_cart_isPlaneEnabled(&e->cart, p)) {
            char off[16];
            if (h) sha256_update(h, off, (size_t)snprintf(off, sizeof off, "off%u", (unsigned)p));
            continue;
        }
        w2c_machine_hwRenderPlane(&e->machine, p);
        u32 ptr = w2c_machine_hwPhysicalPtr(&e->machine);
        if ((uint64_t)ptr + size > e->memory.size) { fprintf(stderr, "host: framebuffer OOB\n"); exit(1); }
        if (h) sha256_update(h, e->memory.data + ptr, size);
    }
}

/* HOST_DUMP_PFB=<path>: the PFB after the last frame, as the board's
 * tools/board_shot.py --what pfb dumps it (its --expect). */
static void dump_pfb(u32 size) {
    const char* path = getenv("HOST_DUMP_PFB");
    if (!path) return;
    FILE* f = fopen(path, "wb");
    if (!f || fwrite(g_env.memory.data + w2c_machine_hwPhysicalPtr(&g_env.machine), 1, size, f) != size) {
        fprintf(stderr, "host: cannot write %s\n", path);
        exit(1);
    }
    fclose(f);
    const char* vpath = getenv("HOST_DUMP_VRAM"); /* the region's VRAM, 64 KiB: board VRAM compares */
    if (!vpath) return;
    u32 vram = w2c_machine_hwPhysicalPtr(&g_env.machine) - 0x101100u + 0x1100u; /* - OFF_PFB + OFF_VRAM */
    FILE* v = fopen(vpath, "wb");
    if (!v || fwrite(g_env.memory.data + vram, 1, 65536, v) != 65536) exit(1);
    fclose(v);
}

static void print_json(const char* cart, long n, long k, char (*hashes)[65], long count, const char* total) {
    printf("{\"cart\":\"%s\",\"frames\":%ld,\"every\":%ld,\"calls\":[", cart, n, k);
    for (int i = 0; host_io_call_spec(i); i++) printf("%s\"%s\"", i ? "," : "", host_io_call_spec(i));
    printf("],\"samples\":[");
    for (long i = 0; i < count; i++)
        printf("%s{\"frame\":%ld,\"hash\":\"%s\"}", i ? "," : "", (i + 1) * k, hashes[i]);
    printf("],\"total\":\"%s\"}\n", total);
}

static void run(const char* cart, long n, long k) {
    u32 size = w2c_machine_hwPhysWidth(&g_env.machine) * w2c_machine_hwPhysHeight(&g_env.machine) * 4;
    u32 planes = w2c_machine_hwPlanesNumber(&g_env.machine);
    long count = n / k;
    char (*hashes)[65] = calloc((size_t)count + 1, sizeof *hashes);
    sha256_ctx total, h;
    sha256_init(&total);
#ifdef HOST_WALLCLOCK
    struct timespec t0, t1;
    timespec_get(&t0, TIME_UTC);
#endif
    for (long f = 1; f <= n; f++) {
        host_io_run_calls(&g_env, f);
        host_io_glass_keys(&g_env, f);
        host_io_glass_mouse(&g_env, f);
        int sample = f % k == 0;
        if (sample) sha256_init(&h);
        if (g_bootsec) host_bootsec_frame(&g_env, sample ? &h : NULL, planes, size);
        else frame(sample ? &h : NULL, planes, size, f);
        if (!sample) continue;
        sha256_hex(&h, hashes[f / k - 1]);
        sha256_update(&total, hashes[f / k - 1], 64);
    }
#ifdef HOST_WALLCLOCK
    timespec_get(&t1, TIME_UTC);
    double ms = (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
    fprintf(stderr, "host: %ld frames in %.1f ms (%.3f ms/frame)\n", n, ms, ms / n);
#endif
    char hex[65];
    sha256_hex(&total, hex);
    print_json(cart, n, k, hashes, count, hex);
    dump_pfb(size);
    free(hashes);
}

int main(int argc, char** argv) {
    const char* pos[3] = {NULL, "1200", "10"};
    int npos = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--call") == 0 && i + 1 < argc) host_io_parse_call(argv[++i]);
        else if (strcmp(argv[i], "--disk") == 0 && i + 1 < argc) host_io_mount_disk(argv[++i]);
        else if (strcmp(argv[i], "--data-disk") == 0 && i + 1 < argc) host_io_data_disk(argv[++i]);
        else if (strcmp(argv[i], "--program") == 0) host_io_program();
        else if (strcmp(argv[i], "--bootsec") == 0 && i + 1 < argc) g_bootsec = argv[++i];
        else if (npos < 3) pos[npos++] = argv[i];
    }
    if (!pos[0]) { fprintf(stderr, "usage: host <cart> [frames] [every] [--call F:name:args] [--disk X.zmd] [--data-disk X.zmd]\n"); return 2; }
    long n = strtol(pos[1], NULL, 10), k = strtol(pos[2], NULL, 10);
    if (k <= 0) { fprintf(stderr, "host: every must be > 0\n"); return 2; }
    wasm_rt_init();
    wasm_rt_trap_t trap = wasm_rt_impl_try();
    if (trap) { fprintf(stderr, "host: %s: trap: %s\n", pos[0], wasm_rt_strerror(trap)); return 1; }
    if (!g_bootsec) host_boot(&g_env);
    else if (host_boot_machine(&g_env), host_bootsec_start(&g_env, g_bootsec)) return 1;
    AUDIO(audio_soft_boot());
    run(pos[0], n, k);
    AUDIO(audio_soft_close());
    /* As scene_hash.mjs: a cart refused a zg.mem buffer ran on a bad pointer. */
    u32 refused = w2c_machine_hwRamAllocFailures(&g_env.machine);
    if (refused) {
        fprintf(stderr, "scene_hash: %s: %u zg.mem allocation(s) refused\n", pos[0], (unsigned)refused);
        return 1;
    }
    return 0;
}
