// --------------------------------------------------------------------------
// STNICCC frame player: draws ANY frame of the stream, not only the next one,
// at any size. The stream is a chain of deltas (805 of its 1800 frames paint
// over the frame before), so frame n is rebuilt by replaying from the last
// frame at or before n that clears the screen. Each frame's offset, clear flag
// and palette are recorded the first time it is decoded, which is what makes
// seeking back (the rewind) cheap, and with a Snaps (snaps.zig) a seek also
// starts from a kept keyframe instead of the clear frame. Pure (no ZigOS);
// tested in player_test.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("stream.zig");
const polyfill = @import("polyfill.zig");
const snaps_mod = @import("snaps.zig");

pub const MAX_FRAMES: u32 = 1800;
pub const SRC_W: u32 = 256; // the stream's coordinate space
pub const SRC_H: u32 = 200;

/// Where a frame is drawn: the fill target, and the size 256x200 is scaled to.
/// Scaling the VERTICES (not the pixels) keeps the edges sharp at any size.
pub const View = struct { target: polyfill.Target, w: u32, h: u32 };

/// What is recorded the first time a frame is decoded (66,600 B). The caller
/// owns it: the scene takes it from the cart RAM arena, a test from its stack.
pub const Index = struct {
    offsets: [MAX_FRAMES]u32,
    clears: [MAX_FRAMES]bool,
    palettes: [MAX_FRAMES][16]u16, // the palette in effect once that frame is drawn
};

pub const Player = struct {
    stream: st.Stream,
    index: *Index,
    known: u32, // frames 0..known-1 are indexed
    next: u32, // stream offset of frame `known`
    total: u32, // frame count once $FD has been read, else 0
    shown: ?u32, // the frame on screen, or null when the screen was disturbed
    snaps: ?*snaps_mod.Snaps, // keyframes for seeks; null: a seek replays from the clear frame
    drawn: u32, // frames the last show() drew: what a seek costs

    pub fn init(self: *Player, source: st.Source, buf: *[st.BLOCK]u8, index: *Index) void {
        self.stream = .{ .source = source, .buf = buf };
        self.index = index;
        self.known = 0;
        self.next = 0;
        self.total = 0;
        self.shown = null;
        self.snaps = null;
        self.drawn = 0;
    }

    pub fn palette(self: *const Player, n: u32) *const [16]u16 {
        return &self.index.palettes[n];
    }

    /// Draw frame n. The next frame after the one on screen decodes just that
    /// frame; anything else replays from the last clear frame at or before n,
    /// or from the latest keyframe kept since it.
    pub fn show(self: *Player, n: u32, view: View) st.Error!void {
        try self.indexTo(n);
        const sequential = if (self.shown) |s| n == s + 1 else false;
        var f = if (sequential) n else self.seekFrom(n, view);
        self.drawn = 0;
        while (f <= n) : (f += 1) {
            try self.draw(f, view);
            self.keep(f, view);
            self.drawn += 1;
        }
        self.shown = n;
    }

    // The first frame a seek to n draws: after the latest keyframe since n's
    // clear frame, painted back first, or else that clear frame.
    fn seekFrom(self: *Player, n: u32, view: View) u32 {
        const c = self.lastClear(n);
        const s = self.snaps orelse return c;
        s.bind(snaps_mod.keyOf(view.target, view.w, view.h));
        const i = s.find(c, n) orelse return c;
        s.restore(i, view.target);
        return s.frame(i) + 1;
    }

    // Keep every snaps.EVERY-th frame of a delta chain, as just drawn.
    fn keep(self: *Player, f: u32, view: View) void {
        const s = self.snaps orelse return;
        const into = f - self.lastClear(f);
        if (into == 0 or into % snaps_mod.EVERY != 0) return;
        s.bind(snaps_mod.keyOf(view.target, view.w, view.h));
        s.save(f, view.target);
    }

    fn lastClear(self: *const Player, n: u32) u32 {
        var f = n;
        while (f > 0 and !self.index.clears[f]) f -= 1;
        return f;
    }

    // Decode frames up to n without drawing, recording where each one starts.
    fn indexTo(self: *Player, n: u32) st.Error!void {
        if (n >= MAX_FRAMES or (self.total != 0 and n >= self.total)) return error.Truncated;
        var pal: [16]u16 = if (self.known == 0) [_]u16{0} ** 16 else self.index.palettes[self.known - 1];
        var poly: st.Poly = undefined;
        while (self.known <= n) {
            const f = self.known;
            self.stream.seek(self.next);
            const flags = try self.stream.beginFrame(&pal);
            while (try self.stream.nextPoly(&poly)) {}
            self.index.offsets[f] = self.next;
            self.index.clears[f] = flags.clear;
            self.index.palettes[f] = pal;
            self.next = self.stream.pos;
            self.known = f + 1;
            if (self.stream.done) {
                self.total = self.known;
                if (self.known <= n) return error.Truncated;
            }
        }
    }

    fn draw(self: *Player, f: u32, view: View) st.Error!void {
        self.stream.seek(self.index.offsets[f]);
        var ignored: [16]u16 = undefined; // the recorded palette is authoritative
        const flags = try self.stream.beginFrame(&ignored);
        if (flags.clear) clear(view.target);
        var poly: st.Poly = undefined;
        var pts: [st.MAX_POLY_VERTS]polyfill.Point = undefined;
        while (try self.stream.nextPoly(&poly)) {
            for (poly.pts[0..poly.n], 0..) |p, i| pts[i] = scale(p, view);
            polyfill.fill(view.target, pts[0..poly.n], poly.color);
        }
    }
};

fn scale(p: st.Point, view: View) polyfill.Point {
    return .{
        .x = @intCast((@as(u32, p.x) * view.w + SRC_W / 2) / SRC_W),
        .y = @intCast((@as(u32, p.y) * view.h + SRC_H / 2) / SRC_H),
    };
}

fn clear(t: polyfill.Target) void {
    polyfill.rect(t, 0, 0, t.w, t.h, 0);
}

comptime {
    // A decoded polygon is copied into a polyfill point list before filling.
    if (st.MAX_POLY_VERTS > polyfill.MAX_VERTS) @compileError("polyfill.MAX_VERTS too small");
}
