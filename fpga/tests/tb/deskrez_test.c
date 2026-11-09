/* The desktop's mode word as ZIGGY's firmware writes and takes it (cycles/bdeskrez.h), over a
 * plain word, for tests/test_board_deskrez.py, which checks it against glass/src/map_cart.zig.
 *
 *   deskrez_test word MODE          -> the word bdiskapp.c leaves for ROM mode MODE, hex
 *   deskrez_test take WORD RESET    -> "<mode> <word after>": what bkos.c hands the ROM */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bdeskrez.h"

int main(int argc, char** argv) {
    if (argc == 3 && !strcmp(argv[1], "word")) {
        printf("%08x\n", bdeskrez_word((uint32_t)strtoul(argv[2], 0, 0)));
        return 0;
    }
    if (argc == 4 && !strcmp(argv[1], "take")) {
        volatile uint32_t w = (uint32_t)strtoul(argv[2], 0, 0);
        uint32_t mode = bdeskrez_take(&w, atoi(argv[3]));
        printf("%u %08x\n", mode, w);
        return 0;
    }
    fprintf(stderr, "usage: deskrez_test word MODE | take WORD RESET\n");
    return 2;
}
