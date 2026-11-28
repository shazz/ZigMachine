// --------------------------------------------------------------------------
// RACER: the cart's buffers, carved out of cart RAM once at init (zg.mem): the frame's polygon
// lists and caches, the car's and the skidmarks' vertex caches. Split from racer.zig to keep it
// under the file size limit.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const carmodel = @import("carmodel.zig");
const frame = @import("frame.zig");
const smoke = @import("smoke.zig");
const xf = @import("xform.zig");

pub fn cache(n: usize) xf.Cache {
    const e = zg.mem.mustAlloc(xf.Entry, n);
    @memset(e, std.mem.zeroes(xf.Entry));
    return .{ .e = e };
}

/// The frame for tracks of at most `nv` vertices and `nf` faces.
pub fn frameFor(nv: usize, nf: usize) frame.Frame {
    const seen = zg.mem.mustAlloc(frame.Stamp, nf);
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
    return cache(@import("carfile.zig").MAX_VERTS); // any car file's model
}

/// The board batch's per-frame scratch, carved out of the library's stage (the packed-file staging buffer, >= the 32 KB car
/// buffer: used only while a track or a car file is read, between frames), so no cart RAM is taken from the track buffers:
/// the course model's polygons (coursedraw.zig), the posed wheels' faces and vertices (carview.zig). A frame never needs
/// both (the course select draws no car); a too-small stage leaves them empty (no model, still wheels: never an overrun).
pub fn scratch(stage: []u8) void {
    const cm = @import("coursemesh.zig");
    const trk = @import("trk.zig");
    const ws = @import("wheelspin.zig");
    const a = cm.MAXP * @sizeOf(cm.Poly);
    const b = a + ws.MAX_FACES * @sizeOf(trk.Face);
    const c = b + ws.MAX_VERTS * @sizeOf(trk.Vert);
    if (stage.len < c or @intFromPtr(stage.ptr) % 4 != 0) return zg.Console.log("racer,scratch,none,{}", .{stage.len});
    @import("coursedraw.zig").polys = @as([*]cm.Poly, @ptrCast(@alignCast(stage.ptr)))[0..cm.MAXP];
    @import("carview.zig").posed_fs = @as([*]trk.Face, @ptrCast(@alignCast(stage.ptr + a)))[0..ws.MAX_FACES];
    @import("carview.zig").posed_vs = @as([*]trk.Vert, @ptrCast(@alignCast(stage.ptr + b)))[0..ws.MAX_VERTS];
}

pub fn smokeCache() xf.Cache {
    return cache(smoke.MAXP * smoke.VERTS);
}
