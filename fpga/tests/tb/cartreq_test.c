/* The request block as ZIGGY's firmware writes it (cycles/bcartreq.h), into a plain buffer,
 * for tests/test_board_cartreq.py, which decodes it with glass/src/map_cart.zig's rule.
 *
 *   cartreq_test REQ NAMEHEX   -> the block's words, hex, one line */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bcartreq.h"

int main(int argc, char** argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: cartreq_test REQ NAMEHEX\n");
        return 2;
    }
    static uint8_t name[256];
    size_t len = strlen(argv[2]) / 2;
    if (len > sizeof name) return 2;
    for (size_t i = 0; i < len; i++) sscanf(argv[2] + 2 * i, "%2hhx", &name[i]);
    uint32_t w[CART_REQ_HEAD_WORDS + CART_REQ_NAME_MAX / 4 + 1];
    memset(w, 0xA5, sizeof w); /* what was there before: the block must cover it */
    bcartreq_write(w, (uint32_t)strtoul(argv[1], 0, 0), name, (uint32_t)len);
    for (size_t i = 0; i < sizeof w / sizeof w[0]; i++) printf("%s%08x", i ? " " : "", w[i]);
    putchar('\n');
    return 0;
}
