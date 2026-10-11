/* The native twin of apps/scene_hash.mjs: same arguments, same frame loop, same
 * JSON on stdout, so the two outputs compare with `scene_hash.mjs --compare`.
 *
 *   host <cart-label> [frames=1200] [every=10] [--call F:export:arg,...] [--disk X.zmd]
 *
 * --disk mounts X.zmd in the drive (host/disk.h), as scene_hash.mjs --disk and the
 * browser do; without it diskReadBlock answers 0, scene_hash.mjs's stub.
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
#include "disk.h"
#include "input_bridge.h"
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

#define MAX_CALLS 64

typedef struct {
    long frame;
    char name[64];
    double args[HOST_MAX_ARGS];
    int nargs;
    const char* spec;
} call_t;

static struct w2c_env g_env; /* static: 7 MiB of memory is heap, the instances are not */
static call_t g_calls[MAX_CALLS];
static int g_ncalls;

/* "F:name:a,b,c" -> call_t; JS Number() semantics are approximated by strtod
 * (a malformed number becomes NaN, as Number("x") does). */
static void parse_call(const char* spec) {
    if (g_ncalls == MAX_CALLS) { fprintf(stderr, "host: too many --call\n"); exit(1); }
    call_t* c = &g_calls[g_ncalls++];
    c->spec = spec;
    c->frame = strtol(spec, NULL, 10);
    const char* name = strchr(spec, ':');
    if (!name) { fprintf(stderr, "host: bad --call %s\n", spec); exit(1); }
    name++;
    const char* args = strchr(name, ':');
    size_t len = args ? (size_t)(args - name) : strlen(name);
    snprintf(c->name, sizeof c->name, "%.*s", (int)len, name);
    for (const char* p = args ? args + 1 : NULL; p && *p && c->nargs < HOST_MAX_ARGS;) {
        char* end;
        double v = strtod(p, &end);
        c->args[c->nargs++] = (end == p || (*end && *end != ',')) ? NAN : v;
        p = strchr(p, ',');
        if (p) p++;
    }
}

/* --disk: the whole image in memory, as the browser's mountDisk holds it. */
static void mount_disk(const char* path) {
    FILE* f = fopen(path, "rb");
    long n = f && fseek(f, 0, SEEK_END) == 0 ? ftell(f) : -1;
    uint8_t* buf = n > 0 ? malloc((size_t)n) : NULL;
    if (!buf || fseek(f, 0, SEEK_SET) != 0 || fread(buf, 1, (size_t)n, f) != (size_t)n) {
        fprintf(stderr, "host: cannot read disk %s\n", path);
        exit(1);
    }
    fclose(f);
    host_disk = (host_disk_t){.data = buf, .size = (uint32_t)n};
}

static void run_calls(long f) {
    for (int i = 0; i < g_ncalls; i++)
        if (g_calls[i].frame == f && host_call(&g_env, g_calls[i].name, g_calls[i].args, g_calls[i].nargs))
            exit(1);
}

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
    for (int i = 0; i < g_ncalls; i++) printf("%s\"%s\"", i ? "," : "", g_calls[i].spec);
    printf("],\"samples\":[");
    for (long i = 0; i < count; i++)
        printf("%s{\"frame\":%ld,\"hash\":\"%s\"}", i ? "," : "", (i + 1) * k, hashes[i]);
    printf("],\"total\":\"%s\"}\n", total);
}

/* ZM_GLASS_KEYS: this frame's events, through the router (cycles/binput.c's job on the board). */
static void glass_keys(long f) {
    static const char* at;
    static int started;
    if (!started) at = getenv("ZM_GLASS_KEYS"), started = 1;
    uint32_t ev[32], n = 0;
    while (at && *at) {
        long frame = 0;
        unsigned long event = 0;
        int used = 0;
        if (sscanf(at, "%ld:%lx%n", &frame, &event, &used) != 2 || frame > f) break;
        at += used + (at[used] == ',');
        if (frame == f && n < 32) ev[n++] = (uint32_t)event;
    }
    input_events(&g_env.cart, ev, n);
}

/* ZM_GLASS_POINTER: this frame's REG_POINTER, polled and acked as cycles/binput.c does. */
static void glass_mouse(long f) {
    static const char* at;
    static int started;
    static uint32_t ptr, seen;
    if (!started) at = getenv("ZM_GLASS_POINTER"), started = 1;
    if (!at) return;
    if (input_pointer_script(&at, f, &ptr)) {
        fprintf(stderr, "host: bad ZM_GLASS_POINTER entry before frame %ld\n", f);
        exit(2);
    }
    (void)input_pointer(&g_env.cart, ptr, &seen); /* the ack: nothing latched to drop here */
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
        run_calls(f);
        glass_keys(f);
        glass_mouse(f);
        int sample = f % k == 0;
        if (sample) sha256_init(&h);
        frame(sample ? &h : NULL, planes, size, f);
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
        if (strcmp(argv[i], "--call") == 0 && i + 1 < argc) parse_call(argv[++i]);
        else if (strcmp(argv[i], "--disk") == 0 && i + 1 < argc) mount_disk(argv[++i]);
        else if (npos < 3) pos[npos++] = argv[i];
    }
    if (!pos[0]) { fprintf(stderr, "usage: host <cart> [frames] [every] [--call F:name:args]\n"); return 2; }
    long n = strtol(pos[1], NULL, 10), k = strtol(pos[2], NULL, 10);
    if (k <= 0) { fprintf(stderr, "host: every must be > 0\n"); return 2; }
    wasm_rt_init();
    wasm_rt_trap_t trap = wasm_rt_impl_try();
    if (trap) { fprintf(stderr, "host: %s: trap: %s\n", pos[0], wasm_rt_strerror(trap)); return 1; }
    host_boot(&g_env);
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
