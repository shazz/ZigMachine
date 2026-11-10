/* The pointer's box word as ZIGGY's firmware writes it (cycles/bptrbox.h), for
 * tests/test_board_ptrbox.py, which decodes it as glass does (src/mouse.zig planeBox).
 *
 *   ptrbox_test ON MODE0 STRIDE0 MODE1 STRIDE1 MODE2 STRIDE2 MODE3 STRIDE3  -> the word, hex
 *   ptrbox_test whole MODE STRIDE                                           -> vplane_whole, 0/1 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bptrbox.h"

int main(int argc, char** argv) {
    if (argc == 4 && !strcmp(argv[1], "whole")) {
        printf("%d\n", vplane_whole((uint8_t)strtoul(argv[2], 0, 0), (uint16_t)strtoul(argv[3], 0, 0)));
        return 0;
    }
    if (argc == 10) {
        uint8_t mode[4];
        uint16_t stride[4];
        for (int p = 0; p < 4; p++) {
            mode[p] = (uint8_t)strtoul(argv[2 + 2 * p], 0, 0);
            stride[p] = (uint16_t)strtoul(argv[3 + 2 * p], 0, 0);
        }
        printf("%08x\n", bptrbox_word((unsigned)strtoul(argv[1], 0, 0), mode, stride));
        return 0;
    }
    fprintf(stderr, "usage: ptrbox_test ON MODE0 STRIDE0 .. MODE3 STRIDE3 | whole MODE STRIDE\n");
    return 2;
}
