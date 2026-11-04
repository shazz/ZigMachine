/* The drive: env.diskReadBlock as docs/sealed-loader.js serves it, for the native host
 * (`host --disk X.zmd`) and the board firmware (ZIGGY reading the disk ZWINDOW placed in
 * DDR, cycles/bdisk.c). One copy of the rules, so tests/test_board_disk.py can hold it
 * against the browser's own function.
 *
 * The browser's, line by line: no disk -> 0. The block's bytes are
 * buf.subarray(start, start + 512) with start = (block >>> 0) * 512: the block is unsigned,
 * so 0x80000000 and up are past the end like any other (before `>>> 0` the browser got them
 * signed and subarray counted them from the end). Nothing there -> 0, dst never looked at.
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

/* TypedArray.prototype.subarray's index for the non-negative ones it gets: clamped to len. */
static inline int64_t host_disk_index(int64_t i, int64_t len) { return i < len ? i : len; }

static inline int64_t host_disk_read(host_disk_t* d, uint32_t block, uint32_t dst, uint8_t* mem, uint64_t mem_size) {
    if (!d->data) return 0;
    int64_t start = (int64_t)block * HOST_DISK_BLOCK;
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

/* KOS's C: (docs/KOS_FAT.md F5, env.kosDriveRead), the native host's half: `count` sectors of
 * unit 2 from host_cdisk's image (--c-image) into the cart's memory at `dst`, as docs/sealed-loader.js
 * serves its C: image. The answer is the sectors read; 0 for any refusal, never a trap (the board's
 * answer to a timeout is 0 too): no image, another unit, count 0 or over HOST_KOS_MAX_SECTORS, a run
 * past the image's end, a dst off a word or whose bytes pass the memory's. All or nothing. */
#define HOST_KOS_UNIT_C 2u
#define HOST_KOS_MAX_SECTORS 64u

extern host_disk_t host_cdisk;

static inline uint32_t host_kos_drive_read(host_disk_t* d, uint32_t unit, uint32_t sector, uint32_t count, uint32_t dst,
                                           uint8_t* mem, uint64_t mem_size) {
    if (!d->data || unit != HOST_KOS_UNIT_C || count == 0 || count > HOST_KOS_MAX_SECTORS || dst % 4) return 0;
    uint64_t from = (uint64_t)sector * HOST_DISK_BLOCK, n = (uint64_t)count * HOST_DISK_BLOCK;
    if (from + n > d->size || (uint64_t)dst + n > mem_size) return 0;
    memcpy(mem + dst, d->data + from, (size_t)n);
    d->reads++;
    d->bytes += (uint32_t)n;
    return count;
}

#endif
