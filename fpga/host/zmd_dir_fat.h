/* zmd_dir.h's second half: the disk's header and FAT (zmdisk.js parseDisk + readFat), the
 * Object.keys order, and the loader's records. Included by zmd_dir.h only. */
#ifndef ZM_ZMD_DIR_FAT_H
#define ZM_ZMD_DIR_FAT_H

/* The ST rule: the sum of the first `words` big-endian 16-bit words. */
static inline uint32_t zmd_be_sum(const uint8_t* b, uint32_t words) {
    uint32_t s = 0;
    for (uint32_t i = 0; i < words; i++) s = (s + (uint32_t)(b[2 * i] << 8 | b[2 * i + 1])) & 0xFFFF;
    return s;
}

/* files[key] = entry: a new key goes last, a known one keeps its place and takes the values. */
static inline int zmd_put(zmd_dir_t* d, const zmd_file_t* f) {
    if (f->key_len == 9 && memcmp(f->key, "__proto__", 9) == 0) return ZMD_DIR_OK; /* sets the prototype: no key */
    for (uint32_t i = 0; i < d->n; i++)
        if (d->files[i].key_len == f->key_len && memcmp(d->files[i].key, f->key, f->key_len) == 0) {
            d->files[i] = *f;
            return ZMD_DIR_OK;
        }
    if (d->n == ZMD_DIR_MAX) return ZMD_DIR_TOO_MANY;
    d->files[d->n++] = *f;
    return ZMD_DIR_OK;
}

/* Object.keys: the array-index keys first, ascending (a stable insertion sort), then the rest as inserted. */
static inline void zmd_order(zmd_dir_t* d) {
    uint32_t idx = 0;
    for (uint32_t i = 0; i < d->n; i++) {
        uint64_t v, w;
        if (!zmd_index(&d->files[i], &v)) continue;
        zmd_file_t f = d->files[i];
        uint32_t j = i;
        while (j > idx) d->files[j] = d->files[j - 1], j--; /* past the strings, to the indices' end */
        while (j > 0 && zmd_index(&d->files[j - 1], &w) && w > v) d->files[j] = d->files[j - 1], j--;
        d->files[j] = f;
        idx++;
    }
}

static inline int zmd_read_fat(zmd_dir_t* d, const uint8_t* b, uint32_t size, uint32_t base, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        uint64_t e = base + (uint64_t)i * 32;
        if (e + 0x18 > size) return ZMD_DIR_FAT; /* DataView.getUint32 past the end: RangeError */
        zmd_file_t f;
        f.key_len = (uint8_t)zmd_key(b + e, (uint32_t)(size - e < 16 ? size - e : 16), f.key);
        f.start = zmd_le32(b + e + 0x10);
        f.len = zmd_le32(b + e + 0x14);
        f.type = e + 0x18 < size ? b[e + 0x18] : 0;
        int rc = zmd_put(d, &f);
        if (rc) return rc;
    }
    zmd_order(d);
    return ZMD_DIR_OK;
}

/* parseDisk, as far as the drive state GEM sees: bootable, v2, date, the files. */
static inline int zmd_dir_parse(const uint8_t* b, uint32_t size, zmd_dir_t* d) {
    d->bootable = d->v2 = 0;
    d->date = d->n = 0;
    if (size < 0x600) return ZMD_DIR_SHORT;
    if (b[0] == 0x00 && b[1] == 0x61 && b[2] == 0x73 && b[3] == 0x6d) { /* v2: a wasm boot sector */
        if (memcmp(b + 0x400, "ZMDISK", 6) != 0) return ZMD_DIR_MAGIC;
        d->v2 = 1;
        d->bootable = zmd_be_sum(b, 512) == 0x1234;
        d->date = zmd_le32(b + 0x4f0);
        return zmd_read_fat(d, b, size, 0x800, (uint32_t)(b[0x4f4] | b[0x4f5] << 8));
    }
    if (memcmp(b, "ZMDISK", 6) != 0) return ZMD_DIR_MAGIC;
    uint32_t sum = zmd_be_sum(b, 256);
    if (sum != 0x1234 && sum != 0) return ZMD_DIR_CORRUPT;
    d->bootable = sum == 0x1234;
    return zmd_read_fat(d, b, size, 0x300, (uint32_t)(b[0x2e4] | b[0x2e5] << 8));
}

/* The loader's records into dst (`room` bytes there before the memory's end): returns how many,
 * or ZMD_DIR_RANGE where the browser's Uint8Array over them throws, ZMD_DIR_LAYOUT for a record
 * too small for its fields (the ROM's is 25). */
static inline int64_t zmd_dir_records(const zmd_dir_t* d, uint32_t ent, uint32_t maxf, uint8_t* dst, uint64_t room) {
    if (ent < ZMD_DIR_MIN_ENT) return ZMD_DIR_LAYOUT;
    uint32_t n = d->n < maxf ? d->n : maxf;
    if ((uint64_t)n * ent > room) return ZMD_DIR_RANGE;
    memset(dst, 0, (size_t)n * ent);
    for (uint32_t i = 0; i < n; i++) {
        const zmd_file_t* f = &d->files[i];
        uint8_t* r = dst + (size_t)i * ent;
        memcpy(r, f->key, f->key_len < ZMD_DIR_NAME ? f->key_len : ZMD_DIR_NAME);
        r[16] = f->type;
        for (int k = 0; k < 4; k++) r[17 + k] = (uint8_t)(f->len >> 8 * k), r[21 + k] = (uint8_t)(d->date >> 8 * k);
    }
    return n;
}

#define ZMD_FIND_MAX 256

/* The file the browser's mountedDisk.files[name] finds for a cart's request (name as the
 * cart wrote it: decoded like a FAT name, without the NUL cut), or NULL. */
static inline const zmd_file_t* zmd_dir_find(const zmd_dir_t* d, const uint8_t* name, uint32_t len) {
    uint32_t cp[ZMD_FIND_MAX];
    uint8_t key[ZMD_FIND_MAX * 3];
    if (len > ZMD_FIND_MAX) return 0; /* a key is <= 48 code points: from <= 195 bytes */
    uint32_t k = zmd_utf8_encode(cp, zmd_utf8_decode(name, len, cp), key);
    for (uint32_t i = 0; i < d->n; i++)
        if (d->files[i].key_len == k && memcmp(d->files[i].key, key, k) == 0) return &d->files[i];
    return 0;
}

#endif
