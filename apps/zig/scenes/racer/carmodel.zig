// --------------------------------------------------------------------------
// RACER: the GT car (M5 step 3), ours: a low-poly flat-shaded GT coupe authored in Blender
// (tools/racer/cars/gt_build.py -> the add-on's Car Kit export -> tools/racer/carc.py) and embedded
// as gt.kcar, read at COMPILE time into the track binary's face-record layout, so the same
// transform, back-face test, clip and fill that draw the track draw the car (project.zig). Car
// space: x right, y up, z forward, Q7 = 1/128 unit, the origin on the ground between the wheels.
// Each face's colour is baked by the converter from its normal against the car's own sun (the car
// turns and its light turns with it). Parts, in the file's order: wheels, hull, cabin, wing (the
// near model), the shadow quad, lod1 (the far model). Liveries: a body face (FLAG_BODY) is
// recoloured to the livery's body ramp, a stripe face (FLAG_STRIPE) to its stripe ramp, both by
// project.Key.dc's palette-index shift from ramp 12. No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const carfile = @import("carfile.zig");
const trk = @import("trk.zig");

const RAW = @embedFile("../../assets/screens/racer/gt.kcar");
pub const MAGIC: u32 = 0x5241434B;
pub const FLAG_SHADOW: u8 = 0x10;
pub const FLAG_BODY: u8 = 0x40;
pub const FLAG_STRIPE: u8 = 0x80;

pub const RAMP_BODY = 12; // the player's red (the track file's palette)
pub const RAMP_DARK = 13;
pub const RAMP_GLASS = 14;
/// The AI cars' body ramps 15..18 (the cart's palette, past the track's): blue, yellow, green, white.
pub const RAMP_LIVERY = 15;
pub const LIVERIES = 4;
pub const SKID_COLOUR: u8 = 16 + RAMP_DARK * 8 + 0;

/// A livery: the body's ramp and the stripe's (the stripe runs over the deck, the roof and the wing).
pub const Livery = struct { body: u8, stripe: u8 };
/// Car k's livery: 0 the player (red, white stripe); the AI car k keeps M3's body ramp 15 + (k - 1) % 4 (the minimap's dot)
/// and a stripe of its own, so the eight cars on the grid all differ.
pub const LIVERY = [8]Livery{
    .{ .body = 12, .stripe = 18 }, .{ .body = 15, .stripe = 18 }, .{ .body = 16, .stripe = 13 }, .{ .body = 17, .stripe = 18 },
    .{ .body = 18, .stripe = 12 }, .{ .body = 15, .stripe = 16 }, .{ .body = 16, .stripe = 12 }, .{ .body = 17, .stripe = 16 },
};

/// The palette-index shift that recolours ramp 12 to `ramp` (wrapping u8 maths: ramp 13 is +8, ramp 18 +48).
pub fn shiftTo(ramp: u8) u8 {
    return (ramp -% RAMP_BODY) *% 8;
}

/// The wheel contact points in car space, Q16 (right, up, forward): where the skidmarks start. The PHYSICS' points (freds72's
/// car): since the GT is drawn x2 (M5 step 5) its tyres sit outside them.
pub const WHEELS = [4][3]i32{
    .{ -9830, 0, 13107 }, // left front
    .{ 9830, 0, 13107 }, // right front
    .{ -9830, 0, -13107 }, // left rear
    .{ 9830, 0, -13107 }, // right rear
};

fn word(i: usize) u32 {
    return std.mem.readInt(u32, RAW[i * 4 ..][0..4], .little);
}

const NVERT = word(2);
const NFACE = word(3);
const VBYTES = (NVERT * 6 + 3) / 4 * 4;

pub const Part = carfile.Part;
pub const Model = carfile.Model;
pub const Set = carfile.Set;

pub const NV = NVERT;
pub const NF = NFACE;

const BUILT = blk: {
    @setEvalBranchQuota(200_000);
    if (word(0) != MAGIC or word(1) != 1 or word(9) != NFACE) @compileError("gt.kcar: not a v1 KCAR (run tools/racer/carc.py)");
    if (std.hash.crc.Crc32IsoHdlc.hash(RAW[64..]) != word(11)) @compileError("gt.kcar: bad CRC");
    if (RAW.len != 64 + VBYTES + NFACE * 32) @compileError("gt.kcar: wrong size");
    if (NVERT > carfile.MAX_VERTS or NFACE > carfile.MAX_FACES) @compileError("gt.kcar: over a car file's limits");
    var vs: [NVERT]trk.Vert = undefined;
    for (&vs, 0..) |*v, i| {
        for (0..3) |k| v[k] = std.mem.readInt(i16, RAW[64 + i * 6 + k * 2 ..][0..2], .little);
    }
    var fs: [NFACE]trk.Face = undefined;
    for (&fs, 0..) |*f, i| f.* = std.mem.bytesToValue(trk.Face, RAW[64 + VBYTES + i * 32 ..][0..32]);
    var e: [6]u16 = undefined;
    for (&e, 0..) |*x, i| x.* = @intCast(word(4 + i));
    var top: i32 = 0;
    for (fs[e[0]..e[1]]) |f| for (f.v[0..f.nv]) |id| {
        top = @max(top, vs[id][1]);
    };
    break :blk .{ .verts = vs, .faces = fs, .end = e, .mid_y = @divTrunc(top, 2) };
};

pub const verts: [NV]trk.Vert = BUILT.verts;
pub const faces: [NF]trk.Face = BUILT.faces;
pub const END: [6]u16 = BUILT.end;
/// The wing's front edge (Q7 forward): an eye behind it sees the wing over the cabin, an eye in front the cabin over the wing.
pub const WING_Z: i32 = @bitCast(word(10));

/// The built-in GT (the fallback when no car file is on the disk, and the gate's car).
pub const gt = Model{ .verts = &verts, .faces = &faces, .end = END, .wing_z = WING_Z, .mid_y = BUILT.mid_y };
pub const builtin = Set{ .models = .{gt} ++ .{undefined} ** (carfile.MAX_MODELS - 1), .n = 1 };

/// The cars on show: the built-in GT, or a car file's set (cars.zig loads it; its slices point into the car buffer).
pub var active: Set = builtin;

pub fn range(p: Part) []const trk.Face {
    return gt.range(p);
}

/// Car k's model in the active set (0: the player's).
pub fn of(k: usize) *const Model {
    return active.of(k);
}
