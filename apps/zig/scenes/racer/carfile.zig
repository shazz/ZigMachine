// --------------------------------------------------------------------------
// RACER: a car FILE (M5 car files): the converter's car (tools/racer/carc.py) checked and viewed in
// place, like trk.parse does a track. Since M5 a car can come off the disk (a user's, Track Kit
// spirit: `<TRACK>.KCR` beside a track, or `CAR.KCR` for every track; cars.zig), so every count and
// offset is untrusted input, bounded here before the cart follows it; a bad file is refused with a
// name, never trapped on or defaulted.
//
//   v1  ONE model: a 64-byte header (magic 'KCAR', version 1, vertices, faces, the six parts' end
//       faces, the wing's front edge, CRC-32 of the rest), the vertices (i16 x3 Q7, padded to 4),
//       the faces (trk.Face's 32-byte records). The built-in GT (carmodel.zig) is one.
//   v2  a SET: a 64-byte header (magic, version 2, models 1..MAX_MODELS, flags, the palette's 7 ramps
//       12..18 as RGBX when flag PALETTE, CRC-32 of the rest, then (board batch) the TAG: byte 48 the car
//       class + 1 (0: none; FORMULA STOCK PROTO, feel_params.CLASSES), bytes 49-51 zero, 52-63 the set's
//       name (A-Z 0-9 space, zero padded)), then that many v1 records. Model 0 is the player's car,
//       models 1.. the AI cars' in turn (each its own colours: a set replaces the liveries' recolour).
//
// No ZigOS import: carfile_test.zig runs it natively.
// --------------------------------------------------------------------------
const std = @import("std");
const trk = @import("trk.zig");
const wheelspin = @import("wheelspin.zig");

pub const MAGIC: u32 = 0x5241434B;
pub const HEADER = 64;
pub const MAX_MODELS = 5;
pub const MAX_VERTS = 256; // a model's vertices: the car's vertex cache (setup.carCache)
pub const MAX_FACES = 256; // a model's faces
pub const MAX_FILE: usize = 32 * 1024; // the car buffer (cars.zig)
pub const RAMPS = 7; // the car ramps 12..18 a set may recolour
pub const FIRST_RAMP = 12;
pub const PALETTE: u32 = 1; // v2 flag: the header holds the ramps' colours
pub const FLAG_SHADOW: u8 = 0x10;
pub const MAX_SHADOW = 16; // the shadow's faces: the footprint (tools/racer/footprint.py, R82 bug pass), or one quad (M5)
pub const Error = error{ Truncated, BadMagic, BadVersion, BadCrc, BadBlock, BadFace, BadParts };

/// The parts, in the file's order: the near model (wheels, hull, cabin, wing), the shadow (1..MAX_SHADOW faces), the far model.
pub const Part = enum(u3) { wheels, hull, cabin, wing, shadow, lod1 };

pub const Model = struct {
    verts: []const trk.Vert,
    faces: []const trk.Face,
    end: [6]u16,
    wing_z: i32, // Q7 forward: carview swaps the cabin and the wing by the eye's side of it
    mid_y: i32, // Q7: half the hull's height, the depth every face of the car is keyed by
    foot: Foot = .{}, // the shadow's box: the car's drawn footprint (decals under it, car-vs-car contacts in ARCADE)
    spin: wheelspin.Groups = .{}, // the wheels' groups and axles: the drawn wheels turn (board batch, wheelspin.zig)
    rad7: i32 = 0x7fff, // Q7: no vertex farther from the model's origin (radiusOf; carview culls a car out of the view by it)

    pub fn range(self: *const Model, p: Part) []const trk.Face {
        const i = @intFromEnum(p);
        return self.faces[if (i == 0) 0 else self.end[i - 1]..self.end[i]];
    }
};

/// The model's bounding radius (Q7, rounded up) around its origin: a vertex is never farther (board optimisation).
pub fn radiusOf(verts: []const trk.Vert) i32 {
    var m: u64 = 0;
    for (verts) |v| {
        const x: i64 = v[0];
        const y: i64 = v[1];
        const z: i64 = v[2];
        m = @max(m, @as(u64, @intCast(x * x + y * y + z * z)));
    }
    return @as(i32, @intCast(std.math.sqrt(m))) + 1;
}

/// A model's footprint box, Q7 car space (x right, z forward): the extent of its shadow faces.
pub const Foot = struct { x0: i32 = 0, x1: i32 = 0, z0: i32 = 0, z1: i32 = 0 };

/// The box around the shadow part's vertices (the footprint, or the one M5 quad).
pub fn footOf(verts: []const trk.Vert, shadow: []const trk.Face) Foot {
    var f = Foot{ .x0 = std.math.maxInt(i32), .x1 = std.math.minInt(i32), .z0 = std.math.maxInt(i32), .z1 = std.math.minInt(i32) };
    for (shadow) |s| for (s.v[0..s.nv]) |id| {
        f.x0 = @min(f.x0, verts[id][0]);
        f.x1 = @max(f.x1, verts[id][0]);
        f.z0 = @min(f.z0, verts[id][2]);
        f.z1 = @max(f.z1, verts[id][2]);
    };
    return f;
}

pub const CLASSES = 3; // the tag's classes (feel_params.CLASSES)
pub const NAME = 12;

pub const Set = struct {
    models: [MAX_MODELS]Model = undefined,
    n: usize = 0,
    palette: ?[RAMPS][3]u8 = null,
    class: ?u8 = null, // the tag's car class (a 32X class's set), or none: the player's class stays
    name: [NAME]u8 = @splat(0), // the tag's name, or zeros (cars.zig names it by its file)

    /// Car k's model: 0 the player's; the AI car k takes the AI models in turn (the player's when the set has one model).
    pub fn of(self: *const Set, k: usize) *const Model {
        return &self.models[if (k == 0 or self.n == 1) 0 else 1 + (k - 1) % (self.n - 1)];
    }
};

fn word(b: []const u8, i: usize) u32 {
    return std.mem.readInt(u32, b[i * 4 ..][0..4], .little);
}

/// A whole file: v1 (one model) or v2 (a set). Every slice points into `b`, which must outlive the set.
pub fn parse(b: []align(4) const u8) Error!Set {
    if (b.len < HEADER) return error.Truncated;
    if (word(b, 0) != MAGIC) return error.BadMagic;
    var s = Set{};
    switch (word(b, 1)) {
        1 => {
            const r = try model(b);
            if (r.len != b.len) return error.Truncated;
            s.models[0] = r.m;
            s.n = 1;
        },
        2 => try set(b, &s),
        else => return error.BadVersion,
    }
    return s;
}

fn set(b: []align(4) const u8, s: *Set) Error!void {
    const n = word(b, 2);
    if (n < 1 or n > MAX_MODELS or word(b, 3) & ~PALETTE != 0) return error.BadBlock;
    if (std.hash.crc.Crc32IsoHdlc.hash(b[HEADER..]) != word(b, 11)) return error.BadCrc;
    try tag(b, s);
    if (word(b, 3) & PALETTE != 0) {
        var pal: [RAMPS][3]u8 = undefined;
        for (&pal, 0..) |*c, i| c.* = b[16 + i * 4 ..][0..3].*;
        s.palette = pal;
    }
    var at: usize = HEADER;
    for (0..n) |i| {
        const r = try model(@alignCast(b[at..])); // every record's length is a multiple of 4

        s.models[i] = r.m;
        at += r.len;
    }
    if (at != b.len) return error.Truncated;
    s.n = n;
}

/// The set's tag (header bytes 48-63): a class past CLASSES, padding not zero, or a name byte outside A-Z 0-9 space is refused.
fn tag(b: []const u8, s: *Set) Error!void {
    const c = b[48];
    if (c > CLASSES or b[49] | b[50] | b[51] != 0) return error.BadBlock;
    if (c != 0) s.class = c - 1;
    for (b[52..64], &s.name) |x, *o| {
        if (x != 0 and x != ' ' and !std.ascii.isUpper(x) and !std.ascii.isDigit(x)) return error.BadBlock;
        o.* = x;
    }
}

const Rec = struct { m: Model, len: usize };

/// One v1 record at the start of `b` (b may run on past it: a set's next record).
fn model(b: []align(4) const u8) Error!Rec {
    if (b.len < HEADER) return error.Truncated;
    if (word(b, 0) != MAGIC) return error.BadMagic;
    if (word(b, 1) != 1) return error.BadVersion;
    const nv = word(b, 2);
    const nf = word(b, 3);
    if (nv == 0 or nv > MAX_VERTS or nf > MAX_FACES or word(b, 9) != nf) return error.BadBlock;
    const vbytes = (nv * 6 + 3) / 4 * 4;
    const len = HEADER + vbytes + nf * 32;
    if (len > b.len) return error.Truncated;
    if (std.hash.crc.Crc32IsoHdlc.hash(b[HEADER..len]) != word(b, 11)) return error.BadCrc;
    const vp: [*]const trk.Vert = @ptrCast(@alignCast(&b[HEADER]));
    const fp: [*]const trk.Face = @ptrCast(@alignCast(&b[HEADER + vbytes]));
    var m = Model{ .verts = vp[0..nv], .faces = fp[0..nf], .end = undefined, .wing_z = @bitCast(word(b, 10)), .mid_y = 0 };
    var last: u32 = 0;
    for (&m.end, 0..) |*e, i| {
        const x = word(b, 4 + i);
        if (x < last or x > nf) return error.BadParts;
        e.* = @intCast(x);
        last = x;
    }
    try check(&m);
    return .{ .m = m, .len = len };
}

/// What the cart relies on: a hull and a far model, 1..MAX_SHADOW shadow faces (flagged, and the only flagged faces), every
/// face 3-4 ids in range.
fn check(m: *Model) Error!void {
    if (m.range(.hull).len == 0 or m.range(.lod1).len == 0) return error.BadParts;
    const sh = m.range(.shadow);
    if (sh.len < 1 or sh.len > MAX_SHADOW) return error.BadParts;
    const s0 = m.end[@intFromEnum(Part.shadow) - 1];
    for (m.faces, 0..) |f, i| {
        if (f.nv < 3 or f.nv > 4 or f.alt != 0 or f.inner_n != 0) return error.BadFace; // no debug shades, no decals on a car
        for (f.v) |id| if (id >= m.verts.len) return error.BadFace; // the padding ids too: all four are read
        if ((f.flags & FLAG_SHADOW != 0) != (i >= s0 and i < m.end[@intFromEnum(Part.shadow)])) return error.BadParts;
    }
    m.foot = footOf(m.verts, sh);
    m.spin = wheelspin.groups(m.verts, m.range(.wheels));
    m.rad7 = radiusOf(m.verts);
    var top: i32 = 0;
    for (m.range(.hull)) |f| for (f.v[0..f.nv]) |id| {
        top = @max(top, m.verts[id][1]);
    };
    m.mid_y = @divTrunc(top, 2);
}
