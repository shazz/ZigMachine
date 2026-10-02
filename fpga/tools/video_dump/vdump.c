/* vdump: run a cart through the native host exactly as fpga/host/main.c does
 * (scene_hash.mjs's frame loop), and record the frames named on the command line
 * for the RTL compositor's replay testbench (tests/tb/video_comp_tb.cpp).
 *
 *   vdump <outdir> <frame> [<frame> ...] [--call F:export:arg,...]
 *
 * The machine's hblDispatch import is env.c's forwarder renamed (the build
 * compiles env.c with -Dw2c_env_hblDispatch=vd_orig_hblDispatch), so every HBL
 * passes through here and is bracketed by a PRE and a POST state record. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "boot.h"
#include "vdump.h"
#include "wasm-rt-exceptions.h"
#include "wasm-rt-impl.h"

#define MAX_FRAMES 64
#define MAX_CALLS 16

void vd_orig_hblDispatch(struct w2c_env* e, u32 id, u32 plane, u32 line, u32 x);

void w2c_env_hblDispatch(struct w2c_env* e, u32 id, u32 plane, u32 line, u32 x) {
    vd_hbl(&e->memory, VD_PRE, line);
    vd_orig_hblDispatch(e, id, plane, line, x);
    vd_hbl(&e->memory, VD_POST, line);
}

static struct w2c_env g_env;
static long g_frames[MAX_FRAMES];
static int g_nframes;
static const char* g_calls[MAX_CALLS];
static int g_ncalls;

/* "F:name:a,b" -> host_call at frame F (the subset of main.c's parser vdump needs). */
static void run_call(const char* spec) {
    char name[64];
    double args[HOST_MAX_ARGS];
    int n = 0;
    const char* p = strchr(spec, ':');
    if (!p) {
        fprintf(stderr, "vdump: bad --call %s\n", spec);
        exit(2);
    }
    p++;
    const char* a = strchr(p, ':');
    snprintf(name, sizeof name, "%.*s", (int)(a ? a - p : (long)strlen(p)), p);
    for (const char* q = a ? a + 1 : NULL; q && *q && n < HOST_MAX_ARGS;) {
        args[n++] = strtod(q, NULL);
        q = strchr(q, ',');
        if (q) q++;
    }
    if (host_call(&g_env, name, args, n)) exit(1);
}

static void run_calls(long f) {
    for (int i = 0; i < g_ncalls; i++)
        if (strtol(g_calls[i], NULL, 10) == f) run_call(g_calls[i]);
}

static int wanted(long f) {
    for (int i = 0; i < g_nframes; i++)
        if (g_frames[i] == f) return 1;
    return 0;
}

/* One host frame (main.c's frame()), with the recorder's hooks at each pass. */
static void frame(int rec) {
    struct w2c_env* e = &g_env;
    u32 planes = w2c_machine_hwPlanesNumber(&e->machine), mask = 0;
    vd_pass_start(&e->memory, 0);
    w2c_machine_hwClear(&e->machine);
    vd_pass_end(&e->memory);
    if (rec) vd_dump_pfb(&e->memory);
    w2c_cart_frame(&e->cart, 16.6f);
    if (rec) vd_dump_mem(&e->memory);
    for (u32 p = 0; p < planes; p++) {
        if (!w2c_cart_isPlaneEnabled(&e->cart, p)) continue;
        mask |= 1u << p;
        vd_pass_start(&e->memory, p + 1);
        w2c_machine_hwRenderPlane(&e->machine, p);
        vd_pass_end(&e->memory);
        if (rec) vd_dump_pfb(&e->memory);
    }
    if (rec) vd_end(&e->memory, mask);
}

static long parse_args(int argc, char** argv) {
    long last = 0;
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--call") == 0 && i + 1 < argc) {
            if (g_ncalls < MAX_CALLS) g_calls[g_ncalls++] = argv[++i];
        } else if (g_nframes < MAX_FRAMES) {
            g_frames[g_nframes] = strtol(argv[i], NULL, 10);
            if (g_frames[g_nframes] > last) last = g_frames[g_nframes];
            g_nframes++;
        }
    }
    return last;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: vdump <outdir> <frame>... [--call F:name:args]\n");
        return 2;
    }
    long last = parse_args(argc, argv);
    wasm_rt_init();
    wasm_rt_trap_t trap = wasm_rt_impl_try();
    if (trap) {
        fprintf(stderr, "vdump: trap: %s\n", wasm_rt_strerror(trap));
        return 1;
    }
    host_boot(&g_env);
    for (long f = 1; f <= last; f++) {
        run_calls(f);
        int rec = wanted(f);
        if (rec && vd_begin(&g_env.memory, argv[1], f)) return 1;
        frame(rec);
    }
    return 0;
}
