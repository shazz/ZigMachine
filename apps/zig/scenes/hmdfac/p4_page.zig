// --------------------------------------------------------------------------
// One phase-4 page: the ST's planar bytes (the truth the 68000's code runs
// on) and its picture in the plane, kept in step write by write. A planar
// byte that changes re-derives only its own 8 pixels from the four plane
// bytes of their column (one pixel when one bit changed: a dot) — so a frame
// stores about one plane pixel per dot cleared or drawn, not a page. On the
// laser rows (page rows 2 and 196) a zero pixel shows the laser stripe, as
// colour 0 does there.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const A = @import("assets.zig");
const R = @import("rasters.zig");

pub const BYTES = 200 * 160; // rows 0..199: all phase 4 ever writes

comptime {
    @setEvalBranchQuota(200_000);
    for (0..BYTES) |a| {
        if ((a * 26215) >> 22 != a / 160) @compileError("the /160 reciprocal is not exact");
    }
}

/// A nibble's 4 pixels' bit, one byte a pixel, leftmost first (a
/// little-endian u32): 64 bytes, so it stays in the data cache.
const NIB: [16]u32 = blk: {
    var t: [16]u32 = undefined;
    for (0..16) |n| {
        var v: u32 = 0;
        for (0..4) |k| v |= @as(u32, (n >> (3 - k)) & 1) << (8 * k);
        t[n] = v;
    }
    break :blk t;
};

pub const Page = struct {
    planar: [*]u8,
    plate: [*]u8, // this page's plate origin in the plane buffer
    stride: usize,

    /// Set planar byte `at` to `v`, re-deriving the pixels that changed.
    pub inline fn set(self: *const Page, at: usize, v: u8) void {
        const was = self.planar[at];
        if (was == v) return;
        self.planar[at] = v;
        self.sync(at, was ^ v);
    }

    pub inline fn orByte(self: *const Page, at: usize, m: u8) void {
        self.set(at, self.planar[at] | m);
    }

    fn sync(self: *const Page, at: usize, changed: u8) void {
        const y = (at * 26215) >> 22; // at / 160 for every at < 32000, no divide
        const r = at - y * 160;
        const c = self.planar + (y * 160 + (r & ~@as(usize, 7)) + (r & 1)); // plane 0's byte
        const x0 = (r >> 3) * 16 + (r & 1) * 8;
        const out = self.plate + y * self.stride + x0;
        const laser = y == 2 or y == 196;
        if (changed & (changed -% 1) == 0) { // one pixel: a dot drawn or cleared
            const k: u3 = @intCast(@clz(changed));
            const s: u3 = 7 - k;
            var idx: u8 = (c[0] >> s) & 1 | ((c[2] >> s) & 1) << 1 | ((c[4] >> s) & 1) << 2 | ((c[6] >> s) & 1) << 3;
            if (idx == 0 and laser) idx = R.stripeAt(A.ART_X + x0 + k, y);
            out[k] = idx;
            return;
        }
        var px: [2]u32 = .{
            NIB[c[0] >> 4] | NIB[c[2] >> 4] << 1 | NIB[c[4] >> 4] << 2 | NIB[c[6] >> 4] << 3,
            NIB[c[0] & 15] | NIB[c[2] & 15] << 1 | NIB[c[4] & 15] << 2 | NIB[c[6] & 15] << 3,
        };
        const b = std.mem.asBytes(&px);
        if (laser) {
            for (b, 0..) |*p, k| {
                if (p.* == 0) p.* = R.stripeAt(A.ART_X + x0 + k, y);
            }
        }
        const q: *align(4) [2]u32 = @ptrCast(@alignCast(out));
        q.* = px;
    }
};
