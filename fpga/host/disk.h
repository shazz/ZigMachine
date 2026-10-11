/* The drive: env.diskReadBlock as docs/sealed-loader.js serves it, for the native host
 * (`host --disk X.zmd`) and the board firmware (ZIGGY reading the disk ZWINDOW placed in
 * DDR, cycles/bdisk.c). One copy of the rules, so tests/test_board_disk.py can hold it
 * against the browser's own function.
 *
 * The browser's, line by line: no disk -> 0. The block's bytes are
 * buf.subarray(block * 512, block * 512 + 512): block arrives SIGNED (a wasm i32 is a JS
 * Number), and subarray counts a negative index from the end, so 0xFFFFFFFE reads the
 * disk's second-to-last block. Nothing there (past the end) -> 0, dst never looked at.
 * Else new Uint8Array(memory.buffer, dstOff, n) throws a RangeError for a negative dstOff
 * or one whose n bytes pass the memory's end: HOST_DISK_RANGE_ERROR, which the caller
 * turns into a trap. Else copy and return n: 512, or fewer for a partial last block.
 * Synchronous: the bytes are there when the call returns. */
#ifndef ZM_HOST_DISK_H
#define ZM_HOST_DISK_H

#include <stdint.h>
#include <string.h>

#define HOST_DISK_BLOCK 512
#define HOST_DISK_RANGE_ERROR (-1)

typedef struct {
    const uint8_t* data; /* NULL: no disk in the drive */
    uint32_t size;
    uint32_t reads; /* calls that copied something, and the bytes they copied */
    uint32_t bytes;
} host_disk_t;

/* The drive's one disk: tools/host_gen.py defines it in every cart's env.c, empty. */
extern host_disk_t host_disk;

/* TypedArray.prototype.subarray's index: negative counts from the end, then clamped to [0, len]. */
static inline int64_t host_disk_index(int64_t i, int64_t len) {
    if (i < 0) return i + len > 0 ? i + len : 0;
    return i < len ? i : len;
}

static inline int64_t host_disk_read(host_disk_t* d, uint32_t block, uint32_t dst, uint8_t* mem, uint64_t mem_size) {
    if (!d->data) return 0;
    int64_t start = (int64_t)(int32_t)block * HOST_DISK_BLOCK;
    int64_t from = host_disk_index(start, d->size), to = host_disk_index(start + HOST_DISK_BLOCK, d->size);
    if (to <= from) return 0;
    int64_t n = to - from;
    /* a negative dstOff is, unsigned, past any memory under 2 GiB: one test covers both */
    if ((uint64_t)dst + (uint64_t)n > mem_size) return HOST_DISK_RANGE_ERROR;
    memcpy(mem + dst, d->data + from, (size_t)n);
    d->reads++;
    d->bytes += (uint32_t)n;
    return n;
}

#endif
