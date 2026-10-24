/* A disk's executable BOOT SECTOR (ZigCart format v2, docs/FLOPPY_DISK.md), run as the
 * browser runs it (docs/sealed-loader.js): the sector's own 1 KB of wasm, through the wint
 * interpreter (host/wint.h), so the board shows sysinfo's "No virus" screen and
 * replicants_emlyn's crew note before their carts, with no per-disk build step.
 *
 * The browser's, step by step: docs/zmdisk.js parseV2 calls block 0 executable when the disk
 * is v2 (wasm at 0, "ZMDISK" at 0x400) and the 1 KB's big-endian words sum to $1234; the
 * loader instantiates those 1024 bytes with its env (memory, hwVideoBase, beep, every other
 * import a stub answering 0), runs hwInit then boot(); each frame hwClear, frame(dt),
 * pollCartRequest() (2 = chainload: the disk's cart, or GEM when the descriptor names none),
 * then every plane isPlaneEnabled says, rendered.
 *
 * What the sandbox adds (the sector comes off a card and must not break the console): a
 * sector wint refuses or that traps is left out and the cart boots as if there were none;
 * boot() runs on BOOTSEC_FUEL_BOOT instructions, each frame on BOOTSEC_FUEL_FRAME, and the
 * phase ends after BOOTSEC_MAX_FRAMES whatever the sector says. */
#ifndef ZM_BOOTSEC_H
#define ZM_BOOTSEC_H

#include <stdint.h>

#include "wint.h"

#define BOOTSEC_BYTES 1024u
#define BOOTSEC_CHAINLOAD 2u
#define BOOTSEC_FUEL_BOOT (16u << 20)  /* novirus' boot() takes ~0.9 M */
#define BOOTSEC_FUEL_FRAME (1u << 20)  /* a frame() is a few instructions */
#define BOOTSEC_MAX_FRAMES 1800u        /* 30 s at 60 Hz: replicants_emlyn holds 240 */

typedef struct {
    wint w;
    int f_boot, f_frame, f_plane, f_poll;
    uint32_t video_base; /* hwVideoBase()'s answer */
    void (*beep)(void);  /* the sector's `beep`: NULL = silent */
    uint32_t frames;     /* frames run */
    wint_status st;      /* the first failure; the phase ends on it */
} bootsec_t;

/* parseV2's rule: a v2 disk whose 1 KB boot sector sums to $1234. */
int bootsec_executable(const uint8_t* disk, uint32_t size);

/* Instantiate the sector of `disk` (bootsec_executable) over the shared memory and run
 * boot(). The caller has already run the machine's hwInit. WINT_OK, or why it did not run. */
wint_status bootsec_start(bootsec_t* b, const uint8_t* disk, uint8_t* mem, uint32_t mem_len, uint32_t video_base,
                          void (*beep)(void));

/* One frame: frame(dt) then pollCartRequest(). 1 = the sector asked to chainload (render
 * this frame, then stop), 0 = go on, -1 = stop now (it trapped, or the frame cap). */
int bootsec_frame(bootsec_t* b, float dt);

/* isPlaneEnabled(p); a trap reads as off and ends the phase after this frame. */
int bootsec_plane_on(bootsec_t* b, uint32_t p);

/* A name for wint's status, for the console. */
const char* bootsec_status(wint_status st);

#endif
