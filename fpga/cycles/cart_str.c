/* Libc string functions a lean cart image may call that the system's runtime table (sys_abi.txt) does not
 * forward. GCC's loop distribution turns a byte-scanning loop in cart.c into a call to strlen (a wasi-libc
 * C program's own strlen, wasm2c'd, is exactly such a loop: pt2-clone, ChipNomad), and a lean image links
 * with -nostdlib. Built without that pass, or this strlen would become a call to itself. */
#include <stddef.h>

__attribute__((optimize("no-tree-loop-distribute-patterns"))) size_t strlen(const char* s)
{
    const char* p = s;
    while (*p) p++;
    return (size_t)(p - s);
}
