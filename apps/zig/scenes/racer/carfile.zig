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
//       12..18 as RGBX when flag PALETTE, CRC-32 of the rest), then that many v1 records. Model 0 is
//       the player's car, models 1.. the AI cars' in turn (each its own colours: a set replaces the
//       liveries' recolour by its own models and ramps).
//
// No ZigOS import: carfile_test.zig runs it natively.
// --------------------------------------------------------------------------
const std = @import("std");
const trk = @import("trk.zig");

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
pub const Error = error{ Truncated, BadMagic, BadVersion, BadCrc, BadBlock, BadFace, BadParts };

/// The parts, in the file's order: the near model (wheels, hull, cabin, wing), the shadow quad, the far model.
pub const Part = enum(u3) { wheels, hull, cabin, wing, shadow, lod1 };

pub const Model = struct {
    verts: []const trk.Vert,
    faces: []const trk.Face,
    end: [6]u16,
    wing_z: i32, // Q7 forward: carview swaps the cabin and the wing by the eye's side of it
    mid_y: i32, // Q7: half the hull's height, the depth every face of the car is keyed by

    pub fn range(self: *const Model, p: Part) []const trk.Face {
        const i = @intFromEnum(p);
        return self.faces[if (i == 0) 0 else self.end[i - 1]..self.end[i]];
    }
};

pub const Set = struct {
    models: [MAX_MODELS]Model = undefined,
    n: usize = 0,
    palette: ?[RAMPS][3]u8 = null,

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

/// What the cart relies on: a hull and a far model, ONE shadow quad (flagged, and the only flagged face), every face 3-4 ids in range.
fn check(m: *Model) Error!void {
    if (m.range(.hull).len == 0 or m.range(.lod1).len == 0) return error.BadParts;
    const sh = m.range(.shadow);
    if (sh.len != 1 or sh[0].nv != 4 or sh[0].flags & FLAG_SHADOW == 0) return error.BadParts;
    for (m.faces, 0..) |f, i| {
        if (f.nv < 3 or f.nv > 4) return error.BadFace;
        for (f.v) |id| if (id >= m.verts.len) return error.BadFace; // the padding ids too: all four are read
        if ((f.flags & FLAG_SHADOW != 0) != (i == m.end[@intFromEnum(Part.shadow)] - 1)) return error.BadParts;
    }
    var top: i32 = 0;
    for (m.range(.hull)) |f| for (f.v[0..f.nv]) |id| {
        top = @max(top, m.verts[id][1]);
    };
    m.mid_y = @divTrunc(top, 2);
}
