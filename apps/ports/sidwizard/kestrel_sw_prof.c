/* Measuring builds only (included by kestrel_sw.c; sw_run_c64 calls it after each C64 sample):
 *   SW_PROFILE_IRQ  the share of C64 samples spent in IRQ handlers (I flag set), logged after 15 s
 *   SW_PROFILE_PC   every 5 s: the main program's 24 hottest PCs (sampled once a C64 sample) and the 6 most read
 *                   I/O registers (kestrel_sw_cpu.c sw_rd_io): where kestrel_sw_idle.c and sw_io_clockless came from
 * make OUT=build/prof EXTRA=-DSW_PROFILE_PC link, then run.mjs with CART=apps/ports/sidwizard/build/prof/... */

#if defined SW_PROFILE_IRQ || defined SW_PROFILE_PC
static void sw_log_top(const char *fmt, uint32_t *hist, int n, int top)
{
    char b[64];
    for (int k = 0; k < top; k++) {
        uint32_t best = 0; int at = 0;
        for (int a = 0; a < n; a++) if (hist[a] > best) { best = hist[a]; at = a; }
        if (!best) break;
        snprintf(b, sizeof b, fmt, at, best); kestrel_log(b);
        hist[at] = 0;
    }
    memset(hist, 0, (size_t)n * sizeof *hist);
}

static void sw_profile_sample(void)
{
    char b[64];
#ifdef SW_PROFILE_IRQ
    static unsigned irq, all;
    all++; if (cRSID_C64.CPU.ST & 4) irq++;
    if (all == 22050 * 15) { snprintf(b, sizeof b, "irq share %u of %u samples", irq, all); kestrel_log(b); }
#endif
#ifdef SW_PROFILE_PC
    static uint32_t hist[65536], seen;
    if (!(cRSID_C64.CPU.ST & 4)) hist[cRSID_C64.CPU.PC & 0xFFFF]++;
    if (++seen % (22050 * 5)) return;
    uint32_t tot = 0;
    for (int a = 0; a < 65536; a++) tot += hist[a];
    snprintf(b, sizeof b, "pc: main %u of %u", tot, seen); kestrel_log(b);
    sw_log_top("pc %04x %u", hist, 65536, 24);
    sw_log_top("io d%03x %u", sw_io_hist, 0x1000, 6);
#endif
    (void)b;
}
#endif
