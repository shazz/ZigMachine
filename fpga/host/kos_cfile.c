/* KOS GEMDOS's writes to C: in the native host (docs/KOS_GEMDOS.md §7): env.kosFileOp's host half, as
 * docs/kos-cfile.js is the page's. KFS (docs/kos-cfs.wasm, rom/kos/kfs*.zig), wasm2c'd as `kfs`, edits
 * host_cdisk's image (--c-image) at the file level; --c-image-rw also writes each sector it changes
 * back to the image file. The cart's request (12 words, rom/kos/kfs_abi.zig) is bounded and copied into
 * KFS's buffer exactly as the page does it, so the two hosts answer and write alike. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

#include "disk.h"
#include "kfs.h"

#define KFS_SECTOR 512u
#define KFS_DATA_MAX 32768u
#define KFS_PATH_MAX 127u
#define KFS_ERANGE ((uint32_t)-64)
#define KFS_EDRIVE ((uint32_t)-46)

static w2c_kfs g_kfs;
static int g_fd = -1; /* --c-image-rw: the image file, written through */

static uint8_t* kmem(uint32_t at, uint32_t n) {
    wasm_rt_memory_t* m = w2c_kfs_memory(&g_kfs);
    return (uint64_t)at + n <= m->size ? m->data + at : NULL;
}

u32 w2c_env_kfsRead(struct w2c_env* e, u32 sector, u32 dst) {
    (void)e;
    uint64_t at = (uint64_t)sector * KFS_SECTOR;
    uint8_t* d = kmem(dst, KFS_SECTOR);
    if (!host_cdisk.data || !d || at + KFS_SECTOR > host_cdisk.size) return 0;
    memcpy(d, host_cdisk.data + at, KFS_SECTOR);
    return 1;
}

u32 w2c_env_kfsWrite(struct w2c_env* e, u32 sector, u32 src) {
    (void)e;
    uint64_t at = (uint64_t)sector * KFS_SECTOR;
    uint8_t* s = kmem(src, KFS_SECTOR);
    if (!host_cdisk.data || !s || at + KFS_SECTOR > host_cdisk.size) return 0;
    memcpy((uint8_t*)host_cdisk.data + at, s, KFS_SECTOR); /* read_image's buffer is the host's own */
    if (g_fd >= 0 && pwrite(g_fd, s, KFS_SECTOR, (off_t)at) != (ssize_t)KFS_SECTOR) return 0;
    return 1;
}

static int span(uint64_t mem_size, uint32_t at, uint32_t n) { return (uint64_t)at + n <= mem_size; }

/* host/disk.h host_kos_file_hook: a TOS code; the generation into the request's last word. */
static uint32_t kos_file_op(uint8_t* mem, uint64_t mem_size, uint32_t req) {
    if (req % 4 || !span(mem_size, req, 48)) return KFS_ERANGE;
    uint32_t w[12];
    memcpy(w, mem + req, sizeof w);
    if (!host_cdisk.data) return KFS_EDRIVE;
    if (w[0] == 0) {
        uint32_t g = w2c_kfs_kfsGen(&g_kfs);
        memcpy(mem + req + 44, &g, 4);
        return g & 0x7FFFFFFFu;
    }
    uint32_t len = w[5], data = w[6], path = w[7], plen = w[8], path2 = w[9], p2len = w[10];
    if (plen > KFS_PATH_MAX || p2len > KFS_PATH_MAX || len > KFS_DATA_MAX) return KFS_ERANGE;
    if (!span(mem_size, path, plen) || !span(mem_size, path2, p2len) || !span(mem_size, data, len)) return KFS_ERANGE;
    uint32_t buf = w2c_kfs_kfsBuf(&g_kfs);
    uint8_t* k = kmem(buf, 256 + KFS_DATA_MAX);
    if (!k) return KFS_ERANGE;
    memcpy(k, mem + path, plen);
    memcpy(k + 128, mem + path2, p2len);
    memcpy(k + 256, mem + data, len);
    uint32_t r = w2c_kfs_kfsServe(&g_kfs, w[0], w[1], w[2], w[3], w[4], plen, p2len, len);
    uint32_t g = w2c_kfs_kfsGen(&g_kfs);
    memcpy(mem + req + 44, &g, 4);
    return r;
}

/* --c-image (rw_path NULL: writes stay in memory, as on the page) or --c-image-rw (into the file too). */
void host_kos_file_mount(const char* rw_path) {
    wasm2c_kfs_instantiate(&g_kfs, NULL);
    if (rw_path && (g_fd = open(rw_path, O_WRONLY)) < 0) {
        fprintf(stderr, "host: cannot write C: image %s\n", rw_path);
        exit(1);
    }
    host_kos_file_hook = kos_file_op;
}
