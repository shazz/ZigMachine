/* Dhrystone 2.1 as a sliced job. Own code, CC0.
 *
 * dhry_1.c / dhry_2.c are Weicker's, patched at build time only to take the run count as an argument (gen.py).
 * A slice is one dhry_main(n): its timed region is the original's own loop, bracketed by times(), which here
 * answers microseconds. Every slice prints the "X: v / should be: w" table; check_table() compares each pair,
 * so a miscompiled run (or a corrupted value, bench_break 1) fails. DMIPS = Dhrystones/s / 1757 (the VAX 11/780). */
#include "bench.h"
#include <string.h>
#include <stdio.h>

extern int dhry_main(int nruns);
extern long Begin_Time, End_Time;

static slicer sl;
static int table_ok, pairs;

static void begin(void) { sl_begin(&sl, 200, 5000000); table_ok = 1; pairs = 0; }

static const char *after(const char *line, const char *key) {
    for (; *line && *line != '\n'; line++) if (!strncmp(line, key, strlen(key))) return line + strlen(key);
    return 0;
}
static const char *next_line(const char *l) { while (*l && *l != '\n') l++; return *l ? l + 1 : l; }
static const char *trim(const char *s) { while (*s == ' ') s++; return s; }
static int same_line(const char *a, const char *b) {   /* equal up to the end of the line, trailing blanks aside */
    while (*a && *a != '\n' && *a == *b) { a++; b++; }
    while (*a == ' ') a++;
    while (*b == ' ') b++;
    return (*a == '\n' || !*a) && (*b == '\n' || !*b);
}

static int check_pair(const char *got_line, const char *want, int runs) {
    const char *got = after(got_line, ":");
    if (!got) return 0;
    got = trim(got); want = trim(want);
    if (*want == '(') return 1;                          /* "(implementation-dependent)" */
    if (!strncmp(want, "Number_Of_Runs + 10", 19)) { char t[16]; snprintf(t, sizeof t, "%d\n", runs + 10); return same_line(got, t); }
    return same_line(got, want);
}

static int check_table(int runs) {
    const char *prev = 0;
    for (const char *l = rt_out; *l; l = next_line(l)) {
        const char *w = after(l, "should be:");
        if (w && prev) { pairs++; if (!check_pair(prev, w, runs)) return 0; }
        prev = l;
    }
    return 1;
}

static void corrupt(void) {
    for (char *l = rt_out; *l; l = (char *)next_line(l)) {
        if (!after(l, "Int_Glob:")) continue;
        while (*l && *l != '\n') l++;
        l[-1] = '9';                                     /* the value's last digit */
        return;
    }
}

static int step(void) {
    int runs = (int)sl_unit(&sl);
    rt_heap_reset(); rt_out_reset();
    dhry_main(runs);
    if (bench_break == 1) corrupt();
    if (!check_table(runs)) table_ok = 0;
    sl_note(&sl, (u32)(End_Time - Begin_Time));
    return sl_more(&sl);
}

static void finish(bench_res *r) {
    res_clear(r);
    res_check(r, table_ok && pairs > 10, table_ok ? (pairs > 10 ? "final values match the original's" : "no values printed") : "A FINAL VALUE DIFFERS");
    if (sl.clocked && sl.us) {
        u64 dps = sl.work * 1000000ull * 1000 / sl.us;
        res_val(r, "dhrystone", "DMIPS", dps / 1757);
        res_val(r, "dhrystone_per_s", "Dhrystones/s", dps);
    }
}

const bench_job job_dhry = { "dhrystone", "Dhrystone 2.1", begin, step, finish };
