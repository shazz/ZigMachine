// --------------------------------------------------------------------------
// RACER: tyre smoke (R82 bug pass, Matt 27 Nov: "in the real game braking/skidding makes light smoke
// puffs, shadow-like, not black traces"). It replaces freds72's skidmarks (M2's skid.zig): a sliding
// wheel of the player's car puffs every EVERY ticks at its DRAWN place (freds72's wheel points times the
// GT's 2x and the car scale); a puff lives TTL ticks, grows and rises, and is drawn as a hexagon facing
// the camera (two trapezoids sharing their middle edge, so no pixel is lightened twice) by LIGHTENING
// what is under it one level up its ramp: the shadow's index trick the other way, real transparency, no
// dither (shadow.lightSpan). Its key is its own depth, never below the ground face it rose from: behind
// the car (nearer the chase camera) it veils the car, in front of it the car hides it. No ZigOS import.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const car = @import("car.zig");
const carmodel = @import("carmodel.zig");
const fix = @import("fix.zig");
const frame = @import("frame.zig");
const project = @import("project.zig");
const trk = @import("trk.zig");
const vec = @import("vec.zig");
const xf = @import("xform.zig");
const V = vec.V;
const lit = fix.lit;

pub var hidden = false; // key 1: the smoke not drawn (racer_drive.mjs compares a lap with and without it)
pub const MAXP = 24; // puffs in flight: 2 sliding wheels a car, a puff every EVERY ticks, TTL ticks each (and room)
pub const TTL = 16; // ~0.5 s
pub const EVERY = 2;
pub const VERTS = 6; // a hexagon a puff
const R0 = lit(0.06); // the radius at birth and at the end, freds72 units (times the drawn scale)
const R1 = lit(0.16);
const RISE = lit(0.006); // a tick
const DRAWN = 2; // the GT's tyres are drawn twice freds72's wheel points (carmodel.WHEELS)

pub const Puff = struct { pos: V = .{ 0, 0, 0 }, face: u16 = 0, age: u8 = 0, size: i32 = fix.ONE, live: bool = false };

pub const Smoke = struct {
    t: u32 = 0,
    puffs: [MAXP]Puff = [_]Puff{.{}} ** MAXP,
    next: usize = 0,
    verts: [MAXP * VERTS]trk.Vert = undefined,

    pub fn live(self: *const Smoke) usize {
        var n: usize = 0;
        for (self.puffs) |p| n += @intFromBool(p.live);
        return n;
    }

    /// The tick's end: age the puffs and drop the old ones.
    pub fn update(self: *Smoke) void {
        self.t +%= 1;
        for (&self.puffs) |*p| {
            if (!p.live) continue;
            p.age += 1;
            if (p.age >= TTL) p.live = false;
        }
    }

    /// A puff at `pos` (Q16 world, on the ground face `face`); the ring's oldest makes room.
    pub fn puff(self: *Smoke, pos: V, face: u16, size: i32) void {
        self.puffs[self.next] = .{ .pos = pos, .face = face, .size = size, .live = true };
        self.next = (self.next + 1) % MAXP;
    }

    /// The tick's emission of one car: each sliding wheel pair (front, rear) puffs at its drawn wheels, every EVERY ticks.
    pub fn emitCar(self: *Smoke, c: *const car.Car) void {
        const face = c.old orelse return;
        if (self.t % EVERY != 0) return;
        const ax = c.axes();
        for (carmodel.WHEELS, 0..) |w, k| {
            if (!(if (k < 2) c.front_slide else c.rear_slide)) continue;
            const x = fix.mul(w[0] * DRAWN, c.size);
            const z = fix.mul(w[2] * DRAWN, c.size);
            self.puff(vec.add(vec.add(c.pos, ax.right, x), ax.fwd, z), face, c.size);
        }
    }

    /// Push every live puff: a hexagon facing the camera, keyed by its depth (never below its ground face's key).
    pub fn draw(self: *Smoke, fr: *frame.Frame, cache: *xf.Cache, v: *const cam.View) void {
        if (hidden) return;
        cache.next();
        for (self.puffs, 0..) |p, i| {
            if (!p.live) continue;
            const r = fix.mul(R0 + @divTrunc((R1 - R0) * p.age, TTL), p.size);
            const c = V{ p.pos[0], p.pos[1] + r + fix.mul(RISE * p.age, p.size), p.pos[2] };
            const z = viewZ(v, c);
            if (z <= 0) continue;
            var key = project.depthKey(z);
            if (fr.faceKey(p.face)) |k| key = @max(key, k);
            self.hexagon(i, c, r, v);
            const base: u16 = @intCast(i * VERTS);
            for ([2][4]u16{ .{ 0, 1, 2, 3 }, .{ 0, 3, 4, 5 } }) |q| {
                const f = trk.Face{ .v = .{ base + q[0], base + q[1], base + q[2], base + q[3] }, .flags = trk.FLAG_DUAL, .nv = 4, .colour = 0,
                    .inner_n = 0, .n = .{ 0, 0, 0 }, .borders = 0, .cp = 0, .inner_first = 0, .alt = 0 };
                _ = project.build(fr, cache, &self.verts, v, &f, .{ .fixed = key, .light = true });
            }
        }
    }

    /// The hexagon's six corners (Q7 world) around `c` in the camera's right / up plane: left, the top two, right, the
    /// bottom two; [0..3] is the top half, [0, 3, 4, 5] the bottom half (the edge 0-3 shared).
    fn hexagon(self: *Smoke, i: usize, c: V, r: i32, v: *const cam.View) void {
        const right = V{ v.r[0][0] >> 9, v.r[0][1] >> 9, v.r[0][2] >> 9 };
        const up = V{ v.r[1][0] >> 9, v.r[1][1] >> 9, v.r[1][2] >> 9 };
        const h = fix.mul(r, lit(0.866));
        const pts = [6][2]i32{ .{ -r, 0 }, .{ -(r >> 1), h }, .{ r >> 1, h }, .{ r, 0 }, .{ r >> 1, -h }, .{ -(r >> 1), -h } };
        for (pts, 0..) |q, j| {
            const p = vec.add(vec.add(c, right, q[0]), up, q[1]);
            self.verts[i * VERTS + j] = .{ @intCast(p[0] >> 9), @intCast(p[1] >> 9), @intCast(p[2] >> 9) };
        }
    }
};

/// The view depth (Q16) of a world point (Q16): the forward row (Q25) against it, as cam.view's translation is built.
fn viewZ(v: *const cam.View, p: V) i32 {
    const row = v.r[2];
    const d = (@as(i64, row[0]) * p[0] + @as(i64, row[1]) * p[1] + @as(i64, row[2]) * p[2]) >> 25;
    return v.t[2] + @as(i32, @truncate(d));
}
