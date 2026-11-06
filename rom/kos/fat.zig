// --------------------------------------------------------------------------
// KOS's FAT reader (docs/KOS_FAT.md): FAT12, FAT16 and FAT32, read-only, GEMDOS-style 8.3 names,
// over a 512-byte sector reader the host provides (the drive ABI's diskReadBlock for drive A,
// kosDriveRead for C:). Pure Zig with no allocator, no float and no imports beyond std, so the ROM
// (rom.wasm), glass (finding a floppy program's bytes) and the native tests share it.
//
// What it accepts, and why:
//   - 512-byte sectors only (every floppy and the SD card's FAT32);
//   - Atari floppies: TOS writes a BPB with no 55 AA signature and a random serial at offset 8,
//     so neither is checked; the BPB's own numbers must add up instead;
//   - the FAT type from the cluster count (< 4085 FAT12, < 65525 FAT16, else FAT32), never from
//     the label text, as Microsoft's specification says.
// --------------------------------------------------------------------------
const std = @import("std");
const ent = @import("fat_entry.zig");
const entryOf = ent.entryOf;
const le16 = ent.le16;
const le32 = ent.le32;

pub const SECTOR = 512;
pub const Kind = enum { fat12, fat16, fat32 };
pub const Error = error{ Io, Corrupt, Unsupported };

/// Reads sector `n` into `dst`; false when it cannot (no such sector, a read error).
pub const ReadFn = *const fn (ctx: *anyopaque, n: u32, dst: *[SECTOR]u8) bool;

pub const ATTR_DIR = ent.ATTR_DIR;
pub const ATTR_VOLUME = ent.ATTR_VOLUME;
const ATTR_LFN = ent.ATTR_LFN;

pub const Entry = ent.Entry;

/// A directory: the fixed root of FAT12/16 (cluster 0), or a cluster chain.
pub const Dir = struct { cluster: u32 = 0 };

pub const Volume = struct {
    read_fn: ReadFn,
    ctx: *anyopaque,
    kind: Kind = .fat12,
    spc: u32 = 1, // sectors per cluster
    fat_start: u32 = 0,
    fat_sectors: u32 = 0,
    root_start: u32 = 0, // FAT12/16: the fixed root's first sector
    root_sectors: u32 = 0,
    root_cluster: u32 = 0, // FAT32
    data_start: u32 = 0,
    clusters: u32 = 0, // data clusters, numbered 2 .. clusters + 1
    label: [11]u8 = [_]u8{' '} ** 11,
    buf: [SECTOR]u8 = undefined,
    buf_sector: u32 = 0xFFFF_FFFF,

    pub fn mount(read_fn: ReadFn, ctx: *anyopaque) Error!Volume {
        var v = Volume{ .read_fn = read_fn, .ctx = ctx };
        const b = try v.sector(0);
        try v.parseBpb(b);
        return v;
    }

    fn parseBpb(v: *Volume, b: *const [SECTOR]u8) Error!void {
        if (le16(b, 11) != SECTOR) return error.Unsupported;
        const spc: u32 = b[13];
        const reserved: u32 = le16(b, 14);
        const nfats: u32 = b[16];
        const root_entries: u32 = le16(b, 17);
        const total: u32 = if (le16(b, 19) != 0) le16(b, 19) else le32(b, 32);
        const fatsz: u32 = if (le16(b, 22) != 0) le16(b, 22) else le32(b, 36);
        if (spc == 0 or spc > 128 or spc & (spc - 1) != 0 or reserved == 0 or nfats == 0 or nfats > 2 or fatsz == 0)
            return error.Corrupt;
        v.spc = spc;
        v.fat_start = reserved;
        v.fat_sectors = fatsz;
        v.root_start = reserved + nfats * fatsz;
        v.root_sectors = (root_entries * 32 + SECTOR - 1) / SECTOR;
        v.data_start = v.root_start + v.root_sectors;
        if (total <= v.data_start) return error.Corrupt;
        v.clusters = (total - v.data_start) / spc;
        v.kind = if (v.clusters < 4085) .fat12 else if (v.clusters < 65525) .fat16 else .fat32;
        if ((v.kind == .fat32) != (root_entries == 0)) return error.Corrupt;
        if (v.kind == .fat32) v.root_cluster = le32(b, 44);
        if (!v.fatFits()) return error.Corrupt;
        const label_at: usize = if (v.kind == .fat32) 71 else 43;
        if (b[if (v.kind == .fat32) 66 else 38] == 0x29) @memcpy(&v.label, b[label_at..][0..11]);
    }

    // The FAT holds an entry per cluster (2 .. clusters + 1).
    fn fatFits(v: *const Volume) bool {
        const n: u64 = @as(u64, v.clusters) + 2;
        const bytes: u64 = switch (v.kind) {
            .fat12 => (n * 3 + 1) / 2,
            .fat16 => n * 2,
            .fat32 => n * 4,
        };
        return bytes <= @as(u64, v.fat_sectors) * SECTOR;
    }

    pub fn sector(v: *Volume, n: u32) Error!*const [SECTOR]u8 {
        if (v.buf_sector != n) {
            v.buf_sector = 0xFFFF_FFFF;
            if (!v.read_fn(v.ctx, n, &v.buf)) return error.Io;
            v.buf_sector = n;
        }
        return &v.buf;
    }

    fn fatByte(v: *Volume, off: u32) Error!u8 {
        return (try v.sector(v.fat_start + off / SECTOR))[off % SECTOR];
    }

    /// The cluster after `c` in its chain, or null at the chain's end.
    pub fn next(v: *Volume, c: u32) Error!?u32 {
        if (c < 2 or c > v.clusters + 1) return error.Corrupt;
        const n: u32 = switch (v.kind) {
            .fat12 => blk: {
                const off = c + c / 2; // an entry may straddle two sectors: read it a byte at a time
                const w = @as(u32, try v.fatByte(off)) | @as(u32, try v.fatByte(off + 1)) << 8;
                break :blk if (c & 1 != 0) w >> 4 else w & 0xFFF;
            },
            .fat16 => @as(u32, try v.fatByte(c * 2)) | @as(u32, try v.fatByte(c * 2 + 1)) << 8,
            .fat32 => blk: {
                var w: u32 = 0;
                for (0..4) |k| w |= @as(u32, try v.fatByte(c * 4 + @as(u32, @intCast(k)))) << @intCast(8 * k);
                break :blk w & 0x0FFF_FFFF;
            },
        };
        const end: u32 = switch (v.kind) {
            .fat12 => 0xFF8,
            .fat16 => 0xFFF8,
            .fat32 => 0x0FFF_FFF8,
        };
        if (n >= end) return null;
        if (n < 2 or n > v.clusters + 1) return error.Corrupt; // a free or bad cluster mid-chain
        return n;
    }

    pub fn clusterSector(v: *const Volume, c: u32) u32 {
        return v.data_start + (c - 2) * v.spc;
    }

    pub fn root(v: *const Volume) Dir {
        return .{ .cluster = if (v.kind == .fat32) v.root_cluster else 0 };
    }

    /// The sector holding a directory's `i`-th 512-byte block, null past its end.
    pub fn dirSector(v: *Volume, d: Dir, i: u32) Error!?u32 {
        if (d.cluster == 0) return if (i < v.root_sectors) v.root_start + i else null;
        var c = d.cluster;
        var k = i / v.spc;
        var hops: u32 = 0;
        while (k > 0) : (k -= 1) {
            c = (try v.next(c)) orelse return null;
            hops += 1;
            if (hops > v.clusters) return error.Corrupt; // a chain that loops
        }
        return v.clusterSector(c) + i % v.spc;
    }

    /// Up to out.len entries of `d` (8.3, no deleted, long-name, `.`/`..` or volume entries).
    pub fn list(v: *Volume, d: Dir, out: []Entry) Error!usize {
        var n: usize = 0;
        var i: u32 = 0;
        while (try v.dirSector(d, i)) |s| : (i += 1) {
            if (i > v.clusters * v.spc + v.root_sectors) return error.Corrupt;
            const b = try v.sector(s);
            var e: usize = 0;
            while (e < SECTOR) : (e += 32) {
                const r = b[e..][0..32];
                if (r[0] == 0) return n; // the directory's end
                if (r[0] == 0xE5 or r[11] == ATTR_LFN or r[11] & ATTR_VOLUME != 0 or r[0] == '.') continue;
                if (n == out.len) return n;
                out[n] = entryOf(r);
                n += 1;
            }
        }
        return n;
    }

    /// Bytes of `e` from `offset` into `dst`; the count read (short at the file's end).
    pub fn read(v: *Volume, e: *const Entry, offset: u32, dst: []u8) Error!usize {
        if (offset >= e.size) return 0;
        const want: u32 = @intCast(@min(dst.len, e.size - offset));
        const csize = v.spc * SECTOR;
        var c = e.cluster;
        var skip = offset / csize;
        var hops: u32 = 0;
        while (skip > 0) : (skip -= 1) {
            c = (try v.next(c)) orelse return error.Corrupt;
            hops += 1;
            if (hops > v.clusters) return error.Corrupt;
        }
        var done: u32 = 0;
        var at = offset % csize;
        while (done < want) {
            const s = v.clusterSector(c) + at / SECTOR;
            const b = try v.sector(s);
            const k = @min(want - done, SECTOR - at % SECTOR);
            @memcpy(dst[done..][0..k], b[at % SECTOR ..][0..k]);
            done += k;
            at += k;
            if (at == csize and done < want) {
                c = (try v.next(c)) orelse return error.Corrupt; // shorter than its size
                hops += 1;
                if (hops > v.clusters) return error.Corrupt;
                at = 0;
            }
        }
        return done;
    }
};
