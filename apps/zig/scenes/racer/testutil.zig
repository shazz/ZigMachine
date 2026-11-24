// RACER: native test helpers: a frame over the testing allocator.
const std = @import("std");
const frame = @import("frame.zig");
const trk = @import("trk.zig");
const xf = @import("xform.zig");

pub fn newFrame(t: *const trk.Track) !frame.Frame {
    const a = std.testing.allocator;
    const e = try a.alloc(xf.Entry, t.verts.len);
    @memset(e, std.mem.zeroes(xf.Entry));
    const seen = try a.alloc(u32, t.faces.len);
    @memset(seen, 0);
    return .{
        .cache = .{ .e = e }, .kept = try a.alloc(frame.Rec, frame.MAXP), .key = try a.alloc(u16, frame.MAXP),
        .order = try a.alloc(u16, frame.MAXP), .count = try a.create([frame.BUCKETS + 1]u32), .seen = seen,
        .fkey = try a.alloc(u16, t.faces.len),
    };
}

pub fn freeFrame(f: *frame.Frame) void {
    const a = std.testing.allocator;
    a.free(f.cache.e);
    a.free(f.kept);
    a.free(f.key);
    a.free(f.order);
    a.destroy(f.count);
    a.free(f.seen);
    a.free(f.fkey);
}

pub fn newCache(n: usize) !xf.Cache {
    const e = try std.testing.allocator.alloc(xf.Entry, n);
    @memset(e, std.mem.zeroes(xf.Entry));
    return .{ .e = e };
}
