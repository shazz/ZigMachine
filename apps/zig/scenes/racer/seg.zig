// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; MIT, Copyright (c) freds72; licence text at the head of frame.zig):
// make_track.
//
// RACER: where a car is on the track. The racing line is a ring of segments, each a quad between
// a left and a right vertex (the track binary's `lr` block) with a plane normal turned out of its
// left-to-right edge. `update` walks the segment index forward or back when the car passes a
// segment's plane, then reports `u` (segment + the fraction along it) and `v` (0 left .. 1 right,
// as a Q16 ratio). Flat segments (a plane the next quad lies in) are skipped, as in the original;
// the walk is bounded by the ring so a degenerate track cannot loop forever.
// No ZigOS import.
// --------------------------------------------------------------------------
const fix = @import("fix.zig");
const ground = @import("ground.zig");
const trk = @import("trk.zig");
const vec = @import("vec.zig");
const V = vec.V;

const FLAT = fix.lit(0.001);

pub const Quad = struct { n: V, l: V, r: V };
pub const Corners = struct { l: V, r: V };
pub const MAXSEG = 256;

pub const TrackPos = struct {
    t: *const trk.Track,
    segment: i32,
    q0: Quad,
    q1: Quad,
    u: i32,
    v: i32 = 0,

    pub fn init(t: *const trk.Track, segment: i32) TrackPos {
        return .{ .t = t, .segment = segment, .q0 = quad(t, segment), .q1 = quad(t, segment + 1), .u = segment << 16 };
    }

    fn getD(self: *const TrackPos, pos: V) i32 {
        const d0 = vec.dot(vec.between(pos, self.q0.l), self.q0.n);
        return fix.div(d0, d0 -% vec.dot(vec.between(pos, self.q1.l), self.q1.n));
    }

    fn flat(self: *const TrackPos) bool {
        const q0 = &self.q0;
        const q1 = &self.q1;
        return fix.abs(vec.dot(vec.between(q0.l, q1.l), q0.n)) < FLAT or fix.abs(vec.dot(vec.between(q0.l, q1.r), q0.n)) < FLAT;
    }

    fn step(self: *TrackPos, dir: i32) void {
        var guard = self.t.lr.len;
        while (guard > 0) : (guard -= 1) {
            self.segment += dir;
            if (dir > 0) {
                self.q0 = self.q1;
                self.q1 = quad(self.t, self.segment + 1);
            } else {
                self.q1 = self.q0;
                self.q0 = quad(self.t, self.segment);
            }
            if (!self.flat()) return;
        }
    }

    /// `get_next(offset)`: the corners `offset` segments past the current one.
    pub fn next(self: *const TrackPos, offset: i32) Corners {
        return corners(self.t, self.segment + offset);
    }

    pub fn update(self: *TrackPos, pos: V) void {
        var d = self.getD(pos);
        if (d > fix.ONE) {
            self.step(1);
        } else if (d < 0) self.step(-1);
        d = self.getD(pos);
        self.u = (self.segment << 16) +% fix.mod(d, fix.ONE);
        const ll = vec.lerp(self.q0.l, self.q1.l, d);
        const rr = vec.lerp(self.q0.r, self.q1.r, d);
        const w = vec.between(ll, rr);
        self.v = fix.div(vec.dot(w, vec.between(ll, pos)), vec.dot(w, w));
    }
};

/// The left / right vertices of ring segment `i` (any integer: it wraps): `to_v` of the original, minus the normal.
pub fn corners(t: *const trk.Track, i: i32) Corners {
    const s = t.lr[@intCast(@mod(i, @as(i32, @intCast(t.lr.len))))];
    return .{ .l = ground.vertex(t, s[0]), .r = ground.vertex(t, s[1]) };
}

/// The length of each side of every ring segment (`get_length`), computed once with the original's `v_len`.
pub const Lens = struct {
    v: [MAXSEG][2]i32 = undefined,
    n: usize = 0,

    pub fn init(t: *const trk.Track) error{TooManySegments}!Lens {
        if (t.lr.len > MAXSEG) return error.TooManySegments;
        var self = Lens{ .n = t.lr.len };
        for (0..t.lr.len) |i| {
            const a = corners(t, @intCast(i));
            const b = corners(t, @intCast(i + 1));
            self.v[i] = .{ vec.len(vec.between(a.l, b.l)), vec.len(vec.between(a.r, b.r)) };
        }
        return self;
    }

    /// Segment `i`'s left and right side lengths (any integer: it wraps).
    pub fn at(self: *const Lens, i: i32) [2]i32 {
        return self.v[@intCast(@mod(i, @as(i32, @intCast(self.n))))];
    }
};

/// Segment `i` of the ring (any integer: it wraps).
pub fn quad(t: *const trk.Track, i: i32) Quad {
    const n: i32 = @intCast(t.lr.len);
    const s = t.lr[@intCast(@mod(i, n))];
    const l = ground.vertex(t, s[0]);
    const r = ground.vertex(t, s[1]);
    return .{ .n = vec.normz(vec.ortho(vec.between(l, r))), .l = l, .r = r };
}
