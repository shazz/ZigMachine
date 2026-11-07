// --------------------------------------------------------------------------
// The image writer's disk (kfs.zig): KOS's FAT reader (fat.zig) over a sector device that can also
// WRITE, and the FAT table's own edits: read an entry raw, set one in every FAT copy, find free
// clusters, link and free chains. Every write goes through put(), which drops the reader's one-sector
// buffer when it holds that sector, so a read after a write sees the write.
//
// Ordering, for a crash between two sector writes (kfs.zig): data first into clusters the FAT still
// calls free (nothing on the disk refers to them yet), then the FAT (FAT 1, then FAT 2), then the
// directory entry. A cut in between leaves at worst lost clusters or FAT copies that differ, both of
// which fsck.fat repairs with no file damaged; never a file pointing at free space.
// --------------------------------------------------------------------------
const std = @import("std");
const fat = @import("fat.zig");

const S = fat.SECTOR;
pub const Error = error{ Io, Corrupt, Unsupported, Full };

pub const Dev = struct {
    ctx: *anyopaque,
    read_fn: fat.ReadFn,
    write_fn: *const fn (ctx: *anyopaque, n: u32, src: *const [S]u8) bool,
};

pub const Disk = struct {
    dev: Dev,
    v: fat.Volume,
    nfats: u32,
    fsinfo: u32, // FAT32's FSInfo sector (0: none)
    scratch: [S]u8 = undefined,

    pub fn mount(dev: Dev) Error!Disk {
        var d = Disk{ .dev = dev, .v = try fat.Volume.mount(dev.read_fn, dev.ctx), .nfats = 0, .fsinfo = 0 };
        d.nfats = (d.v.root_start - d.v.fat_start) / d.v.fat_sectors; // FAT32: root_start is the data's start
        if (d.v.kind == .fat32) {
            const b = try d.v.sector(0);
            d.fsinfo = std.mem.readInt(u16, b[48..50], .little);
        }
        return d;
    }

    /// Sector `n` into the scratch buffer (a copy: put() may be called on it).
    pub fn get(d: *Disk, n: u32) Error!*[S]u8 {
        d.scratch = (try d.v.sector(n)).*;
        return &d.scratch;
    }

    pub fn put(d: *Disk, n: u32, b: *const [S]u8) Error!void {
        if (d.v.buf_sector == n) d.v.buf_sector = 0xFFFF_FFFF;
        if (!d.dev.write_fn(d.dev.ctx, n, b)) return error.Io;
    }

    pub fn csize(d: *const Disk) u32 {
        return d.v.spc * S;
    }

    pub fn endMark(d: *const Disk) u32 {
        return switch (d.v.kind) {
            .fat12 => 0xFFF,
            .fat16 => 0xFFFF,
            .fat32 => 0x0FFF_FFFF,
        };
    }

    /// Cluster `c`'s FAT entry as stored (0 free, >= the end mark's range: a chain's end).
    pub fn entry(d: *Disk, c: u32) Error!u32 {
        return switch (d.v.kind) {
            .fat12 => blk: {
                const off = c + c / 2;
                const w = @as(u32, try d.byte(off)) | @as(u32, try d.byte(off + 1)) << 8;
                break :blk if (c & 1 != 0) w >> 4 else w & 0xFFF;
            },
            .fat16 => @as(u32, try d.byte(c * 2)) | @as(u32, try d.byte(c * 2 + 1)) << 8,
            .fat32 => blk: {
                var w: u32 = 0;
                for (0..4) |k| w |= @as(u32, try d.byte(c * 4 + @as(u32, @intCast(k)))) << @intCast(8 * k);
                break :blk w & 0x0FFF_FFFF;
            },
        };
    }

    fn byte(d: *Disk, off: u32) Error!u8 {
        return (try d.v.sector(d.v.fat_start + off / S))[off % S];
    }

    /// Cluster `c`'s entry := `value`, in FAT 1 then every copy. FAT32 keeps the top 4 bits.
    pub fn set(d: *Disk, c: u32, value: u32) Error!void {
        for (0..d.nfats) |k| {
            const base = d.v.fat_start + @as(u32, @intCast(k)) * d.v.fat_sectors;
            switch (d.v.kind) {
                .fat12 => {
                    const off = c + c / 2;
                    var lo = try d.rawByte(base, off);
                    var hi = try d.rawByte(base, off + 1);
                    if (c & 1 != 0) {
                        lo = (lo & 0x0F) | @as(u8, @truncate(value << 4));
                        hi = @truncate(value >> 4);
                    } else {
                        lo = @truncate(value);
                        hi = (hi & 0xF0) | @as(u8, @truncate(value >> 8 & 0x0F));
                    }
                    try d.putByte(base, off, lo);
                    try d.putByte(base, off + 1, hi);
                },
                .fat16 => {
                    try d.putByte(base, c * 2, @truncate(value));
                    try d.putByte(base, c * 2 + 1, @truncate(value >> 8));
                },
                .fat32 => {
                    const n = base + c * 4 / S;
                    const b = try d.get(n);
                    const at = c * 4 % S;
                    const old = std.mem.readInt(u32, b[at..][0..4], .little);
                    std.mem.writeInt(u32, b[at..][0..4], (old & 0xF000_0000) | (value & 0x0FFF_FFFF), .little);
                    try d.put(n, b);
                },
            }
        }
    }

    fn rawByte(d: *Disk, base: u32, off: u32) Error!u8 {
        return (try d.v.sector(base + off / S))[off % S];
    }

    fn putByte(d: *Disk, base: u32, off: u32, x: u8) Error!void {
        const b = try d.get(base + off / S);
        b[off % S] = x;
        try d.put(base + off / S, b);
    }

    /// The next free cluster from `from` on (wrapping), or Full.
    pub fn free(d: *Disk, from: u32) Error!u32 {
        const last = d.v.clusters + 1;
        var c = if (from < 2 or from > last) 2 else from;
        var seen: u32 = 0;
        while (seen < d.v.clusters) : (seen += 1) {
            if (try d.entry(c) == 0) return c;
            c = if (c == last) 2 else c + 1;
        }
        return error.Full;
    }

    /// Every cluster of the chain from `first` freed (FAT entries 0), first to last.
    pub fn freeChain(d: *Disk, first: u32) Error!void {
        var c = first;
        var hops: u32 = 0;
        while (c >= 2 and c <= d.v.clusters + 1) : (hops += 1) {
            if (hops > d.v.clusters) return error.Corrupt;
            const nx = try d.entry(c);
            try d.set(c, 0);
            if (nx < 2 or nx >= d.endMark() - 7) break;
            c = nx;
        }
    }

    /// FAT32's FSInfo counts said "unknown" (0xFFFFFFFF), as the specification allows: a writer
    /// that kept them would have to keep them exact through every cut; fsck and Linux recount.
    pub fn forgetFsinfo(d: *Disk) Error!void {
        if (d.fsinfo == 0 or d.fsinfo >= d.v.fat_start) return;
        const b = try d.get(d.fsinfo);
        if (std.mem.readInt(u32, b[0..4], .little) != 0x4161_5252) return;
        if (std.mem.readInt(u32, b[488..492], .little) == 0xFFFF_FFFF and std.mem.readInt(u32, b[492..496], .little) == 0xFFFF_FFFF) return;
        std.mem.writeInt(u32, b[488..492], 0xFFFF_FFFF, .little);
        std.mem.writeInt(u32, b[492..496], 0xFFFF_FFFF, .little);
        try d.put(d.fsinfo, b);
    }

    /// Cluster `c`'s sectors all zero (a new folder's cluster, before anything points at it).
    pub fn zeroCluster(d: *Disk, c: u32) Error!void {
        const z = [_]u8{0} ** S;
        for (0..d.v.spc) |i| try d.put(d.v.clusterSector(c) + @as(u32, @intCast(i)), &z);
    }
};
