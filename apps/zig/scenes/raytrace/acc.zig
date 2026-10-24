// A pixel's running samples for refine.zig, kept per RAMP class because the
// palette has no colours between its ramps (dither.zig): up to two classes,
// each with its sample count and summed 0..256 intensities. resolve() dithers
// between the two by coverage, then along the chosen ramp by its mean. Pure,
// so acc_test.zig runs it natively.
const D = @import("dither.zig");

/// One pixel's samples, split over the (at most) two ramp classes it has seen.
/// Word-aligned, so a pixel's state can move as three word stores
/// (refine.zig's record: a misaligned access traps on the board).
pub const Acc = extern struct { cls: [2]u8 align(4), n: [2]u8, q: [2]u16, fog: [2]u16 };

comptime {
    if (@sizeOf(Acc) != 12 or @alignOf(Acc) != 4) @compileError("Acc must stay 3 words");
}

/// A pixel's state after its first sample.
pub fn first(s: D.Shade) Acc {
    return .{ .cls = .{ s.cls, 0 }, .n = .{ 1, 0 }, .q = .{ s.q, 0 }, .fog = .{ s.fog, 0 } };
}

pub fn add(a: *Acc, s: D.Shade) void {
    const slot: usize = if (a.cls[0] == s.cls) 0 else if (a.n[1] == 0 or a.cls[1] == s.cls) 1 else return;
    a.cls[slot] = s.cls;
    a.n[slot] += 1;
    a.q[slot] += s.q;
    a.fog[slot] += s.fog;
}

/// The palette index for a pixel's samples at (x, y).
pub fn resolve(a: Acc, x: u32, y: u32) u8 {
    const n: u32 = @as(u32, a.n[0]) + a.n[1];
    const pick: usize = if (@as(u32, a.n[1]) * 256 / n > D.bayer(x + 2, y + 1)) 1 else 0;
    const k: u32 = a.n[pick];
    const q: u16 = @intCast((a.q[pick] + k / 2) / k);
    const fog: u16 = @intCast((a.fog[pick] + k / 2) / k);
    return D.index(.{ .cls = a.cls[pick], .q = q, .fog = fog }, D.bayer(x, y));
}
