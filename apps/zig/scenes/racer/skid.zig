// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; MIT, Copyright (c) freds72; licence text at the head of frame.zig):
// make_skidmarks and its emitters.
//
// RACER: skidmarks. A wheel that slides emits to its own emitter every tick; the emitter lays a
// new mark every 10 ticks (or when the ground face changes) and stretches the current one's
// leading edge to the wheel in between, as the original does. A mark lives 60 ticks, the ring
// holds 24 (4 wheels x 6 marks in flight). A mark is drawn as a quad on the ground face it was
// laid on, with that face's depth key (so it paints right after the road quad and decals, before
// anything nearer). The drawn width is 0.04 unit, not the original's 0.01: a Q7 vertex has a
// 0.0078 grid. No ZigOS import.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const car = @import("car.zig");
const carmodel = @import("carmodel.zig");
const fix = @import("fix.zig");
const frame = @import("frame.zig");
const ground = @import("ground.zig");
const project = @import("project.zig");
const trk = @import("trk.zig");
const vec = @import("vec.zig");
const xf = @import("xform.zig");
const V = vec.V;

pub const MAXM = 24;
pub const TTL = 60;
pub const EVERY = 10;
const WIDTH = fix.lit(0.04);

pub const Mark = struct { c: [4]V = undefined, ttl: u8 = 0, face: u16 = 0, live: bool = false };

/// One wheel's state between ticks (the original's closure variables).
pub const Emitter = struct {
    expect: u32 = 0, // the tick this emitter must be called on to continue its line
    start: ?V = null,
    old: u16 = 0,
    right: ?V = null,
    cur: ?usize = null,
};

pub const Skid = struct {
    t: u32 = 1,
    marks: [MAXM]Mark = [_]Mark{.{}} ** MAXM,
    verts: [MAXM * 4]trk.Vert = undefined,
    em: [4]Emitter = [_]Emitter{.{}} ** 4,

    pub fn live(self: *const Skid) usize {
        var n: usize = 0;
        for (self.marks) |m| n += @intFromBool(m.live);
        return n;
    }

    /// The tick's end: age the marks and drop the old ones.
    pub fn update(self: *Skid) void {
        self.t += 1;
        for (&self.marks) |*m| {
            if (!m.live) continue;
            m.ttl += 1;
            if (m.ttl > TTL) m.live = false;
        }
    }

    fn alloc(self: *Skid) ?usize {
        var oldest: ?usize = null;
        for (&self.marks, 0..) |*m, i| {
            if (!m.live) return i;
            if (oldest == null or m.ttl > self.marks[oldest.?].ttl) oldest = i;
        }
        return oldest; // the ring is full: the oldest mark makes room
    }

    /// Wheel `k` is on the ground face `newf` at `pos` (Q16, world). `t` is the track, for the face normal.
    pub fn emit(self: *Skid, t: *const trk.Track, k: usize, pos: V, newf: u16) void {
        const e = &self.em[k];
        if (e.expect != self.t) e.* = .{};
        if (e.start == null) {
            e.start = pos;
            e.old = newf;
        }
        e.expect = self.t + 1;
        if (e.expect % EVERY == 0 or e.old != newf) {
            const fwd = vec.normz(vec.between(e.start.?, pos));
            e.right = vec.cross(fwd, ground.poly(t, e.old).n);
            e.cur = self.lay(pos, e.right.?, e.old);
            e.start = pos;
            e.old = newf;
        } else if (e.right) |r| {
            if (e.cur) |i| self.stretch(i, pos, r);
        }
    }

    fn lay(self: *Skid, pos: V, right: V, face: u16) ?usize {
        const i = self.alloc() orelse return null;
        const a = vec.add(pos, right, -WIDTH);
        const b = vec.add(pos, right, WIDTH);
        self.marks[i] = .{ .c = .{ a, b, b, a }, .ttl = 0, .face = face, .live = true };
        return i;
    }

    fn stretch(self: *Skid, i: usize, pos: V, right: V) void {
        const m = &self.marks[i];
        if (!m.live) return;
        m.c[0] = vec.add(pos, right, -WIDTH); // the leading edge: left, right of the quad's winding
        m.c[1] = vec.add(pos, right, WIDTH);
    }

    /// The tick's emission of one car: each sliding wheel (front pair, rear pair) lays on the ground face under the car.
    pub fn emitCar(self: *Skid, t: *const trk.Track, c: *const car.Car) void {
        const old = c.old orelse return;
        const ax = c.axes();
        for (carmodel.WHEELS, 0..) |w, k| {
            if (!(if (k < 2) c.front_slide else c.rear_slide)) continue;
            self.emit(t, k, vec.add(vec.add(c.pos, ax.right, w[0]), ax.fwd, w[2]), old);
        }
    }

    /// Push every mark whose face was kept this frame, with that face's key (so it follows the road quad).
    pub fn draw(self: *Skid, fr: *frame.Frame, cache: *xf.Cache, v: *const cam.View) void {
        cache.next();
        for (self.marks, 0..) |m, i| {
            if (!m.live) continue;
            const key = fr.faceKey(m.face) orelse continue;
            for (m.c, 0..) |p, j| self.verts[i * 4 + j] = .{ @intCast(p[0] >> 9), @intCast(p[1] >> 9), @intCast(p[2] >> 9) };
            const base: u16 = @intCast(i * 4);
            const f = trk.Face{ .v = .{ base, base + 1, base + 2, base + 3 }, .flags = trk.FLAG_DUAL, .nv = 4, .colour = carmodel.SKID_COLOUR,
                .inner_n = 0, .n = .{ 0, 0, 0 }, .borders = 0, .cp = 0, .inner_first = 0, ._p1 = 0 };
            _ = project.build(fr, cache, &self.verts, v, &f, .{ .fixed = key });
        }
    }
};
