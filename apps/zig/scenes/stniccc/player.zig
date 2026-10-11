// --------------------------------------------------------------------------
// STNICCC frame player: draws ANY frame of the stream, not only the next one,
// at any size. The stream is a chain of deltas (805 of its 1800 frames paint
// over the frame before), so frame n is rebuilt by replaying from the last
// frame at or before n that clears the screen. Each frame's offset, clear flag
// and palette are recorded the first time it is decoded, which is what makes
// seeking back (the rewind) cheap. Pure (no ZigOS); tested at the bottom.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("stream.zig");
const polyfill = @import("polyfill.zig");

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

    pub fn init(self: *Player, source: st.Source, buf: *[st.BLOCK]u8, index: *Index) void {
        self.stream = .{ .source = source, .buf = buf };
        self.index = index;
        self.known = 0;
        self.next = 0;
        self.total = 0;
        self.shown = null;
    }

    pub fn palette(self: *const Player, n: u32) *const [16]u16 {
        return &self.index.palettes[n];
    }

    /// Draw frame n. The next frame after the one on screen decodes just that
    /// frame; anything else replays from the last clear frame at or before n.
    pub fn show(self: *Player, n: u32, view: View) st.Error!void {
        try self.indexTo(n);
        const sequential = if (self.shown) |s| n == s + 1 else false;
        var f = if (sequential) n else self.lastClear(n);
        while (f <= n) : (f += 1) try self.draw(f, view);
        self.shown = n;
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
    for (0..t.h) |y| @memset(t.px[y * t.stride + t.ox ..][0..t.w], 0);
}

comptime {
    // A decoded polygon is copied into a polyfill point list before filling.
    if (st.MAX_POLY_VERTS > polyfill.MAX_VERTS) @compileError("polyfill.MAX_VERTS too small");
}
