/* memset / memcpy / memmove that store WORDS. Linked ahead of picolibc, whose rv32 versions
 * are the byte loops (one sb per byte: objdump the old fw.elf's <memset>). On ZIGGY every
 * store is a blocking DDR write (~25 cycles, write-through D$), so a wasm memory.fill or
 * memory.copy (Zig @memset/@memcpy, struct copies, a plane clear) cost 25 cycles A BYTE:
 * empire spent ~0.9 of its 1.8 Mc frame in them, a 64,000-byte plane clear 1.6 Mc. Storing
 * words divides the store count by four; loads are D$ hits and cost little, so a source
 * that is not word-aligned with its destination is read byte-wise and still stored by word.
 * Same results byte for byte (the hashes prove it), only fewer bus writes.
 *
 * The native host (x86) keeps its libc; this file is rv32 firmware only (cycles.mk FW_FILES),
 * so it reaches the cycles sim, the board's monolithic image and the split system image,
 * whose table hands these three to every lean cart (sys_abi.txt `rt memcpy` & co). */
#include <stddef.h>
#include <stdint.h>

/* GCC turns a byte loop inside memset/memcpy back into a call to memset/memcpy: recursion.
 * (clang, which compiles the host-side test, does not know the pragma.) */
#if defined(__GNUC__) && !defined(__clang__)
#pragma GCC optimize("no-tree-loop-distribute-patterns")
#endif

typedef uint32_t __attribute__((__may_alias__)) w32;

static inline uint32_t load_bytes(const uint8_t* s) {
    return (uint32_t)s[0] | ((uint32_t)s[1] << 8) | ((uint32_t)s[2] << 16) | ((uint32_t)s[3] << 24);
}

void* memset(void* dst, int c, size_t n) {
    uint8_t* d = dst;
    if (n >= 8) {
        uint32_t v = (uint8_t)c;
        v |= v << 8;
        v |= v << 16;
        while ((uintptr_t)d & 3) { *d++ = (uint8_t)c; n--; }
        for (; n >= 16; n -= 16, d += 16) {
            ((w32*)d)[0] = v; ((w32*)d)[1] = v; ((w32*)d)[2] = v; ((w32*)d)[3] = v;
        }
        for (; n >= 4; n -= 4, d += 4) *(w32*)d = v;
    }
    while (n--) *d++ = (uint8_t)c;
    return dst;
}

/* Forward copy: d word-aligned after the head; s read by word when co-aligned, else by byte. */
static void copy_fwd(uint8_t* d, const uint8_t* s, size_t n) {
    if (n < 8) {
        while (n--) *d++ = *s++;
        return;
    }
    while ((uintptr_t)d & 3) { *d++ = *s++; n--; }
    if (((uintptr_t)s & 3) == 0) {
        for (; n >= 16; n -= 16, d += 16, s += 16) {
            w32 a = ((const w32*)s)[0], b = ((const w32*)s)[1], c = ((const w32*)s)[2], e = ((const w32*)s)[3];
            ((w32*)d)[0] = a; ((w32*)d)[1] = b; ((w32*)d)[2] = c; ((w32*)d)[3] = e;
        }
        for (; n >= 4; n -= 4, d += 4, s += 4) *(w32*)d = *(const w32*)s;
    } else {
        for (; n >= 4; n -= 4, d += 4, s += 4) *(w32*)d = load_bytes(s);
    }
    while (n--) *d++ = *s++;
}

/* Backward copy for an overlapping move with d > s: the tail first, words where d allows. */
static void copy_bwd(uint8_t* d, const uint8_t* s, size_t n) {
    d += n;
    s += n;
    if (n < 8) {
        while (n--) *--d = *--s;
        return;
    }
    while ((uintptr_t)d & 3) { *--d = *--s; n--; }
    if (((uintptr_t)s & 3) == 0) {
        for (; n >= 4; n -= 4) { d -= 4; s -= 4; *(w32*)d = *(const w32*)s; }
    } else {
        for (; n >= 4; n -= 4) { d -= 4; s -= 4; *(w32*)d = load_bytes(s); }
    }
    while (n--) *--d = *--s;
}

void* memcpy(void* dst, const void* src, size_t n) {
    copy_fwd(dst, src, n);
    return dst;
}

void* memmove(void* dst, const void* src, size_t n) {
    uint8_t* d = dst;
    const uint8_t* s = src;
    if (d <= s || d >= s + n) copy_fwd(d, s, n);
    else copy_bwd(d, s, n);
    return dst;
}
