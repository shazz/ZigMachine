// ---------------------------------------------------------------------------
// ASTRO BENCH — what ASTROLABE (SPIKE, docs/ARM_FPU_COPROC.md), the f64 coprocessor, costs and
// whether its answers are right, against the cart's own maths on the same host.
//
// One job a frame: the round trip (NOP), ADD / MUL / DIV / SQRT / SIN each as one ASTROLABE call
// per op, 48 ops a call, the cart's f64 and its f32; LINPACK 100 in the cart's f64 and as two
// descriptors (GEFA + GESL); sin() over 4096 elements; reference bits for the harness. Each result
// is drawn and logged ONCE as "ZM ASTRO ..."; a wrong answer logs "ZM ASTRO FAIL ...".
// In the browser the machine computes ASTROLABE itself (no latency to speak of, and no ARM: served=0);
// on the board the ARM's VFPv3 does (served = calls), and ZIGGY's cycles of each call are in W_CYCLES.
//
// Keys: 1 reruns, Escape leaves. Build: bash apps/c/build.sh astro_bench -> docs/demo-c-astro_bench.wasm
// ---------------------------------------------------------------------------
#include "astro_bench/astro.h"
#include "astro_bench/fmt.h"
#include "astro_bench/jobs_scalar.h"
#include "astro_bench/jobs_batch.h"
#include "../zigmachine_tvnoise.h" // a catalog channel: +/- tunes in through the snow (exactly one .c file includes it)

#define ROM_IMPORT(name) __attribute__((import_module("env"), import_name(name)))
ROM_IMPORT("consoleLogJS") extern void consoleLogJS(const char* ptr, int len);
ROM_IMPORT("guiOpenPlane") extern unsigned guiOpenPlane(unsigned plane, int w, int h);
ROM_IMPORT("romInstallPalettePlane") extern void romInstallPalettePlane(unsigned plane);
ROM_IMPORT("guiRect") extern void guiRect(unsigned h, int x, int y, int w, int hh, unsigned color);
ROM_IMPORT("guiText") extern void guiText(unsigned h, const char* p, unsigned len, int x, int y, unsigned ink, unsigned paper);

#define K_ESC 0xE012u
enum { BLACK = 0, WHITE = 1, JOBS = 9, ROWS = 19 };

static unsigned gui;
static int want_menu, job = -1, row;

static void text(int r, const char* s, unsigned n) {
    if (!gui || r >= ROWS) return;
    guiRect(gui, 0, r * 10 + 4, 320, 10, WHITE);
    guiText(gui, s, n > 52 ? 52 : n, 2, r * 10 + 5, BLACK, WHITE);
}

// one log line, and its text (from "ZM ASTRO " on) on the next row of the screen
static void say(void) {
    consoleLogJS(fm_buf, (int)fm_len);
    text(row++, fm_buf + 9, fm_len - 9);
}

static int has_clock(void) {
    for (int i = 0; i < 64; i++) if (hostMicros() != 0) return 1;
    return 0;
}

static void start(void) {
    clocked = has_clock(), failures = 0, served = calls = 0, row = 1, job = 0;
    if (gui) guiRect(gui, 0, 0, 320, 200, WHITE);
    text(0, "ASTRO BENCH: ASTROLABE f64 vs ZIGGY (1 = rerun)", 47);
    fm_reset(), fm_s("ZM ASTRO clock="), fm_s(clocked ? "hostMicros" : "none"), consoleLogJS(fm_buf, (int)fm_len);
}

static void step(void) {
    switch (job) {
    case 0: job_roundtrip(); break;
    case 1: job_scalar(AS_ADD, "add"); break;
    case 2: job_scalar(AS_MUL, "mul"); break;
    case 3: job_scalar(AS_DIV, "div"); break;
    case 4: job_scalar(AS_SQRT, "sqrt"); break;
    case 5: job_scalar(AS_SIN, "sin"); break;
    case 6: job_linpack(); break;
    case 7: job_sin_batch(); break;
    case 8: job_reference(); break;
    }
    if (++job < JOBS) return;
    job = -1;
    fm_reset(), fm_s("ZM ASTRO done failures="), fm_u(failures), fm_s(" served="), fm_u(served), fm_s("/"), fm_u(calls), say();
}

__attribute__((export_name("boot"))) void boot(void) {
    gui = guiOpenPlane(0, 320, 200);
    if (gui) romInstallPalettePlane(0);
    start();
}

__attribute__((export_name("frame"))) void frame(float elapsed_ms) {
    (void)elapsed_ms;
    if (zm_tvnoise_frame()) return; // a channel change: snow first
    if (job >= 0) step();
}

__attribute__((export_name("key"))) void key(u32 cp) {
    if (cp == K_ESC) want_menu = 1;
    else if (cp == '1' && job < 0) start();
}

__attribute__((export_name("pollCartRequest"))) int pollCartRequest(void) {
    if (!want_menu) return 0;
    want_menu = 0;
    return -1;
}

__attribute__((export_name("isPlaneEnabled"))) int isPlaneEnabled(int id) { return id == 0; }
__attribute__((export_name("hblDispatch"))) void hblDispatch(u32 id, u32 plane, u32 line, u32 x) { (void)id, (void)plane, (void)line, (void)x; zm_tvnoise_hbl(); }
__attribute__((export_name("skipBoot"))) void skipBoot(void) { zm_tvnoise_stop(); }
__attribute__((export_name("setShadeMode"))) void setShadeMode(u32 m) { (void)m; }
__attribute__((export_name("input"))) void input(unsigned char dir) { (void)dir; }
