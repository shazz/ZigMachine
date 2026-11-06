/* KOS's C: writes, the request block as ZIGGY's firmware writes it (cycles/bkosfreq.h), into a plain buffer,
 * for tests/test_kos_file.py, which decodes it with glass/src/map_cart.zig's rule (glass's own reader is
 * glass/src/kos_file.zig, tested there); and the firmware's reading of an answer.
 *
 *   kosfreq_test SEQ F0 .. F10        -> the block's words, hex, one line (F: KF_OP .. KF_PATH2_LEN)
 *   kosfreq_test answer SEQ ACK DONE  -> what bkosfreq_answer makes of them (hex) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bkosfreq.h"

static uint32_t num(const char* s) { return (uint32_t)strtoul(s, 0, 0); }

int main(int argc, char** argv) {
    uint32_t w[KOS_FILE_WORDS + 1];
    memset(w, 0xA5, sizeof w); /* what was there before: the block must cover it */
    if (argc == 5 && strcmp(argv[1], "answer") == 0) {
        w[KF_ACK] = num(argv[3]);
        w[KF_DONE] = num(argv[4]);
        printf("%08x\n", bkosfreq_answer(w, num(argv[2])));
        return 0;
    }
    if (argc != 2 + KF_FIELDS) {
        fprintf(stderr, "usage: kosfreq_test SEQ F0..F10 | answer SEQ ACK DONE\n");
        return 2;
    }
    uint32_t f[KF_FIELDS];
    for (int i = 0; i < KF_FIELDS; i++) f[i] = num(argv[2 + i]);
    bkosfreq_write(w, num(argv[1]), f);
    for (int i = 0; i <= KOS_FILE_WORDS; i++) printf("%08x%c", w[i], i == KOS_FILE_WORDS ? '\n' : ' ');
    return 0;
}
