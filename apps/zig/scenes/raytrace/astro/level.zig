// Mode 3's arrays: one Level per ray depth (the batch's primary rays; the chrome
// sphere's reflections), the shadow rays' set, all f64 arrays of the batch's
// capacity in the cart's RAM (8-aligned: hwAstro refuses less).
const zg = @import("zigos");
const std = @import("std");
const vq = @import("vq.zig");
const Hit = @import("march.zig").Hit;
const Shade = @import("../shade.zig").Shade;
const F = vq.F;

pub const K_SKY: u8 = 0;
pub const K_FLOOR: u8 = 1;
pub const K_SPHERE: u8 = 2; // which one: hits[k].id

/// Rays o + t d lit from l (each ray its own light: the sample's point of the light disc).
pub const Rays = struct { o: [3]F, d: [3]F, l: [3]F };

pub const Level = struct {
    r: Rays,
    // the floor: its distance, the point there; the sky's intensity; the fog (all x256)
    tf: F,
    fx: F,
    fz: F,
    qs: F,
    fog: F,
    // a sphere hit: its t; the sphere's centre and 1/r (gathered by id); the lifted point,
    // the normal, n.l, n.d, the highlight term, the lit intensities (x256), a scratch
    ht: F,
    c: [3]F,
    ir: F,
    p: [3]F,
    n: [3]F,
    diff: F,
    nd: F,
    sp: F,
    litf: F,
    lits: F,
    s: F,
    refl: [3]F, // the reflected direction (the primary level's chrome rays)
    tmax: []u64,
    hits: []Hit,
    kind: []u8,
    lit: []bool, // the shadow ray found the light
    owner: []u8, // a reflection ray's primary ray
    out: []Shade,

    pub fn init(self: *Level, cap: u32) void {
        inline for (0..3) |a| {
            self.r.o[a] = alloc(cap);
            self.r.d[a] = alloc(cap);
            self.r.l[a] = alloc(cap);
        }
        inline for (std.meta.fields(Level)) |f| {
            if (f.type == F) @field(self, f.name) = alloc(cap);
            if (f.type == [3]F) inline for (0..3) |a| {
                @field(self, f.name)[a] = alloc(cap);
            };
        }
        self.tmax = zg.mem.mustAlloc(u64, cap);
        self.hits = zg.mem.mustAlloc(Hit, cap);
        self.kind = zg.mem.mustAlloc(u8, cap);
        self.lit = zg.mem.mustAlloc(bool, cap);
        self.owner = zg.mem.mustAlloc(u8, cap);
        self.out = zg.mem.mustAlloc(Shade, cap);
    }
};

/// The shadow rays: from a floor point or a lit sphere point toward the light.
pub const Shadow = struct {
    o: [3]F,
    d: [3]F,
    hits: []Hit,
    owner: []u8, // the ray of the level being shaded

    pub fn init(self: *Shadow, cap: u32) void {
        inline for (0..3) |a| {
            self.o[a] = alloc(cap);
            self.d[a] = alloc(cap);
        }
        self.hits = zg.mem.mustAlloc(Hit, cap);
        self.owner = zg.mem.mustAlloc(u8, cap);
    }
};

pub fn alloc(cap: u32) F {
    return zg.mem.mustAlloc(f64, cap).ptr;
}
