// --------------------------------------------------------------------------
// RACER: the cart's buffers, carved out of cart RAM once at init (zg.mem): the frame's polygon
// lists and caches, the car's and the skidmarks' vertex caches. Split from racer.zig to keep it
// under the file size limit.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const carmodel = @import("carmodel.zig");
const frame = @import("frame.zig");
const skid = @import("skid.zig");
const xf = @import("xform.zig");

pub fn cache(n: usize) xf.Cache {
    const e = zg.mem.mustAlloc(xf.Entry, n);
    @memset(e, std.mem.zeroes(xf.Entry));
    return .{ .e = e };
}

/// The frame for tracks of at most `nv` vertices and `nf` faces.
pub fn frameFor(nv: usize, nf: usize) frame.Frame {
    const seen = zg.mem.mustAlloc(u32, nf);
    @memset(seen, 0);
    return .{
        .cache = cache(nv),
        .kept = zg.mem.mustAlloc(frame.Rec, frame.MAXP),
        .key = zg.mem.mustAlloc(u16, frame.MAXP),
        .order = zg.mem.mustAlloc(u16, frame.MAXP),
        .count = &zg.mem.mustAlloc([frame.BUCKETS + 1]u32, 1)[0],
        .seen = seen,
        .fkey = zg.mem.mustAlloc(u16, nf),
    };
}

pub fn carCache() xf.Cache {
    return cache(carmodel.NV);
}

pub fn skidCache() xf.Cache {
    return cache(skid.MAXM * 4);
}
