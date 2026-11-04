/* KOS's C: request block as ZIGGY's firmware writes it (cycles/bkosreq.h), into a plain buffer,
 * for tests/test_kos_drive.py, which decodes it with glass/src/map_cart.zig's rule; the
 * firmware's reading of an answer; and the native host's C: (host/disk.h host_kos_drive_read).
 *
 *   kosreq_test SEQ UNIT SECTOR COUNT OFFSET      -> the block's words, hex, one line
 *   kosreq_test answer SEQ ACK DONE               -> what bkosreq_answer makes of them
 *   kosreq_test host IMG UNIT SECTOR COUNT DST MEM -> host/disk.h's answer over an IMG-byte image
 *                                                    (0: none) and a MEM-byte memory */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bkosreq.h"
#include "disk.h"

host_disk_t host_cdisk;

static uint32_t num(const char* s) { return (uint32_t)strtoul(s, 0, 0); }

int main(int argc, char** argv) {
    uint32_t w[KOS_DRIVE_WORDS + 1];
    memset(w, 0xA5, sizeof w); /* what was there before: the block must cover it */
    if (argc == 5 && strcmp(argv[1], "answer") == 0) {
        w[KD_ACK] = num(argv[3]);
        w[KD_DONE] = num(argv[4]);
        printf("%d\n", (int)bkosreq_answer(w, num(argv[2])));
        return 0;
    }
    if (argc == 8 && strcmp(argv[1], "host") == 0) {
        static uint8_t img[1 << 16], mem[1 << 16];
        uint32_t size = num(argv[2]), msize = num(argv[7]);
        if (size > sizeof img || msize > sizeof mem) return 2;
        host_cdisk = (host_disk_t){.data = size ? img : NULL, .size = size};
        printf("%u\n", host_kos_drive_read(&host_cdisk, num(argv[3]), num(argv[4]), num(argv[5]), num(argv[6]), mem, msize));
        return 0;
    }
    if (argc != 6) {
        fprintf(stderr, "usage: kosreq_test SEQ UNIT SECTOR COUNT OFFSET | answer SEQ ACK DONE | host ...\n");
        return 2;
    }
    bkosreq_write(w, num(argv[1]), num(argv[2]), num(argv[3]), num(argv[4]), num(argv[5]));
    for (size_t i = 0; i < sizeof w / sizeof w[0]; i++) printf("%s%08x", i ? " " : "", w[i]);
    putchar('\n');
    return 0;
}
