// ---------------------------------------------------------------------------
// BENCH — the Hatari benchmark suite (apps/c/bench/), run on this machine for a like-for-like table.
//
// CoreMark, Dhrystone 2.1, Whetstone and LINPACK (double AND single/f32 builds) and a RAM read/write/copy test,
// one after another, each in slices of about 8 ms so no frame holds the machine for long (the board's glass
// calls a frame that finishes nothing for 2 s a stall). The clock is env.hostMicros, the only clock a cart has
// (decisions.md 2026-10-10); a host without one answers 0, and then every rate reads "no clock", never a number.
// Each result is drawn with the ROM's text API and logged ONCE as "ZM BENCH <name>=<value> <unit>".
//
// Keys: 1 reruns, Escape leaves. Times in a browser are the browser's, not the board's.
// Build: bash apps/c/build.sh bench  ->  docs/demo-c-bench.wasm
// ---------------------------------------------------------------------------
#include "../bench/kestrel/bench.h"
#include <stdio.h>
#include <string.h>
#include "../zigmachine_tvnoise.h"   // a catalog channel: +/- tunes in through the snow (exactly one .c file includes it)

#define ROM_IMPORT(name) __attribute__((import_module("env"), import_name(name)))
ROM_IMPORT("hwVideoBase") extern int hwVideoBase(void);
ROM_IMPORT("consoleLogJS") extern void consoleLogJS(const char *ptr, int len);
ROM_IMPORT("guiOpenPlane") extern unsigned guiOpenPlane(unsigned plane, int w, int h);
ROM_IMPORT("romInstallPalettePlane") extern void romInstallPalettePlane(unsigned plane);
ROM_IMPORT("guiRect") extern void guiRect(unsigned h, int x, int y, int w, int hh, unsigned color);
ROM_IMPORT("guiText") extern void guiText(unsigned h, const char *p, unsigned len, int x, int y, unsigned ink, unsigned paper);

#define K_ESC 0xE012u
#define BLACK 0
#define WHITE 1
#define FRAME_BUDGET_US 10000u   /* slices run back to back until a frame has used this much */

static unsigned gui;
static int want_menu, restart = 1, running = -1, dirty = 1, clocked, all_done;
static bench_res res[8];
static char log_line[160];

static void say(void) { consoleLogJS(log_line, (int)strlen(log_line)); }

static void milli(char *out, u64 m) {
    u64 ip = m / 1000;
    if (ip >= 1000000) snprintf(out, 24, "%u", (unsigned)ip);
    else snprintf(out, 24, "%u.%02u", (unsigned)ip, (unsigned)(m % 1000 / 10));
}

static void log_result(const bench_job *j, const bench_res *r) {
    char v[24];
    if (!clocked) { snprintf(log_line, sizeof log_line, "ZM BENCH %s=no clock", j->id); say(); }
    for (int i = 0; i < r->n && clocked; i++) {
        milli(v, r->v[i].milli);
        snprintf(log_line, sizeof log_line, "ZM BENCH %s=%s %s", r->v[i].name, v, r->v[i].unit);
        say();
    }
    snprintf(log_line, sizeof log_line, "ZM BENCH %s_check=%s (%s)", j->id, r->check_ok ? "ok" : "FAIL", r->check);
    say();
}

static void start_job(int i) {
    running = i;
    bench_jobs[i]->begin();
    dirty = 1;
}

static void run_frame(void) {
    if (restart) {
        restart = 0; all_done = 0; clocked = bench_has_clock();
        snprintf(log_line, sizeof log_line, "ZM BENCH clock=%s", clocked ? "hostMicros" : "none"); say();
        start_job(0);
        return;
    }
    if (running < 0) return;
    u32 t0 = bench_now();
    int more;
    do { more = bench_jobs[running]->step(); } while (more && clocked && bench_now() - t0 < FRAME_BUDGET_US);
    if (more) return;
    bench_jobs[running]->finish(&res[running]);
    log_result(bench_jobs[running], &res[running]);
    if (running + 1 < bench_njobs) { start_job(running + 1); return; }
    running = -1; all_done = 1; dirty = 1;
    snprintf(log_line, sizeof log_line, "ZM BENCH done"); say();
}

static void text(int row, const char *s) {
    guiRect(gui, 0, row * 10 + 2, 320, 10, WHITE);
    guiText(gui, s, (unsigned)strlen(s), 4, row * 10 + 3, BLACK, WHITE);
}

static void job_line(int row, int i) {
    char v[24], s[48];
    const bench_res *r = &res[i];
    if (running == i) snprintf(s, sizeof s, "%-21s running...", bench_jobs[i]->label);
    else if (running >= 0 && i > running) snprintf(s, sizeof s, "%-21s", bench_jobs[i]->label);
    else if (!clocked || !r->n) snprintf(s, sizeof s, "%-21s no clock  %s", bench_jobs[i]->label, r->check_ok ? "ok" : "FAIL");
    else { milli(v, r->v[0].milli); snprintf(s, sizeof s, "%-21s%s %s %s", bench_jobs[i]->label, v, r->v[0].unit, r->check_ok ? "" : "FAIL"); }
    text(row, s);
}

static void mem_lines(int row) {
    char s[48];
    const bench_res *r = &res[6];
    for (int half = 0; half < 2; half++) {
        const bench_val *v = &r->v[half * 4];
        if (running < 0 && clocked && r->n == 8)
            snprintf(s, sizeof s, "%-4s MB/s w%u r%u c%u m%u", half ? "256K" : "4K", (unsigned)(v[0].milli / 1000),
                     (unsigned)(v[1].milli / 1000), (unsigned)(v[2].milli / 1000), (unsigned)(v[3].milli / 1000));
        else snprintf(s, sizeof s, "%-4s MB/s (write read copy memcpy)", half ? "256K" : "4K");
        text(row + half, s);
    }
}

static void draw(void) {
    if (!gui || !dirty) return;
    dirty = 0;
    guiRect(gui, 0, 0, 320, 200, WHITE);
    text(0, "KESTREL BENCH  (1 = rerun)");
    for (int i = 0; i < 6; i++) job_line(2 + i, i);
    text(8, "RAM read/write/copy");
    mem_lines(9);
    text(12, clocked || running >= 0 ? "browser timings are not the board's" : "no clock: no rates shown");
    text(14, all_done ? "done" : "running");
}

__attribute__((export_name("boot")))
void boot(void) {
    gui = guiOpenPlane(0, 320, 200);
    if (gui) romInstallPalettePlane(0);
}

__attribute__((export_name("frame")))
void frame(float elapsed_ms) {
    (void)elapsed_ms;
    if (zm_tvnoise_frame()) return;   // a channel change: snow first
    run_frame();
    draw();
}

__attribute__((export_name("key")))
void key(u32 cp) {
    if (cp == K_ESC) want_menu = 1;
    else if (cp == '1') restart = 1;
}

__attribute__((export_name("pollCartRequest")))
int pollCartRequest(void) { if (!want_menu) return 0; want_menu = 0; return -1; }

// Harness hooks: a short target time, and a corrupted check value to prove the checks bite.
__attribute__((export_name("benchSetTargetUs"))) void benchSetTargetUs(u32 us) { bench_target_us = us; }
__attribute__((export_name("benchBreak"))) void benchBreak(int kind) { bench_break = kind; }

__attribute__((export_name("isPlaneEnabled"))) int isPlaneEnabled(int id) { return id == 0; }
__attribute__((export_name("hblDispatch"))) void hblDispatch(u32 id, u32 plane, u32 line, u32 x) { (void)id; (void)plane; (void)x; if (zm_tvnoise_hbl()) return; (void)line; }
__attribute__((export_name("skipBoot"))) void skipBoot(void) { zm_tvnoise_stop(); }
__attribute__((export_name("setShadeMode"))) void setShadeMode(u32 m) { (void)m; }
__attribute__((export_name("input"))) void input(unsigned char dir) { (void)dir; }
