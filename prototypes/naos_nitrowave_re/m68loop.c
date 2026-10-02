/* m68loop: run a Nitrowave part's MAIN LOOP on Musashi from a Hatari RAM dump,
 * with a VBL (IRQ 4 -> $70) each time the loop stops, and save RAM at chosen
 * frames. The reference model ("oracle") of the original code.
 *
 *   m68loop DUMP.bin PC FRAMES OUTPREFIX [frame,frame,...]
 *     PC      where the dump was taken (the main loop's `stop`), resumed there
 *     FRAMES  VBLs to run; after VBL k (and the main loop's pass up to its next
 *             stop) RAM is written to OUTPREFIX.<k> for each listed k
 *
 * $FF8209 (video counter low) reads $10 so the fullscreen sync loops end and
 * the jmp (a0,d0.w) lands in its nop slide; $FFFC00/02 read 0 (no key); the
 * rest of $FF8000.. is a plain register file. RAM is the dump's 512 KB.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "m68k.h"

static unsigned char ram[0x100000];
static unsigned char hw[0x8000];
static unsigned watch_lo = 0, watch_hi = 0;

static unsigned rd8(unsigned a) {
    a &= 0xFFFFFF;
    if (a < 0x100000) return ram[a];
    if (a == 0xFF8209) return 0x10;
    if (a == 0xFFFC00 || a == 0xFFFC02) return 0;
    if (a >= 0xFF8000) return hw[a - 0xFF8000];
    return 0;
}
static void wr8(unsigned a, unsigned v) {
    a &= 0xFFFFFF;
    if (a >= watch_lo && a < watch_hi && (getenv("WATCHALL") || ram[a] != (v & 0xFF))) fprintf(stderr, "write $%X = %02X at pc $%X\n", a, v, m68k_get_reg(NULL, M68K_REG_PPC));
    if (a < 0x100000) ram[a] = v;
    else if (a >= 0xFF8000) hw[a - 0xFF8000] = v;
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

/* Run until the CPU sits in a STOP (PC just past a $4E72 and not moving). */
static long cyc = 0;
static void run_to_stop(void) {
    long n = 0;
    unsigned last = ~0u;
    for (;;) {
        cyc += m68k_execute(64);
        unsigned pc = m68k_get_reg(NULL, M68K_REG_PC);
        if (pc == last && m68k_read_memory_16(pc - 4) == 0x4E72) return;
        last = pc;
        if (++n > 2000000) { fprintf(stderr, "runaway at $%X\n", pc); exit(2); }
    }
}

static int wanted(const char *list, unsigned k) {
    char buf[4096];
    strncpy(buf, list, sizeof buf - 1);
    buf[sizeof buf - 1] = 0;
    for (char *t = strtok(buf, ","); t; t = strtok(NULL, ",")) if ((unsigned)atoi(t) == k) return 1;
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 5) { fprintf(stderr, "usage: m68loop DUMP PC FRAMES OUTPREFIX [frames]\n"); return 1; }
    FILE *f = fopen(argv[1], "rb");
    if (!f || fread(ram, 1, sizeof ram, f) < 0x80000) { fprintf(stderr, "bad dump\n"); return 1; }
    fclose(f);
    unsigned pc = strtoul(argv[2], NULL, 16);
    if (getenv("WATCH")) { char *e; watch_lo = strtoul(getenv("WATCH"), &e, 16); watch_hi = strtoul(e + 1, NULL, 16); }
    unsigned frames = strtoul(argv[3], NULL, 10);
    const char *list = argc > 5 ? argv[5] : "";
    m68k_init();
    m68k_set_cpu_type(M68K_CPU_TYPE_68000);
    m68k_pulse_reset();
    m68k_set_reg(M68K_REG_SR, 0x2700);
    m68k_set_reg(M68K_REG_A7, 0x7FFF2);
    m68k_set_reg(M68K_REG_PC, pc);
    { /* DUMP.regs (regs.py): d0..d7,a0..a7 as Hatari printed them at the dump */
        char name[512], line[512];
        snprintf(name, sizeof name, "%s.regs", argv[1]);
        FILE *g = fopen(name, "r");
        if (g && fgets(line, sizeof line, g)) {
            char *p = line;
            for (int r = 0; r < 16 && *p; r++) { m68k_set_reg(r < 8 ? M68K_REG_D0 + r : M68K_REG_A0 + (r - 8), strtoul(p, &p, 16)); if (*p == ',') p++; }
        } else fprintf(stderr, "note: no %s, registers start at 0\n", name);
        if (g) fclose(g);
    }
    run_to_stop();
    for (unsigned k = 1; k <= frames; k++) {
        m68k_set_irq(4);
        m68k_execute(200);
        m68k_set_irq(0);
        run_to_stop();
        if (getenv("CYC")) fprintf(stderr, "frame %u: %ld cycles, pc $%X\n", k, cyc, m68k_get_reg(NULL, M68K_REG_PC));
        cyc = 0;
        if (wanted(list, k)) {
            char name[512];
            snprintf(name, sizeof name, "%s.%u", argv[4], k);
            FILE *o = fopen(name, "wb");
            fwrite(ram, 1, sizeof ram, o);
            fclose(o);
        }
    }
    return 0;
}
