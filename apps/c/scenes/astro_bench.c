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
// The bench page has a plain-English legend and one table row a job (astro_bench/screen.h). Key 2 is
// the effect page (astro_bench/zoom.h): a Julia set zoomed 1e12 deep, every pixel's f64 maths done by
// ASTROLABE, SPACE swapping it for ZIGGY's soft f64, with ms a picture and pictures a second.
//
// Keys: 1 the bench (rerun), 2 the zoom, SPACE swaps the zoom's side, Escape leaves. Build: bash apps/c/build.sh astro_bench -> docs/demo-c-astro_bench.wasm
// ---------------------------------------------------------------------------
#include "astro_bench/astro.h"
#include "astro_bench/fmt.h"
#include "astro_bench/screen.h"
#include "astro_bench/jobs_scalar.h"
#include "astro_bench/jobs_batch.h"
#include "astro_bench/zoom.h"
#include "../zigmachine_tvnoise.h" // a catalog channel: +/- tunes in through the snow (exactly one .c file includes it)

#define K_ESC 0xE012u
enum { JOBS = 9 };
static int want_menu, job = -1, page; // page 0: the bench, 1: the zoom

// one log line, and the same numbers as a row of the screen
static void say(void) {
    consoleLogJS(fm_buf, (int)fm_len);
    show();
}

static int has_clock(void) {
    for (int i = 0; i < 64; i++) if (hostMicros() != 0) return 1;
    return 0;
}

static void start(void) {
    clocked = has_clock(), failures = 0, served = calls = 0, row = 6, job = 0, page = 0;
    if (gui) guiRect(gui, 0, 0, 320, 200, WHITE);
    text_z(0, "ASTRO BENCH");
    text_z(1, "ASTROLABE = an ARM chip doing f64 maths");
    text_z(2, "for ZIGGY, whose own soft f64 is slow.");
    text_z(3, "ns per op, lower is better:");
    text_z(4, "          ZIGGY    ASTRO    ASTRO  speed");
    text_z(5, "       soft f64   1 call batch 48 x soft");
    text_z(FOOTER_ROW, "1 rerun   2 ZOOM effect   Esc menu");
    fm_reset(), fm_s("ZM ASTRO clock="), fm_s(clocked ? "hostMicros" : "none"), consoleLogJS(fm_buf, (int)fm_len);
}

static void start_zoom(int soft, int from_top) {
    job = -1, page = 1;
    if (from_top) zstep = 0;
    if (gui) guiRect(gui, 0, 0, 320, 200, WHITE);
    zoom_start(soft);
    if (!zok) text_z(0, "zoom: out of memory");
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
    zoom_init();
    start();
}

__attribute__((export_name("frame"))) void frame(float elapsed_ms) {
    (void)elapsed_ms;
    if (zm_tvnoise_frame()) return; // a channel change: snow first
    if (page == 1) zoom_tick();
    else if (job >= 0) step();
}

__attribute__((export_name("key"))) void key(u32 cp) {
    if (cp == K_ESC) want_menu = 1;
    else if (cp == '1' && (job < 0 || page == 1)) start();
    else if (cp == '2') start_zoom(0, 1);
    else if (cp == ' ' && page == 1) start_zoom(!zsoft, 0);
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
