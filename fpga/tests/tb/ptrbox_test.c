/* The pointer's box words as ZIGGY's firmware writes them (cycles/bptrbox.h), for
 * tests/test_board_ptrbox.py, which decodes them as glass does (src/mouse.zig planeBox).
 *
 *   ptrbox_test planes ON MODE0 STRIDE0 .. MODE3 STRIDE3  -> "<x word> <y word>", hex
 *   ptrbox_test cart X0 Y0 X1 Y1                          -> the same, or "none" (the planes decide)
 *   ptrbox_test whole MODE STRIDE                         -> vplane_whole, 0/1 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bptrbox.h"

static uint32_t arg(const char* s) { return (uint32_t)strtoll(s, 0, 0); }

static int words(bptrbox_rect r) {
    printf("%08x %08x\n", bptrbox_xword(r), bptrbox_yword(r));
    return 0;
}

int main(int argc, char** argv) {
    if (argc == 4 && !strcmp(argv[1], "whole")) {
        printf("%d\n", vplane_whole((uint8_t)arg(argv[2]), (uint16_t)arg(argv[3])));
        return 0;
    }
    if (argc == 11 && !strcmp(argv[1], "planes")) {
        uint8_t mode[4];
        uint16_t stride[4];
        for (int p = 0; p < 4; p++) mode[p] = (uint8_t)arg(argv[3 + 2 * p]), stride[p] = (uint16_t)arg(argv[4 + 2 * p]);
        return words(bptrbox_planes((unsigned)arg(argv[2]), mode, stride));
    }
    if (argc == 6 && !strcmp(argv[1], "cart")) {
        bptrbox_rect r;
        if (!bptrbox_cart(arg(argv[2]), arg(argv[3]), arg(argv[4]), arg(argv[5]), &r)) return puts("none") < 0;
        return words(r);
    }
    fprintf(stderr, "usage: ptrbox_test planes ON MODE0 STRIDE0 .. | cart X0 Y0 X1 Y1 | whole MODE STRIDE\n");
    return 2;
}
