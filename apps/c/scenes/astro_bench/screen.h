// ASTRO BENCH's bench page: a legend in plain English, then one table row a job, every line
// clipped to the screen's 40 columns (the 8 px font on 320 px). The log lines ("ZM ASTRO ...")
// are the harness's and stay as they were; the screen shows the same numbers as a table with the
// speedup worked out, so nothing runs off the right edge and nothing needs decoding.
#ifndef ASTRO_SCREEN_H
#define ASTRO_SCREEN_H

#define ROM_IMPORT(name) __attribute__((import_module("env"), import_name(name)))
ROM_IMPORT("consoleLogJS") extern void consoleLogJS(const char* ptr, int len);
ROM_IMPORT("guiOpenPlane") extern unsigned guiOpenPlane(unsigned plane, int w, int h);
ROM_IMPORT("romInstallPalettePlane") extern void romInstallPalettePlane(unsigned plane);
ROM_IMPORT("guiRect") extern void guiRect(unsigned h, int x, int y, int w, int hh, unsigned color);
ROM_IMPORT("guiText") extern void guiText(unsigned h, const char* p, unsigned len, int x, int y, unsigned ink, unsigned paper);

enum { BLACK = 0, WHITE = 1, ROWS = 19, COLS = 40, FOOTER_ROW = 17 };

static unsigned gui;
static int row;

static void text(int r, const char* s, unsigned n) {
    if (!gui || r >= ROWS) return;
    guiRect(gui, 0, r * 10 + 4, 320, 10, WHITE);
    guiText(gui, s, n > COLS ? COLS : n, 0, r * 10 + 5, BLACK, WHITE);
}
static void text_z(int r, const char* s) { text(r, s, fm_strlen(s)); }

// a long line broken at spaces onto the next rows, 2 columns in after the first
static void wrap(const char* s, unsigned n) {
    char out[COLS + 1];
    for (unsigned ind = 0; n; ind = 2) {
        unsigned room = COLS - ind, m = n < room ? n : room;
        if (m < n) while (m > 1 && s[m] != ' ') m--;
        for (unsigned i = 0; i < ind; i++) out[i] = ' ';
        for (unsigned i = 0; i < m; i++) out[ind + i] = s[i];
        text(row++, out, ind + m);
        s += m, n -= m;
        while (n && *s == ' ') s++, n--;
    }
}

// --- one table row: a 40-column line, names left, numbers right-aligned to a column's end ---
static char tb[COLS];
static void tb_clear(void) { for (int i = 0; i < COLS; i++) tb[i] = ' '; }
static void tb_text(int at, const char* s) { while (*s && at < COLS) tb[at++] = *s++; }
static void tb_num(int end, long v, int tenths) { // ends at column `end`; v < 0: "-"; tenths: v is x10
    char t[16];
    int n = 0;
    if (v < 0) t[n++] = '-';
    else {
        unsigned long u = (unsigned long)(tenths ? v / 10 : v);
        char d[12];
        int k = 0;
        do d[k++] = (char)('0' + u % 10), u /= 10; while (u);
        if (tenths) t[n++] = 'x';
        while (k) t[n++] = d[--k];
        if (tenths && v < 1000) t[n++] = '.', t[n++] = (char)('0' + v % 10);
    }
    for (int i = 0; i < n; i++) tb[end - n + 1 + i] = t[i];
}

// " key=" 's number in the log line being shown; -1 for "-" (no clock), -2 when the key is absent
static long tok(const char* key) {
    unsigned kl = fm_strlen(key);
    for (unsigned i = 8; i + kl + 2 <= fm_len; i++) {
        if (fm_buf[i] != ' ' || fm_buf[i + kl + 1] != '=') continue;
        unsigned j = 0;
        while (j < kl && fm_buf[i + 1 + j] == key[j]) j++;
        if (j != kl) continue;
        long v = 0;
        unsigned p = i + kl + 2;
        if (p >= fm_len || fm_buf[p] < '0' || fm_buf[p] > '9') return -1;
        for (; p < fm_len && fm_buf[p] >= '0' && fm_buf[p] <= '9'; p++) v = v * 10 + (fm_buf[p] - '0');
        return v;
    }
    return -2;
}

// x10 of num / den (den > 0): the speedup
static long ratio10(long num, long den) { return num >= 0 && den > 0 ? num * 10 / den : -1; }

// columns end at 14 (ZIGGY soft f64), 23 (ASTROLABE one call), 32 (a batch of 48), 39 (speedup, x10)
static void table_row(const char* name, long soft, long one, long batch) {
    tb_clear();
    tb_text(0, name);
    tb_num(14, soft, 0), tb_num(23, one, 0), tb_num(32, batch, 0), tb_num(39, ratio10(soft, batch), 1);
    text(row++, tb, COLS);
}

static int is_job(const char* w) {
    unsigned n = fm_strlen(w);
    if (fm_len < 9 + n) return 0;
    for (unsigned i = 0; i < n; i++) if (fm_buf[9 + i] != w[i]) return 0;
    return fm_len == 9 + n || fm_buf[9 + n] == ' ';
}

// a number written left-aligned at column `at` of tb; returns the column after it
static int tb_u(int at, long v) {
    char d[12];
    int k = 0;
    do d[k++] = (char)('0' + v % 10), v /= 10; while (v);
    while (k && at < COLS) tb[at++] = d[--k];
    return at;
}

enum { CT60_KFLOPS = 7216 }; // a CT60's 68060, Matt's LINPACK 100 number: for scale

static void linpack_rows(void) {
    long soft = tok("soft"), astro = tok("astro");
    row = 12;
    text_z(row++, "LINPACK 100, KFLOPS (higher is better):");
    tb_clear(), tb_text(0, "ZIGGY");
    int at = tb_u(6, soft), at2;
    tb_text(at + 1, "ASTROLABE"), at2 = tb_u(at + 11, astro);
    tb_text(at2 + 1, "CT60"), tb_u(at2 + 6, CT60_KFLOPS);
    text(row++, tb, COLS);
    tb_clear(), tb_text(0, "= ");
    tb_num(6, ratio10(astro, soft), 1), tb_text(8, "ZIGGY,");
    tb_num(20, ratio10(astro, CT60_KFLOPS), 1), tb_text(22, "a CT60's 68060");
    text(row++, tb, COLS);
}

static void roundtrip_row(void) {
    long ns = tok("ns");
    tb_clear(), tb_text(0, "1 call = ~");
    if (ns < 0) tb_text(10, "?"), tb_text(11, " us round trip: batch it!");
    else tb_text(tb_u(10, (ns + 500) / 1000), " us round trip: batch it!");
    row = 15, text(row++, tb, COLS);
}

// "results check: OK (S/C)": no failure logged, S of C calls answered by the ARM
static void done_row(void) {
    long fails = tok("failures");
    unsigned p = 9;
    while (p < fm_len && fm_buf[p] != '/') p++;
    long calls_n = 0;
    for (p++; p < fm_len && fm_buf[p] >= '0' && fm_buf[p] <= '9'; p++) calls_n = calls_n * 10 + (fm_buf[p] - '0');
    tb_clear(), tb_text(0, "results check: ");
    int at = 15;
    if (fails == 0) tb_text(at, "OK "), at += 3;
    else tb_text(at, "FAILED "), at = tb_u(at + 7, fails) + 1;
    tb_text(at, "("), at = tb_u(at + 1, tok("served")), tb_text(at, "/"), at = tb_u(at + 1, calls_n);
    tb_text(at, ")");
    row = 16, text(row++, tb, COLS);
}

static const char* const SCALAR[] = {"add", "mul", "div", "sqrt", "sin"};

// the log line in fm_buf, onto its row of the screen (a failure wraps under the table)
static void show(void) {
    if (is_job("ref")) return; // 7 raw result words: the console has them
    if (is_job("done")) return done_row();
    if (is_job("roundtrip")) return roundtrip_row();
    if (is_job("linpack")) return linpack_rows();
    if (is_job("sin4096")) return row = 11, table_row("sin4k", tok("soft64"), -1, tok("astro"));
    for (int i = 0; i < 5; i++)
        if (is_job(SCALAR[i])) return row = 6 + i, table_row(SCALAR[i], tok("soft64"), tok("astro1"), tok("astro48"));
    row = 18, wrap(fm_buf + 9, fm_len - 9);
}

#endif
