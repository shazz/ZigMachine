/* ZIGGY bench: the cart (bench.h says what it measures and how the results get out).
 *
 * Called as every lean cart is (cycles/bsys.c, the hello carts): bind, instantiate, boot, then
 * frame and plane_enabled every frame. frame() runs one step a frame, so the glass keeps seeing
 * frames (it calls a cart stalled after 2 s without one) and no step holds the CPU for long:
 *   SETTLE frames idle, the calibration, each case of the four tables, the contention series,
 *   the frame tests (planes.c, many frames), then the results, a page every PAGE_FRAMES
 *   (or at a key). The log is complete (done = 1) once the pages show. */
#include "bench.h"

#define SETTLE 30       /* frames: let the boot and the glass settle first */
#define PAGE_FRAMES 240 /* 4 s a page */

typedef struct w2c_cart {
    uint32_t frames;
} bench_inst;

const zm_sys_table* zm_sys; /* .bss: the system zeroes it, then bind() fills it */

static const bench_case* const TABLES[] = {bench_cpu_cases, bench_mem_cases, bench_chisel_cases, bench_misc_cases,
    bench_align_cases};
#define NTABLES (int)(sizeof TABLES / sizeof TABLES[0])

static struct {
    enum { S_SETTLE, S_CAL, S_CASES, S_CONTEND, S_PLANES, S_SHOW } at;
    int table, row, done, total, page;
    uint32_t page_frames;
} run;

static void bind(const zm_sys_table* t) { zm_sys = t; }

static void instantiate(bench_inst* c, struct w2c_env* e) {
    (void)c;
    g.env = e;
    g.mem = *(uint8_t**)SYS(ZM_RT_w2c_env_memory, void* (*)(struct w2c_env*))(e); /* ->data */
    g.ram = g.mem + BENCH_RAM_AT;
    g.vreg = g.mem + ZM_HW_VIDEO_BASE;
}

static int count_cases(void) {
    int n = 0;
    for (int t = 0; t < NTABLES; t++)
        for (const bench_case* c = TABLES[t]; c->name; c++) n++;
    return n;
}

static void boot(bench_inst* c) {
    (void)c;
    *(volatile uint32_t*)(g.vreg + NATIVE_REG_BACKGROUND) = NATIVE_BORDER_RGBA;
    g.gui = SYS(ZM_ENV_guiOpenPlane, uint32_t (*)(struct w2c_env*, uint32_t, uint32_t, uint32_t))(g.env, 0, 320, 200);
    SYS(ZM_ENV_romInstallPalettePlane, void (*)(struct w2c_env*, uint32_t))(g.env, 0);
    run.total = count_cases();
    log_begin();
#ifdef __riscv_flen
    log_text("ZMBENCH-INFO cart=bench v=1 mhz=100 repeats=7 fpu=1");
#else
    log_text("ZMBENCH-INFO cart=bench v=1 mhz=100 repeats=7 fpu=0");
#endif
}

static void skip_boot(bench_inst* c) { (void)c; }

/* The next case of the tables, run; 0 once they are all done. */
static int next_case(void) {
    while (run.table < NTABLES) {
        const bench_case* c = &TABLES[run.table][run.row];
        if (c->name) {
            run.row++;
            bench_run(c);
            return 1;
        }
        run.table++, run.row = 0;
    }
    return 0;
}

static void show(int key) {
    if (!key && ++run.page_frames < PAGE_FRAMES) return;
    run.page_frames = 0;
    run.page = (run.page + 1) % screen_pages();
    screen_page(run.page);
}

static void frame(bench_inst* c, float dt) {
    (void)dt;
    c->frames++;
    if (!g.gui) return; /* no ROM context: nothing to show the results on */
    switch (run.at) {
    case S_SETTLE:
        if (c->frames == 1) screen_progress(0, run.total);
        if (c->frames >= SETTLE) run.at = S_CAL;
        break;
    case S_CAL: bench_calibrate(), run.at = S_CASES; break;
    case S_CASES:
        if (next_case()) screen_progress(++run.done, run.total);
        else run.at = S_CONTEND;
        break;
    case S_CONTEND: bench_contention(), run.at = S_PLANES; break;
    case S_PLANES:
        if (planes_frame()) break;
        log_done();
        run.at = S_SHOW, run.page = -1;
        show(1);
        break;
    case S_SHOW: show(0); break;
    }
}

static uint32_t plane_enabled(bench_inst* c, uint32_t p) {
    (void)c;
    if (run.at == S_PLANES) return (planes_mask() >> p) & 1u;
    return p == 0 && g.gui != 0;
}

static void hbl_dispatch(bench_inst* c, uint32_t id, uint32_t plane, uint32_t line, uint32_t x) {
    (void)c, (void)id, (void)plane, (void)line, (void)x;
}

/* Any key turns the page once the results show. */
static void key(bench_inst* c, uint32_t k) {
    (void)c, (void)k;
    if (run.at == S_SHOW) show(1);
}

/* host/host.h's host_input_bridge, which the generated header only declares (sys_abi.txt
 * `type host_input_bridge`): only key is set; the system checks every field for NULL. */
static const struct {
    void *owns_keyboard, *input, *input_release;
    void (*key)(bench_inst*, uint32_t);
    void *key_up, *shade, *pointer;
} INPUT = {.key = key};

extern char __cart_bss_start[], __cart_bss_end[]; /* cycles/cart.ld */

__attribute__((section(".zm_cart_hdr"), used)) const zm_cart_hdr zm_cart_header = {
    .magic = ZM_CART_HDR_MAGIC, .version = ZM_SYS_ABI_VERSION, .hdr_bytes = sizeof(zm_cart_hdr),
    .bss_start = __cart_bss_start, .bss_end = __cart_bss_end, .pages = NATIVE_PAGES,
    .cart_high = BENCH_CART_HIGH, .inst_bytes = sizeof(bench_inst), .bind = bind, .instantiate = instantiate,
    .boot = boot, .skip_boot = skip_boot, .frame = frame, .plane_enabled = plane_enabled,
    .hbl_dispatch = hbl_dispatch, .songs = (const struct host_song_bridge*)native_none,
    .input = (const struct host_input_bridge*)&INPUT, .dapp = (const struct host_disk_app_bridge*)native_none,
    .exports = (const struct host_export*)native_none, .song_files = (const struct zm_song*)native_none,
    .tag = "bench",
};
