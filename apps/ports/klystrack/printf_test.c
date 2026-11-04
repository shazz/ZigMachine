/* kestrel_printf.c against the C library's vsnprintf, on the host: every format klystrack's sources pass to
 * font_write_args / console_write_args, and the conversions it handles itself, over edge values (0, negatives,
 * INT_MIN, widths shorter and longer, truncating buffer sizes).   make -C apps/ports/klystrack printf-test */
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

int kestrel_vsnprintf(char *b, size_t n, const char *fmt, va_list va);

static int fails, runs;
static void check(size_t n, const char *fmt, ...)
{
    char a[256], b[256];
    memset(a, 0x55, sizeof a); memset(b, 0x55, sizeof b);
    va_list v1, v2;
    va_start(v1, fmt); va_copy(v2, v1);
    int ra = vsnprintf(a, n, fmt, v1), rb = kestrel_vsnprintf(b, n, fmt, v2);
    va_end(v2); va_end(v1);
    runs++;
    if (ra != rb || memcmp(a, b, sizeof a)) { fails++; printf("FAIL [%s] n=%zu: libc %d \"%s\" kestrel %d \"%s\"\n", fmt, n, ra, n ? a : "", rb, n ? b : ""); }
}

int main(void)
{
    static const int ints[] = { 0, 1, -1, 7, 9, 10, 15, 16, 99, 100, 255, 256, -255, 4095, 65535, 123456789, INT_MAX, INT_MIN };
    static const char *ifmt[] = { "%d", "%i", "%02d", "%03d", "%04d", "%3d", "%+d", "% d", "%-5d|", "%-05d|", "%+05d", "% 4d",
        "%u", "%x", "%X", "%02X", "%02x", "%03X", "%04X", "%-4X|", "%+X", "%0*X", "%*d", "%-*d|", "%c|", "%3c|", "%-3c|" };
    static const char *strs[] = { "", "A", "Starport", "a rather longer string of text, 40 chars", NULL };
    static const char *sfmt[] = { "%s", "%-16s|", "%-10s|", "%10s|", "%.3s|", "%5.2s|", "%-6.4s|", "[%s]%%", "%*s|" };
    static const size_t sizes[] = { 0, 1, 2, 5, 8, 256 };
    for (unsigned z = 0; z < sizeof sizes / sizeof *sizes; z++) {
        size_t n = sizes[z];
        for (unsigned f = 0; f < sizeof ifmt / sizeof *ifmt; f++)
            for (unsigned i = 0; i < sizeof ints / sizeof *ints; i++) {
                if (strchr(ifmt[f], '*')) { check(n, ifmt[f], 4, ints[i]); check(n, ifmt[f], 0, ints[i]); check(n, ifmt[f], -6, ints[i]); }
                else if (strchr(ifmt[f], 'c')) check(n, ifmt[f], 'A' + (ints[i] & 15));
                else check(n, ifmt[f], ints[i]);
            }
        for (unsigned f = 0; f < sizeof sfmt / sizeof *sfmt; f++)
            for (unsigned i = 0; i < sizeof strs / sizeof *strs; i++) {
                if (!strs[i]) continue;                 /* NULL %s: undefined; musl and glibc differ */
                if (strchr(sfmt[f], '*')) { check(n, sfmt[f], 12, strs[i]); check(n, sfmt[f], -12, strs[i]); }
                else check(n, sfmt[f], strs[i]);
            }
        check(n, "%02d:%02d", 3, 7);
        check(n, "%s %02X %c%c %d%%", "ins", 0xAB, 'x', 'y', -42);
        check(n, "%.1f %5.2f %+.1f %lu %#x %ld", 1.25, -3.5, 0.75, 9ul, 255, -7l);   /* handed to libc */
        check(n, "no conversion at all");
        check(n, "%");
    }
    printf("printf_test: %d of %d formats differ\n", fails, runs);
    return fails != 0;
}
