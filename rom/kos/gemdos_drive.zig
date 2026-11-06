// --------------------------------------------------------------------------
// One GEMDOS drive (docs/KOS_GEMDOS.md §4): a FAT volume over a run reader, the folder that is the
// drive's root (C: is the card's /HD), its current folder, and a sector cache. A request to C: costs
// one round trip to glass (~0.5 ms on the board) whatever its length up to 64 sectors, so the cache
// holds RUNS of 8 sectors (a directory's next sectors, the FAT's), SLOTS of them, oldest replaced;
// file data in whole sectors skips it (gemdos_file.zig reads straight into the caller's buffer).
// --------------------------------------------------------------------------
const std = @import("std");
const fat = @import("fat.zig");
const dir = @import("fat_dir.zig");
const gp = @import("gemdos_path.zig");

/// `count` sectors from `sector` into `dst` (word-aligned): `count` or 0, all or nothing (the
/// kosDriveRead rule, docs/KOS_FAT.md §4).
pub const RunFn = *const fn (ctx: *anyopaque, sector: u32, count: u32, dst: [*]align(4) u8) u32;

pub const RUN = 8;
pub const SLOTS = 4;
pub const MAX_RUN = 64; // kosDriveRead's limit

pub const State = enum { unknown, mounted, absent };

pub const Drive = struct {
    run_fn: RunFn,
    ctx: *anyopaque,
    max_run: u32, // the backend's longest request (1: a sector at a time)
    root_name: ?[]const u8, // the folder of the volume's root that is the drive's root (C: "HD")
    state: State = .unknown,
    vol: fat.Volume = undefined,
    top: fat.Dir = .{},
    cwd: [gp.MAX_DEPTH]gp.Fcb = undefined, // the current folder, by name from `top`
    depth: u8 = 0,
    cache: [SLOTS][RUN * fat.SECTOR]u8 align(4) = undefined,
    first: [SLOTS]u32 = [_]u32{0} ** SLOTS,
    count: [SLOTS]u32 = [_]u32{0} ** SLOTS, // sectors a slot holds (0: empty)
    victim: u32 = 0,
    trips: u32 = 0, // backend requests, for the cost tests

    /// Mounted, or why not: the volume and its root folder are read once, at the first use.
    pub fn ready(d: *Drive) bool {
        if (d.state == .unknown) d.state = if (d.mount()) .mounted else .absent;
        return d.state == .mounted;
    }

    /// Forget the volume (a new disk in the drive): the next use mounts it afresh.
    pub fn reset(d: *Drive) void {
        d.state = .unknown;
        d.depth = 0;
        d.count = [_]u32{0} ** SLOTS;
    }

    fn mount(d: *Drive) bool {
        d.count = [_]u32{0} ** SLOTS;
        d.vol = fat.Volume.mount(readSector, d) catch return false;
        d.top = d.vol.root();
        if (d.root_name) |name| {
            const e = (dir.find(&d.vol, d.top, name) catch return false) orelse return false;
            if (!e.isDir() or e.cluster < 2) return false; // cluster 0 would be FAT12/16's fixed root
            d.top = .{ .cluster = e.cluster };
        }
        return true;
    }

    /// `n` sectors from `sector` straight into `dst`, in requests the backend takes.
    pub fn readRun(d: *Drive, sector: u32, n: u32, dst: [*]align(4) u8) bool {
        var done: u32 = 0;
        while (done < n) {
            const k = @min(n - done, d.max_run);
            d.trips += 1;
            const p: [*]align(4) u8 = @alignCast(dst + done * fat.SECTOR);
            if (d.run_fn(d.ctx, sector + done, k, p) != k) return false;
            done += k;
        }
        return true;
    }

    fn readSector(ctx: *anyopaque, n: u32, out: *[fat.SECTOR]u8) bool {
        const d: *Drive = @ptrCast(@alignCast(ctx));
        for (0..SLOTS) |i| if (d.count[i] != 0 and n >= d.first[i] and n - d.first[i] < d.count[i]) {
            out.* = d.cache[i][(n - d.first[i]) * fat.SECTOR ..][0..fat.SECTOR].*;
            return true;
        };
        const i = d.victim;
        d.victim = (d.victim + 1) % SLOTS;
        d.count[i] = 0;
        var got: u32 = RUN; // all or nothing: near the volume's end, one sector
        if (!d.readRun(n, RUN, &d.cache[i])) {
            if (!d.readRun(n, 1, &d.cache[i])) return false;
            got = 1;
        }
        d.first[i] = n;
        d.count[i] = got;
        out.* = d.cache[i][0..fat.SECTOR].*;
        return true;
    }

    /// The folder `names` lead to from `from`; null if one is missing or a file.
    pub fn walk(d: *Drive, from: fat.Dir, names: []const gp.Fcb) fat.Error!?fat.Dir {
        var at = from;
        for (names) |*f| {
            const e = (try d.lookup(at, f)) orelse return null;
            if (!e.isDir()) return null;
            at = .{ .cluster = e.cluster };
        }
        return at;
    }

    /// The entry named `f` (no wildcards) in `in`.
    pub fn lookup(d: *Drive, in: fat.Dir, f: *const gp.Fcb) fat.Error!?fat.Entry {
        var name: [12]u8 = undefined;
        return dir.find(&d.vol, in, name[0..gp.show(f, &name)]);
    }

    /// The names from the drive's root to the folder `p` names (absolute, or from the current folder).
    pub fn absolute(d: *const Drive, p: *const gp.Path, out: *[gp.MAX_DEPTH * 2 + 1]gp.Fcb) ?[]const gp.Fcb {
        var n: usize = 0;
        if (!p.absolute) {
            const keep = d.depth -| p.up;
            @memcpy(out[0..keep], d.cwd[0..keep]);
            n = keep;
        }
        for (p.slice()) |f| {
            if (n == out.len) return null;
            out[n] = f;
            n += 1;
        }
        return out[0..n];
    }
};

test "a path is relative to the current folder, `..` stops at the root" {
    var d: Drive = .{ .run_fn = undefined, .ctx = undefined, .max_run = 1, .root_name = null };
    d.cwd[0] = try gp.fcb("PICTURES");
    d.depth = 1;
    var buf: [gp.MAX_DEPTH * 2 + 1]gp.Fcb = undefined;
    const p = try gp.parse("..\\..\\X\\Y.PI1");
    const a = d.absolute(&p, &buf).?;
    try std.testing.expectEqual(@as(usize, 2), a.len);
    try std.testing.expectEqualSlices(u8, "X          ", &a[0]);
}
