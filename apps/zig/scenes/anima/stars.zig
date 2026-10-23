// --------------------------------------------------------------------------
// A 3D starfield flying out of the screen's centre, plotted LAST and only on
// pixels still at index 0, so the stars sit behind everything in front of the
// raster. Each star is erased by the frame after, only if its pixel still
// holds its colour (a load is cheap on the board, a store is a DDR write).
//
// Integer maths: positions in 1/16 px, z in 1..Z_FAR, the projection through
// a comptime reciprocal table. New stars come from a 32-bit LCG, so the field
// is deterministic.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const P = @import("palette.zig");

pub const N = 120;
const Z_FAR = 512;
const SPEED = 4; // z units a tick
const W = zg.PHYSICAL_WIDTH;
const H = zg.PHYSICAL_HEIGHT;
const CXS: i32 = W / 2;
const CYS: i32 = 148;

// RECIP[z] = 2^16 * 64 / z: the screen scale at depth z (64 px per unit at z=1).
const RECIP: [Z_FAR + 1]i32 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [Z_FAR + 1]i32 = undefined;
    t[0] = 0;
    for (1..Z_FAR + 1) |z| t[z] = @divTrunc(64 << 16, @as(i32, @intCast(z)));
    break :blk t;
};

const Star = struct { x: i32, y: i32, z: i32 };
var stars: [N]Star = undefined;
var at: [N]u32 = @splat(0xFFFF_FFFF); // last pixel offset, or none
var ink: [N]u8 = @splat(0);
var seed: u32 = 0x414E_494D; // "ANIM"

fn rnd() u32 {
    seed = seed *% 1664525 +% 1013904223;
    return seed >> 8;
}

fn spawn(s: *Star, z: i32) void {
    s.x = @as(i32, @intCast(rnd() % 1024)) - 512;
    s.y = @as(i32, @intCast(rnd() % 768)) - 384;
    s.z = z;
}

pub fn reset() void {
    seed = 0x414E_494D;
    for (&stars, 0..) |*s, i| spawn(s, @intCast(1 + (i * Z_FAR) / N));
    at = @splat(0xFFFF_FFFF);
}

/// Erase last frame's stars (before anything else draws).
pub fn erase(fb: *zg.LogicalFB) void {
    for (0..N) |i| {
        const p = at[i];
        if (p == 0xFFFF_FFFF) continue;
        if (fb.fb[p] == ink[i]) fb.fb[p] = P.BG;
        at[i] = 0xFFFF_FFFF;
    }
}

/// Move and plot `count` stars (the field fades in by count).
pub fn draw(fb: *zg.LogicalFB, count: usize, advance: bool) void {
    for (stars[0..count], 0..) |*s, i| {
        if (advance) {
            s.z -= SPEED;
            if (s.z < 8) spawn(s, Z_FAR);
        }
        const k = RECIP[@intCast(s.z)];
        const x = CXS + ((s.x * k) >> 16);
        const y = CYS + ((s.y * k) >> 16);
        if (x < 0 or y < 0 or x >= W or y >= H) {
            if (advance) spawn(s, Z_FAR);
            continue;
        }
        const p: u32 = @intCast(y * W + x);
        if (fb.fb[p] != P.BG) continue;
        const c: u8 = P.STAR0 + @as(u8, if (s.z > 340) 0 else if (s.z > 170) 1 else 2);
        fb.fb[p] = c;
        at[i] = p;
        ink[i] = c;
    }
}
