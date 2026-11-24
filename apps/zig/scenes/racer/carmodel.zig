// --------------------------------------------------------------------------
// RACER: the player's car, ours: a body, a cabin and four wheel blocks, flat-shaded boxes in the
// car's own space (x right, y up, z forward; Q7 = 1/128 unit; the origin is on the ground between
// the wheels). Built at compile time in the track binary's face-record layout, so the same
// transform, back-face test, clip and fill that draw the track draw the car (project.zig).
// The bottom faces are left out (never seen). Light is baked from the face's own normal (the car
// turns, the light does not follow: a rotating car is lit as if the sun turned with it, which a
// flat-shaded box shows least). Ramps 12-14 are the converter's car_body / car_dark / car_glass
// (tools/racer/trackc.py). No ZigOS import.
// --------------------------------------------------------------------------
const trk = @import("trk.zig");

pub const RAMP_BODY = 12;
pub const RAMP_DARK = 13;
pub const RAMP_GLASS = 14;
/// The AI cars' liveries: body ramps 15..18 (the cart's own, past the track's 15), the player keeps 12.
pub const RAMP_LIVERY = 15;
pub const LIVERIES = 4;

/// The palette-index shift of a body face for AI car `k` (0-based): the livery k % 4's ramp for ramp 12's.
pub fn liveryShift(k: usize) u8 {
    return @intCast((RAMP_LIVERY + k % LIVERIES - RAMP_BODY) * 8);
}
pub const SKID_COLOUR: u8 = 16 + RAMP_DARK * 8 + 0;

/// The wheel contact points in car space, Q16 (right, up, forward): where the skidmarks start.
pub const WHEELS = [4][3]i32{
    .{ -19660, 0, 26214 }, // left front
    .{ 19660, 0, 26214 }, // right front
    .{ -19660, 0, -26214 }, // left rear
    .{ 19660, 0, -26214 }, // right rear
};

const Box = struct { lo: [3]i16, hi: [3]i16, ramp: u8 };
const BOXES = [_]Box{
    .{ .lo = .{ -30, 8, -58 }, .hi = .{ 30, 30, 58 }, .ramp = RAMP_BODY },
    .{ .lo = .{ -22, 30, -28 }, .hi = .{ 22, 46, 22 }, .ramp = RAMP_GLASS },
    .{ .lo = .{ -40, 0, 41 }, .hi = .{ -30, 18, 61 }, .ramp = RAMP_DARK },
    .{ .lo = .{ 30, 0, 41 }, .hi = .{ 40, 18, 61 }, .ramp = RAMP_DARK },
    .{ .lo = .{ -40, 0, -61 }, .hi = .{ -30, 18, -41 }, .ramp = RAMP_DARK },
    .{ .lo = .{ 30, 0, -61 }, .hi = .{ 40, 18, -41 }, .ramp = RAMP_DARK },
};

/// A box face: the axis, the side, and its corners as (x, y, z) picks of lo (0) or hi (1).
const Side = struct { axis: u2, hi: bool, light: u8, c: [4][3]u1 };
const SIDES = [_]Side{
    .{ .axis = 0, .hi = true, .light = 4, .c = .{ .{ 1, 0, 0 }, .{ 1, 1, 0 }, .{ 1, 1, 1 }, .{ 1, 0, 1 } } },
    .{ .axis = 0, .hi = false, .light = 2, .c = .{ .{ 0, 0, 0 }, .{ 0, 0, 1 }, .{ 0, 1, 1 }, .{ 0, 1, 0 } } },
    .{ .axis = 1, .hi = true, .light = 6, .c = .{ .{ 0, 1, 0 }, .{ 0, 1, 1 }, .{ 1, 1, 1 }, .{ 1, 1, 0 } } },
    .{ .axis = 2, .hi = true, .light = 4, .c = .{ .{ 0, 0, 1 }, .{ 1, 0, 1 }, .{ 1, 1, 1 }, .{ 0, 1, 1 } } },
    .{ .axis = 2, .hi = false, .light = 2, .c = .{ .{ 0, 0, 0 }, .{ 0, 1, 0 }, .{ 1, 1, 0 }, .{ 1, 0, 0 } } },
};

pub const NV = BOXES.len * 8;
pub const NF = BOXES.len * SIDES.len;

fn corner(b: Box, pick: [3]u1) trk.Vert {
    var v: trk.Vert = undefined;
    for (0..3) |k| v[k] = if (pick[k] == 1) b.hi[k] else b.lo[k];
    return v;
}

const BUILT = blk: {
    var vs: [NV]trk.Vert = undefined;
    var fs: [NF]trk.Face = undefined;
    for (BOXES, 0..) |b, bi| {
        for (0..8) |c| vs[bi * 8 + c] = corner(b, .{ @intCast(c & 1), @intCast((c >> 1) & 1), @intCast((c >> 2) & 1) });
        for (SIDES, 0..) |s, si| {
            var f = trk.Face{
                .v = undefined, .flags = 0, .nv = 4, .colour = @intCast(16 + @as(u32, b.ramp) * 8 + s.light), .inner_n = 0,
                .n = .{ 0, 0, 0 }, .borders = 0, .cp = 0, .inner_first = 0, ._p1 = 0,
            };
            for (s.c, 0..) |pick, k| f.v[k] = @intCast(bi * 8 + @as(usize, pick[0]) + 2 * @as(usize, pick[1]) + 4 * @as(usize, pick[2]));
            const sign: i16 = if (s.hi) 16384 else -16384;
            f.n[s.axis] = sign;
            f.cp = @as(i32, sign) * vs[f.v[0]][s.axis];
            fs[bi * SIDES.len + si] = f;
        }
    }
    break :blk .{ .verts = vs, .faces = fs };
};

pub const verts: [NV]trk.Vert = BUILT.verts;
pub const faces: [NF]trk.Face = BUILT.faces;
