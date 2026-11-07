// --------------------------------------------------------------------------
// The image writer's file data (kfs.zig): `data` written at `offset` of the file a slot names, the
// chain grown as it needs. New clusters are picked from the FAT's free ones and written BEFORE the
// FAT links them and before the entry's size grows, so a cut mid-request leaves the file as it was
// plus, at worst, clusters fsck reclaims (kfs_fat.zig). A request is at most kfs_abi.DATA_MAX bytes,
// so it adds at most MAX_NEW clusters.
// --------------------------------------------------------------------------
const std = @import("std");
const fat = @import("fat.zig");
const kf = @import("kfs_fat.zig");
const kd = @import("kfs_dir.zig");
const abi = @import("kfs_abi.zig");

const S = fat.SECTOR;
const MAX_NEW = abi.DATA_MAX / S + 1;

/// A walk along a file's clusters: its own chain, then the clusters this request adds.
const Walk = struct {
    d: *kf.Disk,
    have: u32,
    fresh: []const u32,
    index: u32 = 0,
    c: u32,

    fn to(w: *Walk, index: u32) kf.Error!u32 {
        while (w.index < index) {
            w.index += 1;
            w.c = if (w.index < w.have) (try w.d.v.next(w.c)) orelse return error.Corrupt else w.fresh[w.index - w.have];
        }
        return w.c;
    }
};

/// The file `s` names grows to max(size, offset + data.len); `data` lands at `offset`. The entry is
/// written back last (its size and, for an empty file, its first cluster).
pub fn writeAt(d: *kf.Disk, s: *kd.Slot, offset: u32, data: []const u8) kf.Error!void {
    if (data.len > abi.DATA_MAX) return error.Unsupported;
    const cs = d.csize();
    const end: u32 = @max(s.size(), offset + @as(u32, @intCast(data.len)));
    const want = (end + cs - 1) / cs;
    var have: u32 = 0;
    var tail: u32 = 0;
    var c = s.cluster();
    while (c >= 2) {
        have += 1;
        tail = c;
        if (have > d.v.clusters) return error.Corrupt;
        c = (try d.v.next(c)) orelse 0;
    }
    var fresh: [MAX_NEW]u32 = undefined;
    const k = want -| have;
    if (k > MAX_NEW) return error.Unsupported; // offset past the end (kfs.zig refuses it first)
    var from = tail + 1;
    for (0..k) |i| {
        const f = try d.free(from);
        if (std.mem.indexOfScalar(u32, fresh[0..i], f) != null) return error.Full; // wrapped round
        fresh[i] = f;
        from = f + 1;
    }
    if (data.len > 0) {
        var w = Walk{ .d = d, .have = have, .fresh = fresh[0..k], .c = if (have > 0) s.cluster() else fresh[0] };
        try put(d, &w, offset, data);
    }
    for (0..k) |i| try d.set(fresh[i], if (i + 1 < k) fresh[i + 1] else d.endMark());
    if (k > 0) {
        if (have > 0) try d.set(tail, fresh[0]) else s.setCluster(fresh[0]);
    }
    s.setSize(end);
    try kd.write(d, s);
}

fn put(d: *kf.Disk, w: *Walk, offset: u32, data: []const u8) kf.Error!void {
    const cs = d.csize();
    var pos = offset;
    var done: usize = 0;
    while (done < data.len) {
        const cl = try w.to(pos / cs);
        const sector = d.v.clusterSector(cl) + (pos % cs) / S;
        const at = pos % S;
        const n: u32 = @intCast(@min(S - at, data.len - done));
        if (n == S) {
            try d.put(sector, data[done..][0..S]);
        } else {
            const b = try d.get(sector);
            @memcpy(b[at..][0..n], data[done..][0..n]);
            try d.put(sector, b);
        }
        done += n;
        pos += n;
    }
}
