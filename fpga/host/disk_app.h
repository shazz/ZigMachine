/* GEM over a data disk: what docs/sealed-loader.js does each frame once it booted GEM for a
 * disk that is not bootable (ST Replay's), for the native host (`--data-disk`, host_io.c) and
 * the board firmware (cycles/bdiskapp.c). After demo.frame(), in the browser's order:
 *
 *   1. pollCartRequest(): a request (3 = run the FAT file named at getCartTagPtr/Len, 4 =
 *      back to GEM) is the browser's cart swap. Here it is only reported: a native host
 *      cannot swap its linked cart, and on the board the glass does it (FPGA_GLASS.md,
 *      "Programs off a data disk"). The browser stops polling while it swaps; so do these,
 *      except after a program that is not on the disk (no such file, or not a program: only
 *      a type-0 file instantiates), where the browser's swap fails and the cart keeps polling.
 *   2. insertDisk(1): the browser's diskApp, true for GEM booted for a data disk and for the
 *      program it launched (the disk stays in).
 *   3. once isBooted(): the FAT listing (zmd_dir.h) into diskDirPtr() with the ROM's record
 *      size and cap, then setDiskFileCount(n). Once per boot: the browser's diskDirSet. A
 *      program launched off the disk starts with it set (the browser hands GEM only).
 * A cart without an export gets no call for it (host_dapp's NULLs, tools/host_bridges.py). */
#ifndef ZM_DISK_APP_H
#define ZM_DISK_APP_H

#include "host.h"
#include "wasm-rt.h"
#include "zmd_dir.h"

typedef struct {
    const zmd_dir_t* dir; /* the mounted data disk */
    int dir_set;          /* the listing handed (sealed-loader.js diskDirSet) */
    int requested;        /* a request that swaps the cart: no more polls */
    uint32_t req;         /* the last request */
    uint8_t name[ZMD_FIND_MAX];
    uint32_t name_len;      /* the cart's tag bytes (req 1 and 3), at most ZMD_FIND_MAX kept */
    const zmd_file_t* file; /* req 3: the program on the disk it names, else NULL */
} disk_app_t;

/* new Uint8Array(memory.buffer, ptr, n): its RangeError is a trap here. */
static inline uint8_t* disk_app_mem(struct w2c_env* e, uint32_t ptr, uint64_t n) {
    if ((uint64_t)ptr + n > e->memory.size) wasm_rt_trap(WASM_RT_TRAP_OOB);
    return e->memory.data + ptr;
}

static inline void disk_app_request(struct w2c_env* e, disk_app_t* s, uint32_t req) {
    s->req = req;
    s->name_len = 0;
    s->file = 0;
    s->requested = req != 3;
    if ((req != 1 && req != 3) || !host_dapp.tag_ptr || !host_dapp.tag_len) return;
    uint32_t len = host_dapp.tag_len(HOST_CART(e));
    const uint8_t* tag = disk_app_mem(e, host_dapp.tag_ptr(HOST_CART(e)), len);
    s->name_len = len;
    memcpy(s->name, tag, len < ZMD_FIND_MAX ? len : ZMD_FIND_MAX);
    const zmd_file_t* f = req == 3 ? zmd_dir_find(s->dir, tag, len) : 0;
    s->file = f && f->type == 0 ? f : 0;
    s->requested = req != 3 || s->file;
}

/* The listing, once the cart says it is booted (the browser's `diskDirSet` block). */
static inline void disk_app_listing(struct w2c_env* e, disk_app_t* s) {
    if (s->dir_set || !host_dapp.dir_ptr || !host_dapp.is_booted || !host_dapp.is_booted(HOST_CART(e))) return;
    uint32_t ent = w2c_rom_deskDirEntryBytes(&e->rom), maxf = w2c_rom_deskDirMaxFiles(&e->rom);
    uint32_t ptr = host_dapp.dir_ptr(HOST_CART(e));
    if (ptr > e->memory.size) wasm_rt_trap(WASM_RT_TRAP_OOB);
    int64_t n = zmd_dir_records(s->dir, ent, maxf, e->memory.data + ptr, e->memory.size - ptr);
    if (n < 0) wasm_rt_trap(WASM_RT_TRAP_OOB);
    if (!host_dapp.set_count) wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE); /* demo.setDiskFileCount is not a function */
    host_dapp.set_count(HOST_CART(e), (u32)n);
    s->dir_set = 1;
}

/* After the cart's frame: the request this frame made (0: none), see the top. */
static inline uint32_t disk_app_frame(struct w2c_env* e, disk_app_t* s) {
    uint32_t req = 0;
    if (!s->requested && host_dapp.poll && (req = host_dapp.poll(HOST_CART(e))) != 0) disk_app_request(e, s, req);
    if (host_dapp.insert_disk) host_dapp.insert_disk(HOST_CART(e), 1);
    disk_app_listing(e, s);
    return req;
}

#endif
