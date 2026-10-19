/* The results on plane 0 with the ROM's GEM text (8x8 font, 40 columns): a title, a header,
 * and ROWS results a page. Drawn only when the page changes: every pixel is a store. */
#include "bench.h"

#define ROWS 19
#define ROW_H 9
#define TOP 24

typedef void (*text_fn)(struct w2c_env*, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);
typedef void (*rect_fn)(struct w2c_env*, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);

extern struct zmb_log zmb_log;

/* The ROM reads text from the shared memory: copy it to the cart's scratch, then draw. */
static void text(const char* s, uint32_t n, uint32_t x, uint32_t y) {
    for (uint32_t i = 0; i < n; i++) g.mem[BENCH_TEXT_AT + i] = (uint8_t)s[i];
    SYS(ZM_ENV_guiText, text_fn)(g.env, g.gui, BENCH_TEXT_AT, n, x, y, GEM_WHITE, GEM_BLACK);
}

static void clear(void) { SYS(ZM_ENV_guiRect, rect_fn)(g.env, g.gui, 0, 0, 320, 200, GEM_BLACK); }

static char* pad(char* p, char* from, uint32_t col) {
    while ((uint32_t)(p - from) < col) *p++ = ' ';
    return p;
}

/* The log's address as the ARM sees it (bench_collect.py finds it on its own). */
static char* hex(char* p, uint32_t v) {
    for (int s = 28; s >= 0; s -= 4) *p++ = "0123456789ABCDEF"[(v >> s) & 15u];
    return p;
}

static void title(const char* what) {
    char b[48], *p = fmt_str(b, "ZIGGY BENCH ");
    p = fmt_str(p, what);
    p = fmt_str(p, " LOG ");
    p = hex(p, (uint32_t)(uintptr_t)&zmb_log - NATIVE_CART_CPU_BASE + NATIVE_DDR_CART_BASE);
    text(b, (uint32_t)(p - b), 0, 0);
}

void screen_progress(int done, int total) {
    char b[24], *p = fmt_u32(b, (uint32_t)done);
    *p++ = '/';
    p = fmt_u32(p, (uint32_t)total);
    if (done == 0) clear();
    title("RUN");
    text(b, (uint32_t)(p - b), 0, 12);
}

int screen_pages(void) { return (bench_nresults + ROWS - 1) / ROWS; }

/* name, cycles an op (one decimal), MB/s at 100 MHz (bytes a cycle x 100). */
static void row(const bench_result* r, uint32_t y) {
    char b[48], *p = fmt_str(b, r->name);
    p = pad(p, b, 17);
    p = fmt_fixed1(p, r->min, r->ops);
    if (r->size) {
        p = pad(p, b, 29);
        p = fmt_fixed1(p, r->size * 100u, r->min); /* size <= 256 KiB: no overflow */
    }
    text(b, (uint32_t)(p - b), 0, y);
}

void screen_page(int page) {
    char b[24], *p = fmt_str(b, "P");
    p = fmt_u32(p, (uint32_t)page + 1u);
    *p++ = '/';
    p = fmt_u32(p, (uint32_t)screen_pages());
    clear();
    title("DONE");
    text(b, (uint32_t)(p - b), 0, 12);
    text("CYC/OP      MB/S", 16, 17 * 8, 12);
    for (int i = 0; i < ROWS; i++) {
        int k = page * ROWS + i;
        if (k >= bench_nresults) break;
        row(&bench_results[k], TOP + (uint32_t)i * ROW_H);
    }
}
