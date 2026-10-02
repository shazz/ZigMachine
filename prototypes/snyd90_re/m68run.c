/* m68run: run routines of a Hatari RAM dump on Musashi (a reference model of the
 * original 68000 code, used to validate the hand models and to generate frames).
 *
 *   m68run IN.bin OUT.bin cmd...
 *     call:ADDR      jsr ADDR, run until it returns
 *     irq:ADDR       enter ADDR as an interrupt (PC+SR stacked), run until rte
 *     key:HEX        what $FFFC02 reads from now on
 *     reg:N:HEX      set data/address register N (0-7 = d0-d7, 8-15 = a0-a7)
 *     frames:N:vbl:ADDR:calls:A,B,C...   N times: irq VBL then call each routine
 *     exec:START:STOP  run from START until PC == STOP (a main loop's straight-line body)
 *     loop:N:vbl:ADDR:exec:START:STOP    N times: irq VBL, then exec START..STOP
 *     dump:FILE        write RAM now (the run goes on)
 *     hw:FILE          write the $FF8000 register file now (palette at +$240)
 *     ymlog:FILE       from now on, 16 YM registers after every loop: frame
 *
 * RAM is the dump's 512 KB; $FF8000-$FFFFFF is a plain register file whose
 * writes are logged to stderr for the colour / shifter registers when -v.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "m68k.h"

static unsigned char ram[0x80000];
static unsigned char hw[0x8000]; /* $FF8000.. */
static unsigned key = 0;
static unsigned char ym[16], ym_sel;
static FILE *ymlog = NULL; /* ymlog:FILE -- 16 YM registers after every loop/frames frame */
static int verbose = 0;
#define SENT 0x7FF00u

static unsigned rd8(unsigned a) {
    a &= 0xFFFFFF;
    if (a < 0x80000) return ram[a];
    if (a >= 0xFF8000) {
        if (a == 0xFFFC02) return key;
        return hw[a - 0xFF8000];
    }
    return 0;
}
static void wr8(unsigned a, unsigned v) {
    a &= 0xFFFFFF;
    if (a < 0x80000) { ram[a] = v; return; }
    if (a >= 0xFF8000) {
        hw[a - 0xFF8000] = v;
        if ((a & 0xFFFF03) == 0xFF8800) ym_sel = v & 15;
        else if ((a & 0xFFFF03) == 0xFF8802) ym[ym_sel] = v;
        if (verbose && a >= 0xFF8200 && a < 0xFF8262) fprintf(stderr, "w $%06X = %02X\n", a, v);
    }
}
unsigned int m68k_read_memory_8(unsigned int a) { return rd8(a); }
unsigned int m68k_read_memory_16(unsigned int a) { return (rd8(a) << 8) | rd8(a + 1); }
unsigned int m68k_read_memory_32(unsigned int a) { return (m68k_read_memory_16(a) << 16) | m68k_read_memory_16(a + 2); }
void m68k_write_memory_8(unsigned int a, unsigned int v) { wr8(a, v & 0xFF); }
void m68k_write_memory_16(unsigned int a, unsigned int v) { wr8(a, (v >> 8) & 0xFF); wr8(a + 1, v & 0xFF); }
void m68k_write_memory_32(unsigned int a, unsigned int v) { m68k_write_memory_16(a, v >> 16); m68k_write_memory_16(a + 2, v); }
unsigned int m68k_read_disassembler_8(unsigned int a) { return rd8(a); }
unsigned int m68k_read_disassembler_16(unsigned int a) { return m68k_read_memory_16(a); }
unsigned int m68k_read_disassembler_32(unsigned int a) { return m68k_read_memory_32(a); }

static void run_until_sent(void) {
    long n = 0;
    while (m68k_get_reg(NULL, M68K_REG_PC) != SENT) {
        m68k_execute(1);
        if (++n > 50000000) { fprintf(stderr, "runaway at $%X\n", m68k_get_reg(NULL, M68K_REG_PC)); exit(2); }
    }
}

static void call(unsigned addr) {
    unsigned sp = m68k_get_reg(NULL, M68K_REG_A7) - 4;
    m68k_write_memory_32(sp, SENT);
    m68k_set_reg(M68K_REG_A7, sp);
    m68k_set_reg(M68K_REG_PC, addr);
    run_until_sent();
}

static void exec_to(unsigned start, unsigned stop) {
    long n = 0;
    m68k_set_reg(M68K_REG_PC, start);
    while (m68k_get_reg(NULL, M68K_REG_PC) != stop) {
        m68k_execute(1);
        if (++n > 50000000) { fprintf(stderr, "runaway at $%X\n", m68k_get_reg(NULL, M68K_REG_PC)); exit(2); }
    }
}

static void irq(unsigned addr) {
    unsigned sr = m68k_get_reg(NULL, M68K_REG_SR);
    unsigned sp = m68k_get_reg(NULL, M68K_REG_A7) - 6;
    m68k_write_memory_16(sp, sr);
    m68k_write_memory_32(sp + 2, SENT);
    m68k_set_reg(M68K_REG_A7, sp);
    m68k_set_reg(M68K_REG_SR, 0x2400);
    m68k_set_reg(M68K_REG_PC, addr);
    run_until_sent();
    m68k_set_reg(M68K_REG_SR, sr);
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: m68run IN OUT cmd...\n"); return 1; }
    FILE *f = fopen(argv[1], "rb");
    if (!f || fread(ram, 1, sizeof ram, f) != sizeof ram) { fprintf(stderr, "bad dump\n"); return 1; }
    fclose(f);
    m68k_init();
    m68k_set_cpu_type(M68K_CPU_TYPE_68000);
    m68k_pulse_reset();
    m68k_set_reg(M68K_REG_SR, 0x2300);
    m68k_set_reg(M68K_REG_A7, 0x7FE00);
    m68k_set_reg(M68K_REG_PC, SENT);
    for (int i = 3; i < argc; i++) {
        char *c = argv[i];
        if (!strcmp(c, "-v")) verbose = 1;
        else if (!strncmp(c, "call:", 5)) call(strtoul(c + 5, NULL, 16));
        else if (!strncmp(c, "irq:", 4)) irq(strtoul(c + 4, NULL, 16));
        else if (!strncmp(c, "exec:", 5)) {
            char *e; unsigned a = strtoul(c + 5, &e, 16);
            exec_to(a, strtoul(e + 1, NULL, 16));
        } else if (!strncmp(c, "loop:", 5)) {
            char *e; unsigned n = strtoul(c + 5, &e, 10);
            unsigned vbl = strtoul(strstr(e, "vbl:") + 4, NULL, 16);
            char *x = strstr(e, "exec:") + 5;
            unsigned a = strtoul(x, &e, 16), b = strtoul(e + 1, NULL, 16);
            for (unsigned k = 0; k < n; k++) {
                irq(vbl); exec_to(a, b);
                if (ymlog) fwrite(ym, 1, 16, ymlog);
            }
        } else if (!strncmp(c, "ymlog:", 6)) {
            ymlog = fopen(c + 6, "wb");
        } else if (!strncmp(c, "hw:", 3)) {
            FILE *g = fopen(c + 3, "wb");
            fwrite(hw, 1, sizeof hw, g);
            fclose(g);
        } else if (!strncmp(c, "dump:", 5)) {
            FILE *g = fopen(c + 5, "wb");
            fwrite(ram, 1, sizeof ram, g);
            fclose(g);
        }
        else if (!strncmp(c, "key:", 4)) key = strtoul(c + 4, NULL, 16);
        else if (!strncmp(c, "pokel:", 6)) {
            char *e; unsigned a = strtoul(c + 6, &e, 16);
            m68k_write_memory_32(a, strtoul(e + 1, NULL, 16));
        }
        else if (!strncmp(c, "reg:", 4)) {
            char *e; unsigned r = strtoul(c + 4, &e, 10);
            m68k_set_reg(r < 8 ? M68K_REG_D0 + r : M68K_REG_A0 + (r - 8), strtoul(e + 1, NULL, 16));
        } else if (!strncmp(c, "frames:", 7)) {
            char *e; unsigned n = strtoul(c + 7, &e, 10);
            unsigned vbl = strtoul(strstr(e, "vbl:") + 4, NULL, 16);
            char *cl = strstr(e, "calls:") + 6;
            for (unsigned k = 0; k < n; k++) {
                irq(vbl ? vbl : m68k_read_memory_32(0x70));
                char buf[512]; strncpy(buf, cl, sizeof buf - 1); buf[sizeof buf - 1] = 0;
                for (char *t = strtok(buf, ","); t; t = strtok(NULL, ",")) call(strtoul(t, NULL, 16));
            }
        } else if (!strncmp(c, "search:", 7)) {
            /* search:N:REF:LO:HI:vbl:ADDR:calls:A,B  -- run N frames, after each
             * report how many bytes of [LO,HI) differ from REF (print the best) */
            char *e; unsigned n = strtoul(c + 7, &e, 10);
            char ref[256]; char *p = e + 1; char *q = strchr(p, ':');
            memcpy(ref, p, q - p); ref[q - p] = 0;
            unsigned lo = strtoul(q + 1, &e, 16), hi = strtoul(e + 1, &e, 16);
            static unsigned char rb[0x80000];
            FILE *g = fopen(ref, "rb"); fread(rb, 1, sizeof rb, g); fclose(g);
            unsigned vbl = strtoul(strstr(e, "vbl:") + 4, NULL, 16);
            char *xs = strstr(e, "exec:");
            unsigned xa = 0, xb = 0;
            if (xs) { char *f; xa = strtoul(xs + 5, &f, 16); xb = strtoul(f + 1, NULL, 16); }
            char *cl = xs ? "" : strstr(e, "calls:") + 6;
            unsigned best = ~0u, bestk = 0;
            for (unsigned k = 1; k <= n; k++) {
                irq(vbl ? vbl : m68k_read_memory_32(0x70));
                if (xs) exec_to(xa, xb);
                char buf[512]; strncpy(buf, cl, sizeof buf - 1); buf[sizeof buf - 1] = 0;
                for (char *t = strtok(buf, ","); t; t = strtok(NULL, ",")) call(strtoul(t, NULL, 16));
                unsigned d = 0;
                for (unsigned a = lo; a < hi; a++) d += ram[a] != rb[a];
                if (d < best) { best = d; bestk = k; }
                if (d < 64) fprintf(stderr, "frame %u: %u bytes differ\n", k, d);
            }
            fprintf(stderr, "best frame %u: %u bytes differ\n", bestk, best);
        } else { fprintf(stderr, "bad cmd %s\n", c); return 1; }
    }
    if (ymlog) fclose(ymlog);
    f = fopen(argv[2], "wb");
    fwrite(ram, 1, sizeof ram, f);
    fclose(f);
    fprintf(stderr, "a6=$%X\n", m68k_get_reg(NULL, M68K_REG_A6));
    return 0;
}
