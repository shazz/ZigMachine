/* cycles/bdinval.h on the host, for tests/blitter_ref/dinval_check.zig: the line invalidates
 * are recorded instead of issued, so the check can hold them against the bytes the machine's
 * own blitter changed. */
#include <stdint.h>

#define BDI_MAX 4096u
static uintptr_t g_lines[BDI_MAX];
static unsigned g_n;

static void dinval_record(uintptr_t a) {
    if (g_n < BDI_MAX) g_lines[g_n] = a;
    g_n++;
}

#define BDI_INVAL_LINE(a) dinval_record(a)
#include "bdinval.h"

/* bdi_range() for op `cmd` with its registers in the region r: its result, and the lines. */
int dinval_host_range(const uint8_t* r, uint8_t cmd, const uintptr_t** lines, unsigned* n) {
    g_n = 0;
    int ok = bdi_range(r, cmd);
    *lines = g_lines;
    *n = g_n < BDI_MAX ? g_n : BDI_MAX;
    return g_n > BDI_MAX ? -1 : ok;
}
