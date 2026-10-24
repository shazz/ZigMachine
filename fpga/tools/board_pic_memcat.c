/* memcat ADDR BYTES: mmap /dev/mem at ADDR and write BYTES to stdout. For tools/board_pic.py: the
 * cart window is a no-map reserved region under Linux, so dd on /dev/mem reads nothing; an mmap
 * does (as glass's devmem.zig). Built for the board's ARM by board_pic.py with `zig cc`. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char** argv) {
    if (argc != 3) return fprintf(stderr, "usage: memcat ADDR BYTES\n"), 2;
    unsigned long a = strtoul(argv[1], 0, 0), n = strtoul(argv[2], 0, 0), pg = a & ~4095ul, off = a - pg;
    int fd = open("/dev/mem", O_RDONLY | O_SYNC);
    if (fd < 0) return perror("open /dev/mem"), 1;
    unsigned char* m = mmap(0, n + off, PROT_READ, MAP_SHARED, fd, (off_t)pg);
    if (m == MAP_FAILED) return perror("mmap"), 1;
    for (unsigned long i = 0; i < n;) {
        ssize_t w = write(1, m + off + i, n - i > 65536 ? 65536 : n - i);
        if (w <= 0) return 1;
        i += (unsigned long)w;
    }
    return 0;
}
