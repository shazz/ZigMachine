/* What a native KESTREL cart (cycles/native/native.mk) needs beyond the generated table
 * (gen/zm_sys_abi.h): the few machine numbers it pokes, and, for the hand-written assembly,
 * the table indices and header offsets as plain numbers. native_check.c holds every one of
 * those against the generated header and memmap, so a table change fails the build instead
 * of calling the wrong entry. Included by C and by .S (cpp). */
#ifndef ZM_NATIVE_H
#define ZM_NATIVE_H

/* machine/sdk/memmap.zig (checked against build/vdump/zm_memmap.h by native_check.c). */
#define NATIVE_PAGES 112              /* SHARED_PAGES: the header must say what the system has */
#define NATIVE_REG_BACKGROUND 0x04    /* in the video registers: the border/background RGBA */
#define NATIVE_CART_RAM_BASE 0x100000 /* the cart window: a wasm cart's statics start here */
/* The cart's own bytes in the shared memory: the text the ROM draws. CART_HIGH tells the
 * machine where the cart's RAM ends (hwRamAlloc would hand out what is above it). */
#define NATIVE_TEXT_AT NATIVE_CART_RAM_BASE
#define NATIVE_CART_HIGH (NATIVE_CART_RAM_BASE + 0x100)
#define NATIVE_BORDER_RGBA 0xFF402000 /* opaque, a dark blue (bytes R,G,B,A in memory) */
#define GEM_BLACK 0
#define GEM_WHITE 1

/* For the assembly: zm_sys_table's fn[] index of each entry it calls (fn[] starts at byte 12),
 * and zm_cart_hdr's size (rv32: every field 4 bytes, the tag 16). */
#define NATIVE_MAGIC 0x41434d5a   /* ZM_CART_HDR_MAGIC */
#define NATIVE_VERSION 0x00010000 /* ZM_SYS_ABI_VERSION: table 1.0 */
#define NATIVE_TABLE_FN 12
#define NATIVE_IX_w2c_env_memory 0
#define NATIVE_IX_guiOpenPlane 63
#define NATIVE_IX_guiRect 65
#define NATIVE_IX_guiText 68
#define NATIVE_IX_hwVideoBase 85
#define NATIVE_IX_romInstallPalettePlane 87
#define NATIVE_HDR_BYTES 96

#ifndef __ASSEMBLER__
#include "zm_sys_abi.h"

/* Call table entry `ix` as a function of type `type`. */
#define SYS(ix, type) ((type)zm_sys->fn[ix])

/* A cart with no songs, input, disk app or --call exports: every bridge is all NULLs and both
 * lists end at once, so one zeroed block of more words than the largest bridge (10) serves
 * for all of them (the system checks each field for NULL: host/audio_bridge.c, binput.c). */
static const void* const native_none[16];
#define NATIVE_NO_BRIDGES                                                                    \
    .songs = (const struct host_song_bridge*)native_none,                                    \
    .input = (const struct host_input_bridge*)native_none,                                   \
    .dapp = (const struct host_disk_app_bridge*)native_none,                                 \
    .exports = (const struct host_export*)native_none, .song_files = (const struct zm_song*)native_none
#endif

#endif
