/* A data disk's FAT listing as GEM gets it, for the native host (`host --data-disk X.zmd`)
 * and the board firmware (cycles/bdiskapp.c): one copy of the rules, held against the
 * browser's own code by tests/test_board_gemdisk.py.
 *
 * The browser's, step by step:
 *  - docs/zmdisk.js parseDisk: v1 ("ZMDISK" at 0, FAT at 0x300, count at 0x2e4, no date;
 *    boot-sector BE word sum 0x1234 = bootable, 0 = data disk, else corrupt) or v2 (a wasm
 *    boot sector, "ZMDISK" at 0x400, FAT at 0x800, count at 0x4f4, date at 0x4f0; bootable
 *    iff the 1 KB sum is 0x1234 and the descriptor names a cart: length at 0x40c != 0). Under 0x600 bytes, no magic or a corrupt v1 sum: throws.
 *  - readFat: 32-byte entries name[16] start[4] len[4] type[1] into an OBJECT keyed by
 *    name, so a repeated name keeps its first place and takes the last entry's values, and
 *    Object.keys lists array-index names ("0", "17", ...) first in numeric order ("__proto__"
 *    sets the object's prototype instead, so it is never listed). A name is
 *    TextDecoder's (UTF-8, U+FFFD for bad bytes, a leading BOM dropped) cut at the first
 *    NUL that no line break follows (cstr's /\0.*$/). An entry whose start/len words pass
 *    the end throws (DataView); a type byte past the end is undefined, & 0xff = 0.
 *  - sealed-loader.js: the first deskDirMaxFiles() names, each a record of
 *    deskDirEntryBytes(): TextEncoder(name)[0..16], type at +16, u32 LE len at +17, u32 LE
 *    date (v2's, else 0) at +21; the records zeroed first.
 * Beyond the browser: at most ZMD_DIR_MAX FAT entries (the format's FAT holds 24). */
#ifndef ZM_ZMD_DIR_H
#define ZM_ZMD_DIR_H

#include <stdint.h>
#include <string.h>

#define ZMD_DIR_MAX 256
#define ZMD_DIR_KEY 48 /* 16 bytes, each at worst one U+FFFD (3 bytes) */
#define ZMD_DIR_NAME 16
#define ZMD_DIR_MIN_ENT 25 /* name 16 + type 1 + size 4 + date 4 */

enum { ZMD_DIR_OK = 0, ZMD_DIR_SHORT = -1, ZMD_DIR_MAGIC = -2, ZMD_DIR_CORRUPT = -3, ZMD_DIR_FAT = -4,
       ZMD_DIR_TOO_MANY = -5, ZMD_DIR_RANGE = -6, ZMD_DIR_LAYOUT = -7 };

typedef struct {
    uint8_t key[ZMD_DIR_KEY];
    uint8_t key_len, type;
    uint32_t start, len;
} zmd_file_t;

typedef struct {
    int bootable, v2;
    uint32_t date, n; /* n: distinct names, in Object.keys order */
    zmd_file_t files[ZMD_DIR_MAX];
} zmd_dir_t;

static inline uint32_t zmd_le32(const uint8_t* p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

static inline uint32_t zmd_put_cp(uint32_t cp, uint32_t* out, uint32_t n) { out[n] = cp; return n + 1; }

/* TextDecoder("utf-8").decode, fatal = false: the WHATWG decoder, one U+FFFD per maximal bad subpart. */
static inline uint32_t zmd_utf8_decode(const uint8_t* b, uint32_t len, uint32_t* out) {
    uint32_t n = 0, cp = 0, need = 0, seen = 0, lo = 0x80, hi = 0xBF, i = 0;
    if (len >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) i = 3; /* the BOM is dropped */
    while (i < len) {
        uint8_t c = b[i];
        if (need == 0) {
            i++;
            if (c <= 0x7F) n = zmd_put_cp(c, out, n);
            else if (c >= 0xC2 && c <= 0xDF) need = 1, cp = c & 0x1F;
            else if (c >= 0xE0 && c <= 0xEF) need = 2, cp = c & 0xF, lo = c == 0xE0 ? 0xA0 : 0x80, hi = c == 0xED ? 0x9F : 0xBF;
            else if (c >= 0xF0 && c <= 0xF4) need = 3, cp = c & 7, lo = c == 0xF0 ? 0x90 : 0x80, hi = c == 0xF4 ? 0x8F : 0xBF;
            else n = zmd_put_cp(0xFFFD, out, n);
            continue;
        }
        if (c < lo || c > hi) { /* the bad byte starts over: not consumed */
            need = seen = cp = 0, lo = 0x80, hi = 0xBF;
            n = zmd_put_cp(0xFFFD, out, n);
            continue;
        }
        i++, lo = 0x80, hi = 0xBF, cp = cp << 6 | (c & 0x3F);
        if (++seen == need) n = zmd_put_cp(cp, out, n), need = seen = cp = 0;
    }
    return need ? zmd_put_cp(0xFFFD, out, n) : n;
}

/* cstr's .replace(/\0.*$/, ""): `.` stops at a line break, so the cut is the first NUL after the last one. */
static inline uint32_t zmd_cstr_cut(const uint32_t* cp, uint32_t n) {
    uint32_t from = 0;
    for (uint32_t i = 0; i < n; i++)
        if (cp[i] == '\n' || cp[i] == '\r' || cp[i] == 0x2028 || cp[i] == 0x2029) from = i + 1;
    for (uint32_t i = from; i < n; i++)
        if (cp[i] == 0) return i;
    return n;
}

/* TextEncoder: code points (no surrogates: the decoder makes none) to UTF-8. */
static inline uint32_t zmd_utf8_encode(const uint32_t* cp, uint32_t n, uint8_t* out) {
    uint32_t k = 0;
    for (uint32_t i = 0; i < n; i++) {
        uint32_t c = cp[i];
        if (c < 0x80) out[k++] = (uint8_t)c;
        else if (c < 0x800) out[k++] = (uint8_t)(0xC0 | c >> 6), out[k++] = (uint8_t)(0x80 | (c & 0x3F));
        else if (c < 0x10000)
            out[k++] = (uint8_t)(0xE0 | c >> 12), out[k++] = (uint8_t)(0x80 | (c >> 6 & 0x3F)), out[k++] = (uint8_t)(0x80 | (c & 0x3F));
        else
            out[k++] = (uint8_t)(0xF0 | c >> 18), out[k++] = (uint8_t)(0x80 | (c >> 12 & 0x3F)),
            out[k++] = (uint8_t)(0x80 | (c >> 6 & 0x3F)), out[k++] = (uint8_t)(0x80 | (c & 0x3F));
    }
    return k;
}

/* A name's bytes as the browser keys it (decode, cut, re-encode): key[] gets <= 48 bytes. */
static inline uint32_t zmd_key(const uint8_t* b, uint32_t len, uint8_t* key) {
    uint32_t cp[ZMD_DIR_NAME + 1];
    uint32_t n = zmd_utf8_decode(b, len, cp);
    return zmd_utf8_encode(cp, zmd_cstr_cut(cp, n), key);
}

/* A canonical array index ("0", or no leading 0, up to 2^32 - 2): Object.keys lists it first. */
static inline int zmd_index(const zmd_file_t* f, uint64_t* v) {
    if (f->key_len == 0 || f->key_len > 10 || (f->key[0] == '0' && f->key_len > 1)) return 0;
    *v = 0;
    for (uint32_t i = 0; i < f->key_len; i++) {
        if (f->key[i] < '0' || f->key[i] > '9') return 0;
        *v = *v * 10 + (f->key[i] - '0');
    }
    return *v <= 0xFFFFFFFEull;
}

#include "zmd_dir_fat.h"

#endif
